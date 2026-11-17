use super::*;
use std::fs;
use std::sync::atomic::AtomicBool;

#[test]
fn rejects_archive_symlink_and_retains_zip() -> Result<()> {
    let dir = tempfile::tempdir()?;
    let path = dir.path().join("malicious.zip");
    let mut zip = ZipWriter::new(File::create(&path)?);
    zip.add_symlink("root/link", "../../outside", SimpleFileOptions::default())?;
    zip.finish()?;
    assert!(restore_folder(&path, dir.path(), &AtomicBool::new(false)).is_err());
    assert!(path.exists());
    assert!(!dir.path().join("root").exists());
    Ok(())
}

#[test]
fn depth_limit_matches_between_pack_and_restore() -> Result<()> {
    let dir = tempfile::tempdir()?;
    let source = dir.path().join("root");
    let out = dir.path().join("out");
    let dest = dir.path().join("dest");
    fs::create_dir(&source)?;
    fs::create_dir(&out)?;
    fs::create_dir(&dest)?;
    let mut child = source.clone();
    for _ in 0..62 {
        child.push("d");
        fs::create_dir(&child)?;
    }
    fs::write(child.join("file"), b"ok")?;
    let archive = pack_folder(&source, &out, &AtomicBool::new(false))?;
    assert!(restore_folder(Path::new(&archive), &dest, &AtomicBool::new(false)).is_ok());
    fs::create_dir(child.join("d"))?;
    fs::write(child.join("d/file"), b"too deep")?;
    assert!(pack_folder(&source, &out, &AtomicBool::new(false)).is_err());
    Ok(())
}

#[cfg(windows)]
#[test]
fn windows_rejects_unsafe_archive_names_before_creating_files() -> Result<()> {
    let dir = tempfile::tempdir()?;
    let path = dir.path().join("unsafe.zip");
    for name in ["CON.txt", "NUL", "LPT¹", "file:stream", "file.", "file "] {
        let mut zip = ZipWriter::new(File::create(&path)?);
        zip.start_file(format!("root/{name}"), SimpleFileOptions::default())?;
        zip.write_all(b"untrusted")?;
        zip.finish()?;
        assert!(restore_folder(&path, dir.path(), &AtomicBool::new(false)).is_err());
        assert!(!dir.path().join("root").exists());
    }
    Ok(())
}

#[cfg(windows)]
#[test]
fn windows_rejects_junctions_and_keeps_open_directories_in_place() -> Result<()> {
    let dir = tempfile::tempdir()?;
    let source = dir.path().join("source");
    let outside = dir.path().join("outside");
    fs::create_dir(&source)?;
    fs::create_dir(&outside)?;
    fs::write(outside.join("private.txt"), b"outside")?;
    let junction = source.join("junction");
    let result = std::process::Command::new("cmd")
        .args(["/d", "/c", "mklink", "/J"])
        .arg(&junction)
        .arg(&outside)
        .output()?;
    assert!(
        result.status.success(),
        "cannot create test junction: {result:?}"
    );
    let held = Dir::from_std_file(open_nofollow(None, &source, true)?);
    assert!(open_nofollow(Some(&held), Path::new("junction"), true).is_err());
    assert!(fs::rename(&source, dir.path().join("moved")).is_err());
    assert_eq!(fs::read(outside.join("private.txt"))?, b"outside");
    Ok(())
}
