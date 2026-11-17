use crate::failure_code::FailureCode;
use anyhow::Context;
use anyhow::{bail, Result};
use sha2::{Digest, Sha256};
use std::path::{Path, PathBuf};
use tokio::io::AsyncReadExt;

pub(super) async fn send_file_contents_and_checksum(
    send: &mut iroh::endpoint::SendStream,
    file: &mut tokio::fs::File,
    size: u64,
    buf: &mut [u8],
) -> Result<()> {
    let mut remaining = size;
    let mut hash = Sha256::new();
    while remaining > 0 {
        let cap = remaining.min(buf.len() as u64) as usize;
        let n = file.read(&mut buf[..cap]).await?;
        if n == 0 {
            bail!("file changed while sending")
        }
        send.write_all(&buf[..n]).await?;
        hash.update(&buf[..n]);
        remaining -= n as u64;
    }
    send.write_all(&hash.finalize()).await?;
    Ok(())
}

pub(super) async fn create_unique_destination(
    directory: &Path,
    name: &str,
) -> Result<(PathBuf, tokio::fs::File)> {
    let original = Path::new(name);
    let stem = original
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or(name);
    let extension = original.extension().and_then(|s| s.to_str());
    for index in 0..10_000 {
        let candidate = if index == 0 {
            name.to_owned()
        } else {
            match extension {
                Some(ext) => format!("{stem} ({index}).{ext}"),
                None => format!("{stem} ({index})"),
            }
        };
        let path = directory.join(candidate);
        match tokio::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&path)
            .await
        {
            Ok(file) => return Ok((path, file)),
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(error) => {
                return Err(error)
                    .with_context(|| FailureCode::SaveFailed.error("cannot create destination"));
            }
        }
    }
    Err(FailureCode::SaveFailed
        .error("cannot create destination: too many files with the same name"))
}
