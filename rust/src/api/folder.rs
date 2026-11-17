use anyhow::{bail, Context, Result};
use cap_std::fs::Dir;
use std::{
    collections::{HashMap, HashSet},
    fs::File,
    io::{Read, Seek, SeekFrom, Write},
    path::Path,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
};
use unicode_normalization::UnicodeNormalization;
use zip::{write::SimpleFileOptions, ZipArchive, ZipWriter};

#[cfg(unix)]
use std::{
    ffi::CString,
    os::fd::{AsRawFd, FromRawFd},
    os::unix::{ffi::OsStrExt, fs::MetadataExt},
};

#[cfg(unix)]
type SpaceHandle = libc::c_int;
#[cfg(unix)]
type FileIdentity = (u64, u64);

#[cfg(windows)]
#[path = "folder_windows.rs"]
mod windows;
#[cfg(windows)]
use windows::{
    available_space, create_file, file_identity, make_subdir, open_for_publication, open_nofollow,
    rename_exclusive, space_handle, FileIdentity, SpaceHandle,
};

const MAX_ENTRIES: usize = 10_000;
const MAX_DEPTH: usize = 64;
const MAX_PATH: usize = 4096;
const MAX_BYTES: u64 = 16 * 1024 * 1024 * 1024;
const SUFFIX: &str = ".vela-folder.zip";

pub struct FolderArchiveJob {
    cancelled: Arc<AtomicBool>,
    started: AtomicBool,
}

pub fn new_folder_archive_job() -> FolderArchiveJob {
    FolderArchiveJob {
        cancelled: Arc::new(AtomicBool::new(false)),
        started: AtomicBool::new(false),
    }
}

impl FolderArchiveJob {
    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Relaxed);
    }

    pub async fn pack(&self, source: String, output_dir: String) -> Result<String> {
        if self.started.swap(true, Ordering::AcqRel) {
            bail!("folder job already started")
        }
        let cancelled = self.cancelled.clone();
        tokio::task::spawn_blocking(move || {
            pack_folder(Path::new(&source), Path::new(&output_dir), &cancelled)
        })
        .await?
    }

    pub async fn restore(&self, archive: String, output_dir: String) -> Result<String> {
        if self.started.swap(true, Ordering::AcqRel) {
            bail!("folder job already started")
        }
        let cancelled = self.cancelled.clone();
        tokio::task::spawn_blocking(move || {
            restore_folder(Path::new(&archive), Path::new(&output_dir), &cancelled)
        })
        .await?
    }
}

fn check_cancel(cancelled: &AtomicBool) -> Result<()> {
    if cancelled.load(Ordering::Relaxed) {
        bail!("folder operation cancelled")
    }
    Ok(())
}

fn valid_component(s: &str) -> bool {
    !s.is_empty()
        && s != "."
        && s != ".."
        && !s.contains(['/', '\\', '\0', ':'])
        && !s.chars().any(char::is_control)
        && valid_platform_component(s)
}

#[cfg(windows)]
fn valid_platform_component(s: &str) -> bool {
    super::windows_file_name::valid_component(s)
}

#[cfg(not(windows))]
fn valid_platform_component(_s: &str) -> bool {
    true
}

#[cfg(unix)]
fn open_nofollow(parent: Option<&Dir>, path: &Path, directory: bool) -> Result<File> {
    let name = CString::new(path.as_os_str().as_bytes())?;
    let flags = libc::O_RDONLY
        | libc::O_CLOEXEC
        | libc::O_NOFOLLOW
        | libc::O_NONBLOCK
        | if directory { libc::O_DIRECTORY } else { 0 };
    let fd = unsafe {
        match parent {
            Some(dir) => libc::openat(dir.as_raw_fd(), name.as_ptr(), flags),
            None => libc::open(name.as_ptr(), flags),
        }
    };
    if fd < 0 {
        return Err(std::io::Error::last_os_error()).context("cannot open folder item safely");
    }
    let file = unsafe { File::from_raw_fd(fd) };
    let meta = file.metadata()?;
    if directory && !meta.is_dir() || !directory && !meta.is_file() {
        bail!("unsupported folder item")
    }
    Ok(file)
}

