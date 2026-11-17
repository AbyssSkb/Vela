use super::*;
use std::fs;

#[test]
fn accepts_normal_comment_and_zip_signature_inside_file() -> Result<()> {
    let dir = tempfile::tempdir()?;
    let path = dir.path().join("valid.zip");
    let mut zip = ZipWriter::new(File::create(&path)?);
    zip.set_comment("ordinary comment")?;
    zip.start_file(
        "root/file",
        SimpleFileOptions::default().compression_method(zip::CompressionMethod::Stored),
    )?;
    zip.write_all(b"A PK\x05\x06 B")?;
    zip.finish()?;
    let restored = restore_folder(&path, dir.path(), &AtomicBool::new(false))?;
    assert_eq!(
        fs::read(Path::new(&restored).join("file"))?,
        b"A PK\x05\x06 B"
    );
    Ok(())
}

#[test]
fn rejects_forged_counts_sizes_and_ambiguous_end_records() -> Result<()> {
    let dir = tempfile::tempdir()?;
    let path = dir.path().join("valid.zip");
    let mut zip = ZipWriter::new(File::create(&path)?);
    zip.start_file("root/file", SimpleFileOptions::default())?;
    zip.write_all(b"data")?;
    zip.finish()?;
    let valid = fs::read(&path)?;
    let end = valid.len() - 22;
    assert_eq!(&valid[end..end + 4], b"PK\x05\x06");
    let mut cases = Vec::new();
    let mut bad_count = valid.clone();
    bad_count[end + 8..end + 10].copy_from_slice(&2u16.to_le_bytes());
    bad_count[end + 10..end + 12].copy_from_slice(&2u16.to_le_bytes());
    cases.push(bad_count);
    let mut bad_size = valid.clone();
    bad_size[end + 12..end + 16].copy_from_slice(&(17u32 * 1024 * 1024).to_le_bytes());
    cases.push(bad_size);
    let mut bad_comment = valid.clone();
    bad_comment[end + 20..end + 22].copy_from_slice(&22u16.to_le_bytes());
    bad_comment.extend_from_slice(b"PK\x05\x06");
    bad_comment.extend_from_slice(&[0u8; 18]);
    cases.push(bad_comment);
    for data in cases {
        fs::write(&path, data)?;
        assert!(restore_folder(&path, dir.path(), &AtomicBool::new(false)).is_err());
        assert!(!dir.path().join("root").exists());
    }
    Ok(())
}

#[test]
fn rejects_exact_duplicate_zip_names() -> Result<()> {
    let dir = tempfile::tempdir()?;
    let path = dir.path().join("duplicate.zip");
    let mut zip = ZipWriter::new(File::create(&path)?);
    zip.start_file("root/a", SimpleFileOptions::default())?;
    zip.start_file("root/b", SimpleFileOptions::default())?;
    zip.finish()?;
    let mut data = fs::read(&path)?;
    for i in 0..data.len().saturating_sub(5) {
        if &data[i..i + 6] == b"root/b" {
            data[i + 5] = b'a';
        }
    }
    fs::write(&path, data)?;
    assert!(restore_folder(&path, dir.path(), &AtomicBool::new(false)).is_err());
    assert!(path.exists());
    assert!(!dir.path().join("root").exists());
    Ok(())
}

#[test]
fn chunked_copy_observes_cancellation_before_next_chunk() {
    struct CancellingWriter<'a>(&'a AtomicBool);
    impl Write for CancellingWriter<'_> {
        fn write(&mut self, input: &[u8]) -> std::io::Result<usize> {
            self.0.store(true, Ordering::Relaxed);
            Ok(input.len())
        }
        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }
    let flag = AtomicBool::new(false);
    let mut input = std::io::repeat(1).take(128 * 1024);
    assert!(copy_limited(
        &mut input,
        &mut CancellingWriter(&flag),
        &flag,
        128 * 1024,
        None
    )
    .is_err());
}
