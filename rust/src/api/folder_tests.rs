use super::*;
use std::fs;
#[cfg(unix)]
use std::os::unix::fs::symlink;

fn cancelled() -> AtomicBool {
    AtomicBool::new(false)
}

#[test]
fn folder_roundtrip_preserves_contents_and_never_overwrites() -> Result<()> {
    let base = tempfile::tempdir()?;
    let source = base.path().join("source");
    let archives = base.path().join("archives");
    let output = base.path().join("out");
    fs::create_dir_all(source.join("nested/empty"))?;
    fs::create_dir(&archives)?;
    fs::create_dir_all(output.join("source"))?;
    fs::write(source.join("nested/test.txt"), "hello")?;
    fs::write(output.join("source/existing"), "untouched")?;
    let archive = pack_folder(&source, &archives, &cancelled())?;
    assert!(archive.ends_with("source.vela-folder.zip"));
    let restored = restore_folder(Path::new(&archive), &output, &cancelled())?;
    assert!(restored.ends_with("source (1)"));
    assert_eq!(
        fs::read(Path::new(&restored).join("nested/test.txt"))?,
        b"hello"
    );
    assert!(Path::new(&restored).join("nested/empty").is_dir());
    assert_eq!(fs::read(output.join("source/existing"))?, b"untouched");
    assert!(Path::new(&archive).exists());
    Ok(())
}

fn make_zip(path: &Path, entries: &[(&str, Option<u32>)]) -> Result<()> {
    let mut zip = ZipWriter::new(File::create(path)?);
    for (name, mode) in entries {
        let mut options = SimpleFileOptions::default();
        if let Some(mode) = mode {
            options = options.unix_permissions(*mode);
        }
        zip.start_file(*name, options)?;
        zip.write_all(b"test")?;
    }
    zip.finish()?;
    Ok(())
}

#[test]
fn rejects_unsafe_and_conflicting_paths_without_writing_outside() -> Result<()> {
    let base = tempfile::tempdir()?;
    for paths in [
        vec!["root/../escape"],
        vec!["/absolute"],
        vec!["root/evil\\name"],
        vec!["root/A/x", "root/a/y"],
        vec!["root/a", "root/A"],
        vec!["root/file", "root/file/child"],
    ] {
        let archive = base.path().join("test.zip");
        make_zip(
            &archive,
            &paths.iter().map(|p| (*p, None)).collect::<Vec<_>>(),
        )?;
        assert!(
            restore_folder(&archive, base.path(), &cancelled()).is_err(),
            "accepted {paths:?}"
        );
        assert!(archive.exists());
        assert!(!base.path().join("escape").exists());
        assert!(!base.path().join("root").exists());
    }
    Ok(())
}

#[test]
#[cfg(unix)]
fn refuses_source_symlinks_and_cleans_cancelled_archives() -> Result<()> {
    let base = tempfile::tempdir()?;
    let src = base.path().join("source");
    let out = base.path().join("out");
    fs::create_dir(&src)?;
    fs::create_dir(&out)?;
    fs::write(src.join("data"), b"abc")?;
    symlink("data", src.join("link"))?;
    assert!(pack_folder(&src, &out, &cancelled()).is_err());
    assert_eq!(fs::read_dir(&out)?.count(), 0);
    fs::remove_file(src.join("link"))?;
    let flag = AtomicBool::new(true);
    assert!(pack_folder(&src, &out, &flag).is_err());
    assert_eq!(fs::read_dir(&out)?.count(), 0);
    assert!(pack_folder(&src, &src, &cancelled()).is_err());
    Ok(())
}