#[cfg(unix)]
fn space_handle(file: &File) -> SpaceHandle {
    file.as_raw_fd()
}

#[cfg(unix)]
fn file_identity(file: &File) -> Result<FileIdentity> {
    let metadata = file.metadata()?;
    Ok((metadata.dev(), metadata.ino()))
}

#[cfg(unix)]
fn open_for_publication(parent: &Dir, name: &str) -> Result<File> {
    open_nofollow(Some(parent), Path::new(name), true)
}

#[cfg(unix)]
fn available_space(fd: SpaceHandle) -> Result<u64> {
    let mut stat = std::mem::MaybeUninit::<libc::statvfs>::uninit();
    if unsafe { libc::fstatvfs(fd, stat.as_mut_ptr()) } != 0 {
        return Err(std::io::Error::last_os_error()).context("cannot check free space");
    }
    let stat = unsafe { stat.assume_init() };
    Ok((stat.f_bavail as u64).saturating_mul(stat.f_frsize as u64))
}

fn check_space(handle: SpaceHandle) -> Result<()> {
    if available_space(handle)? < 256 * 1024 * 1024 {
        bail!("not enough free space for folder operation")
    }
    Ok(())
}

fn copy_limited<R: Read, W: Write>(
    reader: &mut R,
    writer: &mut W,
    cancelled: &AtomicBool,
    max: u64,
    space_fd: Option<SpaceHandle>,
) -> Result<u64> {
    let mut bytes = 0u64;
    let mut next_space_check = 0u64;
    let mut buffer = [0u8; 64 * 1024];
    loop {
        check_cancel(cancelled)?;
        if bytes >= next_space_check {
            if let Some(fd) = space_fd {
                check_space(fd)?;
            }
            next_space_check = bytes.saturating_add(16 * 1024 * 1024);
        }
        let n = reader.read(&mut buffer)?;
        if n == 0 {
            break;
        }
        bytes = bytes.checked_add(n as u64).context("size overflow")?;
        if bytes > max {
            bail!("folder size limit exceeded")
        }
        writer.write_all(&buffer[..n])?;
    }
    Ok(bytes)
}

fn add_tree(
    dir: &Dir,
    prefix: &str,
    zip: &mut ZipWriter<&mut File>,
    cancelled: &AtomicBool,
    entries: &mut usize,
    total: &mut u64,
    depth: usize,
    seen: &mut HashMap<String, String>,
    space_fd: SpaceHandle,
    archive_id: FileIdentity,
) -> Result<()> {
    if depth > MAX_DEPTH {
        bail!("folder nesting limit exceeded")
    }
    let options = SimpleFileOptions::default()
        .compression_method(zip::CompressionMethod::Deflated)
        .large_file(true);
    for entry in dir.entries()? {
        check_cancel(cancelled)?;
        let entry = entry?;
        if depth >= MAX_DEPTH {
            bail!("folder nesting limit exceeded")
        }
        let os_name = entry.file_name();
        let name = os_name
            .to_str()
            .context("folder contains non-UTF-8 filename")?;
        if !valid_component(name) {
            bail!("invalid folder item name")
        }
        let path = format!("{prefix}/{name}");
        let normalized: String = path.nfkc().flat_map(char::to_lowercase).collect();
        if let Some(existing) = seen.insert(normalized, path.clone()) {
            if existing != path {
                bail!("conflicting folder paths")
            }
        }
        if path.len() > MAX_PATH {
            bail!("folder path too long")
        }
        *entries += 1;
        if *entries > MAX_ENTRIES {
            bail!("too many folder items")
        }
        if *entries % 128 == 0 {
            check_space(space_fd)?;
        }
        let typ = entry.file_type()?;
        if typ.is_symlink() {
            bail!("symbolic links are not supported")
        }
        if typ.is_dir() {
            let child = Dir::from_std_file(open_nofollow(Some(dir), Path::new(name), true)?);
            zip.add_directory(format!("{path}/"), options)?;
            add_tree(
                &child,
                &path,
                zip,
                cancelled,
                entries,
                total,
                depth + 1,
                seen,
                space_fd,
                archive_id,
            )?;
        } else if typ.is_file() {
            let mut file = open_nofollow(Some(dir), Path::new(name), false)?;
            let metadata = file.metadata()?;
            if file_identity(&file)? == archive_id {
                bail!("archive destination cannot be inside the source folder")
            }
            if metadata.len() > MAX_BYTES - *total {
                bail!("folder size limit exceeded")
            }
            zip.start_file(&path, options)?;
            let n = copy_limited(
                &mut file,
                zip,
                cancelled,
                MAX_BYTES - *total,
                Some(space_fd),
            )?;
            *total = total.checked_add(n).context("folder size overflow")?;
        } else {
            bail!("unsupported folder item")
        }
    }
    Ok(())
}

