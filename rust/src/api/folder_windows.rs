use anyhow::{bail, Context, Result};
use cap_std::fs::{Dir, OpenOptions, OpenOptionsExt};
use std::{
    ffi::c_void,
    fs::File,
    io,
    mem::{offset_of, size_of},
    os::windows::{
        ffi::OsStrExt,
        fs::{MetadataExt, OpenOptionsExt as _},
        io::AsRawHandle,
    },
    path::Path,
};

pub(super) type SpaceHandle = *mut c_void;

#[derive(Clone, Copy, PartialEq, Eq)]
#[repr(C)]
pub(super) struct FileIdentity {
    volume: u64,
    id: [u8; 16],
}

#[repr(C)]
struct RenameInfo {
    flags: u32,
    directory: *mut c_void,
    name_length: u32,
    name: [u16; 1],
}

#[repr(C)]
struct IoStatusBlock {
    status_or_pointer: usize,
    information: usize,
}

#[repr(C)]
struct VolumeSize {
    total_units: i64,
    available_units: i64,
    sectors_per_unit: u32,
    bytes_per_sector: u32,
}

#[link(name = "kernel32")]
unsafe extern "system" {
    fn GetFileInformationByHandleEx(
        file: *mut c_void,
        class: i32,
        info: *mut c_void,
        size: u32,
    ) -> i32;
    fn SetFileInformationByHandle(
        file: *mut c_void,
        class: i32,
        info: *const c_void,
        size: u32,
    ) -> i32;
}

#[link(name = "ntdll")]
unsafe extern "system" {
    fn NtQueryVolumeInformationFile(
        file: *mut c_void,
        status: *mut IoStatusBlock,
        info: *mut c_void,
        size: u32,
        class: i32,
    ) -> i32;
    fn RtlNtStatusToDosError(status: i32) -> u32;
}

const OPEN_FLAGS: u32 = 0x0020_0000 | 0x0200_0000;
const REPARSE_POINT: u32 = 0x400;
const DELETE: u32 = 0x0001_0000;
const GENERIC_READ: u32 = 0x8000_0000;

fn check_file(file: File, directory: bool) -> Result<File> {
    let metadata = file.metadata()?;
    if metadata.file_attributes() & REPARSE_POINT != 0 {
        bail!("symbolic links and reparse points are not supported")
    }
    if directory && !metadata.is_dir() || !directory && !metadata.is_file() {
        bail!("unsupported folder item")
    }
    Ok(file)
}

pub(super) fn open_nofollow(parent: Option<&Dir>, path: &Path, directory: bool) -> Result<File> {
    // Denying directory deletion keeps path-based mkdir inside the held parent.
    let share = if directory { 3 } else { 7 };
    let file = match parent {
        Some(parent) => parent
            .open_with(
                path,
                OpenOptions::new()
                    .read(true)
                    .share_mode(share)
                    .custom_flags(OPEN_FLAGS),
            )?
            .into_std(),
        None => std::fs::OpenOptions::new()
            .read(true)
            .share_mode(share)
            .custom_flags(OPEN_FLAGS)
            .open(path)?,
    };
    check_file(file, directory)
}

pub(super) fn open_for_publication(parent: &Dir, name: &str) -> Result<File> {
    let file = parent
        .open_with(
            name,
            OpenOptions::new()
                .access_mode(GENERIC_READ | DELETE)
                .share_mode(7)
                .custom_flags(OPEN_FLAGS),
        )?
        .into_std();
    check_file(file, true)
}

pub(super) fn space_handle(file: &File) -> SpaceHandle {
    file.as_raw_handle()
}

pub(super) fn file_identity(file: &File) -> Result<FileIdentity> {
    let mut info = FileIdentity {
        volume: 0,
        id: [0; 16],
    };
    if unsafe {
        GetFileInformationByHandleEx(
            file.as_raw_handle(),
            18,
            (&mut info as *mut FileIdentity).cast(),
            size_of::<FileIdentity>() as u32,
        )
    } == 0
    {
        return Err(io::Error::last_os_error()).context("cannot identify folder item");
    }
    Ok(info)
}

pub(super) fn available_space(file: SpaceHandle) -> Result<u64> {
    let mut status = IoStatusBlock {
        status_or_pointer: 0,
        information: 0,
    };
    let mut size = VolumeSize {
        total_units: 0,
        available_units: 0,
        sectors_per_unit: 0,
        bytes_per_sector: 0,
    };
    let result = unsafe {
        NtQueryVolumeInformationFile(
            file,
            &mut status,
            (&mut size as *mut VolumeSize).cast(),
            size_of::<VolumeSize>() as u32,
            3,
        )
    };
    if result < 0 {
        let code = unsafe { RtlNtStatusToDosError(result) };
        return Err(io::Error::from_raw_os_error(code as i32)).context("cannot check free space");
    }
    Ok(u64::try_from(size.available_units)?
        .saturating_mul(size.sectors_per_unit as u64)
        .saturating_mul(size.bytes_per_sector as u64))
}

pub(super) fn make_subdir(parent: &Dir, name: &str) -> Result<Dir> {
    match parent.create_dir(name) {
        Ok(()) => {}
        Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {}
        Err(error) => return Err(error.into()),
    }
    Ok(Dir::from_std_file(open_nofollow(
        Some(parent),
        Path::new(name),
        true,
    )?))
}

pub(super) fn create_file(parent: &Dir, name: &str) -> Result<File> {
    let file = parent
        .open_with(
            name,
            OpenOptions::new()
                .write(true)
                .create_new(true)
                .custom_flags(OPEN_FLAGS),
        )?
        .into_std();
    check_file(file, false)
}

pub(super) fn rename_exclusive(
    _from_dir: &Dir,
    _from: &str,
    to_dir: &Dir,
    to: &str,
    source: &File,
) -> io::Result<()> {
    let name: Vec<_> = std::ffi::OsStr::new(to).encode_wide().collect();
    let name_offset = offset_of!(RenameInfo, name);
    let length = (name_offset + name.len() * size_of::<u16>()).max(size_of::<RenameInfo>());
    let mut buffer = vec![0usize; length.div_ceil(size_of::<usize>())];
    let info = buffer.as_mut_ptr().cast::<RenameInfo>();
    unsafe {
        (*info).flags = 0;
        (*info).directory = to_dir.as_raw_handle();
        (*info).name_length = (name.len() * size_of::<u16>()) as u32;
        std::ptr::copy_nonoverlapping(
            name.as_ptr(),
            buffer.as_mut_ptr().cast::<u8>().add(name_offset).cast(),
            name.len(),
        );
        if SetFileInformationByHandle(source.as_raw_handle(), 3, info.cast(), length as u32) != 0 {
            Ok(())
        } else {
            Err(io::Error::last_os_error())
        }
    }
}
