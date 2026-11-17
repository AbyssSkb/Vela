use super::request_io::check_response_end;
use super::transfer::{
    publish_transfer_path, read_receipt_progress, set_transfer_connection, wait_for_cancellation,
    with_path_monitor,
};
use super::transfer_io::send_file_contents_and_checksum;
use super::validation::valid_file_name;
use super::TransferJob;
use crate::content_kind::ContentKind;
use crate::failure_code::FailureCode;
use crate::protocol::{alpn, RequestHeader, TransferFileHeader, MAX_HEADER};
use crate::trust::TrustStatus;
use anyhow::Context;
use anyhow::{anyhow, bail, Result};
use iroh::EndpointId;
use std::path::Path;
use std::str::FromStr;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

impl TransferJob {
    async fn connect_transfer(
        &self,
        target: iroh::EndpointAddr,
    ) -> Result<iroh::endpoint::Connection> {
        let peer_id = target.id.to_string();
        let session = {
            let state = self.trust.read().await;
            if state.status(&peer_id) != TrustStatus::Paired {
                bail!("untrusted device")
            }
            state
                .sessions
                .get(&peer_id)
                .cloned()
                .ok_or_else(|| anyhow!("untrusted device"))?
        };
        let connection = self.endpoint.connect(target, alpn::TRANSFER).await?;
        {
            let state = self.trust.read().await;
            if !state.is_current(&peer_id, &session) || !session.register(&connection) {
                connection.close(0u32.into(), b"pairing changed");
                bail!("pairing changed")
            }
        }
        Ok(connection)
    }

    pub async fn send_file(&self, peer_id: String, path: String, kind: String) -> Result<()> {
        let _run = self.start()?;
        let target = EndpointId::from_str(&peer_id).context("invalid device ID")?;
        self.send_file_cancellable_to(iroh::EndpointAddr::new(target), path, kind)
            .await
    }

    pub(super) async fn send_file_cancellable_to(
        &self,
        target: iroh::EndpointAddr,
        path: String,
        kind: String,
    ) -> Result<()> {
        let cancel = self.transfer.lock().unwrap().cancel.subscribe();
        tokio::select! {
            biased;
            _ = wait_for_cancellation(cancel) => Err(FailureCode::Cancelled.error("transfer cancelled")),
            result = self.send_file_to(target, path, kind) => result,
        }
    }

    pub(super) async fn send_file_to(
        &self,
        target: iroh::EndpointAddr,
        path: String,
        kind: String,
    ) -> Result<()> {
        let kind = ContentKind::parse(&kind)
            .filter(|kind| *kind != ContentKind::Batch)
            .ok_or_else(|| anyhow!("invalid content type"))?;
        let path = Path::new(&path);
        let name = path
            .file_name()
            .and_then(|n| n.to_str())
            .ok_or_else(|| anyhow!("invalid filename"))?
            .to_owned();
        if !valid_file_name(&name) {
            bail!("invalid filename")
        }
        let mut file = tokio::fs::File::open(path).await?;
        let size = file.metadata().await?.len();
        if kind == ContentKind::TypedText && size > 1024 * 1024 {
            bail!("text is too large")
        }
        *self.progress.lock().unwrap() = (0, size);
        let conn = self.connect_transfer(target).await?;
        set_transfer_connection(&self.transfer, &conn, true)?;
        let (mut send, mut recv) = conn.open_bi().await?;
        let header = serde_json::to_vec(&RequestHeader {
            name,
            size,
            kind: kind.wire_name().into(),
            files: vec![],
        })?;
        if header.len() > MAX_HEADER {
            bail!("filename too long")
        }
        send.write_u32(header.len() as u32).await?;
        send.write_all(&header).await?;
        if recv.read_u8().await? != 1 {
            check_response_end(&mut recv).await?;
            return Err(FailureCode::Declined.error("transfer declined"));
        }
        let write = async {
            let mut buf = vec![0u8; 64 * 1024];
            send_file_contents_and_checksum(&mut send, &mut file, size, &mut buf).await?;
            send.finish()?;
            Ok::<(), anyhow::Error>(())
        };
        with_path_monitor(
            async {
                tokio::try_join!(
                    write,
                    read_receipt_progress(&mut recv, &self.progress, size)
                )
            },
            publish_transfer_path(&conn),
        )
        .await?;
        *self.progress.lock().unwrap() = (size, size);
        Ok(())
    }

    pub async fn send_files(&self, peer_id: String, paths: Vec<String>) -> Result<()> {
        let _run = self.start()?;
        let target = EndpointId::from_str(&peer_id).context("invalid device ID")?;
        self.send_files_cancellable_to(iroh::EndpointAddr::new(target), paths)
            .await
    }

    pub(super) async fn send_files_cancellable_to(
        &self,
        target: iroh::EndpointAddr,
        paths: Vec<String>,
    ) -> Result<()> {
        let cancel = self.transfer.lock().unwrap().cancel.subscribe();
        tokio::select! {
            biased;
            _ = wait_for_cancellation(cancel) => Err(FailureCode::Cancelled.error("transfer cancelled")),
            result = self.send_files_to(target, paths) => result,
        }
    }

    pub(super) async fn send_files_to(
        &self,
        target: iroh::EndpointAddr,
        paths: Vec<String>,
    ) -> Result<()> {
        if paths.len() < 2 || paths.len() > 100 {
            bail!("invalid file count")
        }
        let mut files = Vec::new();
        let mut total = 0u64;
        for path in &paths {
            let path = Path::new(path);
            let name = path
                .file_name()
                .and_then(|name| name.to_str())
                .ok_or_else(|| anyhow!("invalid filename"))?
                .to_owned();
            if !valid_file_name(&name) {
                bail!("invalid filename")
            }
            let size = tokio::fs::metadata(path).await?.len();
            total = total
                .checked_add(size)
                .ok_or_else(|| anyhow!("file size overflow"))?;
            files.push(TransferFileHeader { name, size });
        }
        *self.progress.lock().unwrap() = (0, total);
        let conn = self.connect_transfer(target).await?;
        set_transfer_connection(&self.transfer, &conn, true)?;
        let (mut send, mut recv) = conn.open_bi().await?;
        let header = serde_json::to_vec(&RequestHeader {
            name: String::new(),
            size: total,
            kind: ContentKind::Batch.wire_name().into(),
            files: files.clone(),
        })?;
        if header.len() > MAX_HEADER {
            bail!("filenames too long")
        }
        send.write_u32(header.len() as u32).await?;
        send.write_all(&header).await?;
        if recv.read_u8().await? != 1 {
            check_response_end(&mut recv).await?;
            return Err(FailureCode::Declined.error("transfer declined"));
        }
        let write = async {
            let mut buf = vec![0u8; 64 * 1024];
            for (path, metadata) in paths.iter().zip(files) {
                let mut file = tokio::fs::File::open(path).await?;
                send_file_contents_and_checksum(&mut send, &mut file, metadata.size, &mut buf)
                    .await?;
            }
            send.finish()?;
            Ok::<(), anyhow::Error>(())
        };
        with_path_monitor(
            async {
                tokio::try_join!(
                    write,
                    read_receipt_progress(&mut recv, &self.progress, total)
                )
            },
            publish_transfer_path(&conn),
        )
        .await?;
        *self.progress.lock().unwrap() = (total, total);
        Ok(())
    }
}