fn pack_folder(source: &Path, output_dir: &Path, cancelled: &AtomicBool) -> Result<String> {
    check_cancel(cancelled)?;
    if output_dir
        .canonicalize()?
        .starts_with(source.canonicalize()?)
    {
        bail!("archive destination cannot be inside the source folder")
    }
    let root = source
        .file_name()
        .and_then(|n| n.to_str())
        .context("invalid folder name")?;
    if !valid_component(root) {
        bail!("invalid folder name")
    }
    let dir = Dir::from_std_file(open_nofollow(None, source, true)?);
    let mut temp = tempfile::NamedTempFile::new_in(output_dir)?;
    let space_fd = space_handle(temp.as_file());
    let archive_id = file_identity(temp.as_file())?;
    check_space(space_fd)?;
    {
        let mut zip = ZipWriter::new(temp.as_file_mut());
        let options = SimpleFileOptions::default()
            .compression_method(zip::CompressionMethod::Deflated)
            .large_file(true);
        zip.add_directory(format!("{root}/"), options)?;
        add_tree(
            &dir,
            root,
            &mut zip,
            cancelled,
            &mut 1,
            &mut 0,
            1,
            &mut HashMap::new(),
            space_fd,
            archive_id,
        )?;
        zip.finish()?;
    }
    check_cancel(cancelled)?;
    for i in 0..10_000 {
        let name = if i == 0 {
            format!("{root}{SUFFIX}")
        } else {
            format!("{root} ({i}){SUFFIX}")
        };
        let path = output_dir.join(name);
        match temp.persist_noclobber(&path) {
            Ok(_) => return Ok(path.to_string_lossy().into_owned()),
            Err(e) if e.error.kind() == std::io::ErrorKind::AlreadyExists => {
                temp = e.file;
            }
            Err(e) => return Err(e.error.into()),
        }
    }
    bail!("cannot create folder archive")
}

#[cfg(target_os = "macos")]
fn rename_exclusive(
    from_dir: &Dir,
    from: &str,
    to_dir: &Dir,
    to: &str,
    _source: &File,
) -> std::io::Result<()> {
    unsafe extern "C" {
        fn renameatx_np(
            fromfd: libc::c_int,
            from: *const libc::c_char,
            tofd: libc::c_int,
            to: *const libc::c_char,
            flags: libc::c_uint,
        ) -> libc::c_int;
    }
    let from = CString::new(from)?;
    let to = CString::new(to)?;
    if unsafe {
        renameatx_np(
            from_dir.as_raw_fd(),
            from.as_ptr(),
            to_dir.as_raw_fd(),
            to.as_ptr(),
            4,
        )
    } == 0
    {
        Ok(())
    } else {
        Err(std::io::Error::last_os_error())
    }
}
#[cfg(any(target_os = "android", target_os = "linux"))]
fn rename_exclusive(
    from_dir: &Dir,
    from: &str,
    to_dir: &Dir,
    to: &str,
    _source: &File,
) -> std::io::Result<()> {
    let from = CString::new(from)?;
    let to = CString::new(to)?;
    if unsafe {
        libc::syscall(
            libc::SYS_renameat2,
            from_dir.as_raw_fd(),
            from.as_ptr(),
            to_dir.as_raw_fd(),
            to.as_ptr(),
            libc::RENAME_NOREPLACE,
        )
    } == 0
    {
        Ok(())
    } else {
        Err(std::io::Error::last_os_error())
    }
}
#[cfg(not(any(
    target_os = "macos",
    target_os = "android",
    target_os = "linux",
    windows
)))]
fn rename_exclusive(
    _from_dir: &Dir,
    _from: &str,
    _to_dir: &Dir,
    _to: &str,
    _source: &File,
) -> std::io::Result<()> {
    Err(std::io::Error::new(
        std::io::ErrorKind::Unsupported,
        "folder restore is not supported on this platform",
    ))
}

#[cfg(unix)]
fn make_subdir(parent: &Dir, name: &str) -> Result<Dir> {
    let name_c = CString::new(name)?;
    if unsafe { libc::mkdirat(parent.as_raw_fd(), name_c.as_ptr(), 0o700) } != 0 {
        let error = std::io::Error::last_os_error();
        if error.kind() != std::io::ErrorKind::AlreadyExists {
            return Err(error.into());
        }
    }
    Ok(Dir::from_std_file(open_nofollow(
        Some(parent),
        Path::new(name),
        true,
    )?))
}

#[cfg(unix)]
fn create_file(parent: &Dir, name: &str) -> Result<File> {
    let name_c = CString::new(name)?;
    let fd = unsafe {
        libc::openat(
            parent.as_raw_fd(),
            name_c.as_ptr(),
            libc::O_WRONLY | libc::O_CREAT | libc::O_EXCL | libc::O_NOFOLLOW | libc::O_CLOEXEC,
            0o600,
        )
    };
    if fd < 0 {
        return Err(std::io::Error::last_os_error()).context("cannot create archive file safely");
    }
    Ok(unsafe { File::from_raw_fd(fd) })
}

struct ZipReader {
    file: File,
    masked_end_records: Vec<u64>,
    mask: Arc<AtomicBool>,
}
impl Read for ZipReader {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        let start = self.file.stream_position()?;
        let n = self.file.read(buf)?;
        if self.mask.load(Ordering::Relaxed) {
            for &offset in &self.masked_end_records {
                if offset >= start && offset - start < n as u64 {
                    buf[(offset - start) as usize] = 0;
                }
            }
        }
        Ok(n)
    }
}
impl Seek for ZipReader {
    fn seek(&mut self, position: SeekFrom) -> std::io::Result<u64> {
        self.file.seek(position)
    }
}

fn preflight_zip(file: &mut File) -> Result<Vec<u64>> {
    let len = file.metadata()?.len();
    let tail_len = len.min(65_557) as usize;
    let mut tail = vec![0u8; tail_len];
    file.seek(SeekFrom::End(-(tail_len as i64)))?;
    file.read_exact(&mut tail)?;
    let u16at = |data: &[u8], i: usize| u16::from_le_bytes([data[i], data[i + 1]]);
    let u32at = |data: &[u8], i: usize| u32::from_le_bytes(data[i..i + 4].try_into().unwrap());
    let u64at = |data: &[u8], i: usize| u64::from_le_bytes(data[i..i + 8].try_into().unwrap());
    let pos = (0..tail_len.saturating_sub(21))
        .rev()
        .find(|&i| {
            tail[i..i + 4] == *b"PK\x05\x06" && i + 22 + u16at(&tail, i + 20) as usize == tail_len
        })
        .context("missing ZIP central directory")?;
    let alternate_ends: Vec<u64> = (0..tail_len.saturating_sub(21))
        .filter(|&i| {
            i != pos
                && tail[i..i + 4] == *b"PK\x05\x06"
                && i + 22 + u16at(&tail, i + 20) as usize <= tail_len
        })
        .map(|i| len - tail_len as u64 + i as u64)
        .collect();
    if u16at(&tail, pos + 4) != 0 || u16at(&tail, pos + 6) != 0 {
        bail!("multi-disk archives are not supported")
    }
    let mut count = u16at(&tail, pos + 10) as u64;
    let mut size = u32at(&tail, pos + 12) as u64;
    let mut offset = u32at(&tail, pos + 16) as u64;
    let eocd_offset = len - tail_len as u64 + pos as u64;
    let mut directory_end = eocd_offset;
    if count == u16::MAX as u64 || size == u32::MAX as u64 || offset == u32::MAX as u64 {
        if eocd_offset < 20 {
            bail!("missing ZIP64 locator")
        }
        let mut locator = [0u8; 20];
        file.seek(SeekFrom::Start(eocd_offset - 20))?;
        file.read_exact(&mut locator)?;
        if locator[..4] != *b"PK\x06\x07" || u32at(&locator, 4) != 0 || u32at(&locator, 16) != 1 {
            bail!("invalid ZIP64 locator")
        }
        let zip64_offset = u64at(&locator, 8);
        if zip64_offset.checked_add(56) != Some(eocd_offset - 20) {
            bail!("invalid ZIP64 directory")
        }
        let mut zip64 = [0u8; 56];
        file.seek(SeekFrom::Start(zip64_offset))?;
        file.read_exact(&mut zip64)?;
        if zip64[..4] != *b"PK\x06\x06"
            || u64at(&zip64, 4) != 44
            || u32at(&zip64, 16) != 0
            || u32at(&zip64, 20) != 0
            || u64at(&zip64, 24) != u64at(&zip64, 32)
        {
            bail!("invalid ZIP64 directory")
        }
        count = u64at(&zip64, 32);
        size = u64at(&zip64, 40);
        offset = u64at(&zip64, 48);
        directory_end = zip64_offset;
    } else if u16at(&tail, pos + 8) as u64 != count {
        bail!("invalid ZIP directory count")
    }
    if count == 0
        || count > MAX_ENTRIES as u64
        || size > 16 * 1024 * 1024
        || offset.checked_add(size) != Some(directory_end)
    {
        bail!("ZIP directory limit exceeded")
    }
    if alternate_ends.iter().any(|&end| end >= offset) {
        bail!("ambiguous ZIP end record")
    }
    file.seek(SeekFrom::Start(offset))?;
    let mut cursor = offset;
    for _ in 0..count {
        if cursor.checked_add(46).is_none_or(|end| end > directory_end) {
            bail!("truncated ZIP directory")
        }
        let mut header = [0u8; 46];
        file.read_exact(&mut header)?;
        if header[..4] != *b"PK\x01\x02" {
            bail!("invalid ZIP directory header")
        }
        let extra =
            u16at(&header, 28) as u64 + u16at(&header, 30) as u64 + u16at(&header, 32) as u64;
        cursor = cursor
            .checked_add(46 + extra)
            .context("ZIP directory overflow")?;
        if cursor > directory_end {
            bail!("truncated ZIP directory")
        }
        file.seek(SeekFrom::Start(cursor))?;
    }
    if cursor != directory_end {
        bail!("ZIP directory count mismatch")
    }
    file.seek(SeekFrom::Start(0))?;
    Ok(alternate_ends)
}

fn restore_folder(archive: &Path, output_dir: &Path, cancelled: &AtomicBool) -> Result<String> {
    check_cancel(cancelled)?;
    let mut input = open_nofollow(None, archive, false)?;
    let masked_end_records = preflight_zip(&mut input)?;
    let mask = Arc::new(AtomicBool::new(true));
    let reader = ZipReader {
        file: input,
        masked_end_records,
        mask: mask.clone(),
    };
    let mut zip = ZipArchive::with_config(
        zip::read::Config {
            archive_offset: zip::read::ArchiveOffset::Known(0),
        },
        reader,
    )?;
    mask.store(false, Ordering::Relaxed);
    if zip.has_duplicate_names() {
        bail!("duplicate archive path")
    }
    if zip.is_empty() || zip.len() > MAX_ENTRIES {
        bail!("invalid folder archive item count")
    }
    let mut total = 0u64;
    let mut names = HashSet::new();
    let mut kinds: HashMap<String, (String, bool)> = HashMap::new();
    let mut root: Option<String> = None;
    for i in 0..zip.len() {
        check_cancel(cancelled)?;
        let entry = zip.by_index(i)?;
        let raw = std::str::from_utf8(entry.name_raw()).context("invalid archive filename")?;
        let is_dir = entry.is_dir();
        let raw = if is_dir {
            raw.strip_suffix('/').context("invalid directory")?
        } else {
            raw
        };
        if raw.len() > MAX_PATH {
            bail!("archive path too long")
        }
        let parts: Vec<_> = raw.split('/').collect();
        if parts.len() > MAX_DEPTH || parts.iter().any(|part| !valid_component(part)) {
            bail!("unsafe archive path")
        }
        if !is_dir && parts.len() < 2 {
            bail!("archive must contain one folder")
        }
        match &root {
            Some(name) if name != parts[0] => bail!("archive must contain one folder"),
            None => root = Some(parts[0].to_owned()),
            _ => {}
        }
        if entry.is_symlink() {
            bail!("archive links are not supported")
        }
        if let Some(mode) = entry.unix_mode() {
            let kind = mode & 0o170000;
            if kind != 0 && kind != if is_dir { 0o040000 } else { 0o100000 } {
                bail!("archive contains special files")
            }
        }
        total = total
            .checked_add(entry.size())
            .context("archive size overflow")?;
        if total > MAX_BYTES {
            bail!("archive size limit exceeded")
        }
        let mut prefix = String::new();
        let mut original_prefix = String::new();
        for (index, part) in parts.iter().enumerate() {
            if !prefix.is_empty() {
                prefix.push('/');
            }
            if !original_prefix.is_empty() {
                original_prefix.push('/');
            }
            prefix.extend(part.nfkc().flat_map(char::to_lowercase));
            original_prefix.push_str(part);
            let is_folder = index + 1 < parts.len() || is_dir;
            if let Some((existing_name, existing_kind)) =
                kinds.insert(prefix.clone(), (original_prefix.clone(), is_folder))
            {
                if existing_name != original_prefix || existing_kind != is_folder {
                    bail!("conflicting archive paths")
                }
            }
        }
        if !names.insert(prefix) {
            bail!("duplicate archive path")
        }
    }
    let root = root.context("archive has no root")?;
    let destination_file = open_nofollow(None, output_dir, true)?;
    let available = available_space(space_handle(&destination_file))?;
    if available < total.saturating_add(256 * 1024 * 1024) {
        bail!("not enough free space to restore folder")
    }
    let temp = tempfile::Builder::new()
        .prefix(".vela-folder-")
        .tempdir_in(output_dir)?;
    let temp_dir = Dir::from_std_file(open_nofollow(None, temp.path(), true)?);
    let destination_dir = Dir::from_std_file(destination_file);
    for i in 0..zip.len() {
        check_cancel(cancelled)?;
        let mut entry = zip.by_index(i)?;
        let raw = std::str::from_utf8(entry.name_raw())?.to_owned();
        let parts: Vec<_> = raw.trim_end_matches('/').split('/').collect();
        let mut parent = temp_dir.try_clone()?;
        let dirs = if entry.is_dir() {
            parts.len()
        } else {
            parts.len() - 1
        };
        for part in &parts[..dirs] {
            parent = make_subdir(&parent, part)?;
        }
        if !entry.is_dir() {
            let mut out = create_file(&parent, parts[parts.len() - 1])?;
            let expected = entry.size();
            let space_fd = space_handle(&out);
            let actual = copy_limited(&mut entry, &mut out, cancelled, expected, Some(space_fd))?;
            if actual != expected {
                bail!("archive item size mismatch")
            }
        }
    }
    check_cancel(cancelled)?;
    let original_root = open_for_publication(&temp_dir, &root)?;
    let original_id = file_identity(&original_root)?;
    for i in 0..10_000 {
        let name = if i == 0 {
            root.clone()
        } else {
            format!("{root} ({i})")
        };
        let dest = output_dir.join(&name);
        match rename_exclusive(&temp_dir, &root, &destination_dir, &name, &original_root) {
            Ok(()) => {
                let published = open_for_publication(&destination_dir, &name)?;
                if file_identity(&published)? != original_id {
                    bail!("folder changed during publication")
                }
                return Ok(dest.to_string_lossy().into_owned());
            }
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(e).context("cannot publish folder"),
        }
    }
    bail!("cannot create folder: too many existing names")
}

#[cfg(test)]
#[path = "folder_tests.rs"]
mod tests;

#[cfg(test)]
#[path = "folder_additional_tests.rs"]
mod additional_tests;

#[cfg(test)]
#[path = "folder_preflight_tests.rs"]
mod preflight_tests;
