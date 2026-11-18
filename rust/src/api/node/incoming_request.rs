use super::request_io::response_acknowledged;
use super::transfer::{
    receive_transfer_path, set_transfer_connection, wait_for_cancellation, with_path_monitor,
};
use super::transfer_io::{create_unique_destination, receive_file_contents_and_checksum};
use super::validation::{valid_device_name, valid_device_type};
use super::{
    DeviceInfo, IncomingRequest, IncomingRequestInfo, Request, TransferJob, TransferOffer,
};
use crate::content_kind::ContentKind;
use crate::failure_code::FailureCode;
use crate::protocol::PAIRING_COMPLETE;
use anyhow::Context;
use anyhow::{anyhow, bail, Result};
use flutter_rust_bridge::frb;
use iroh::endpoint::{RecvStream, SendStream};
use std::path::Path;
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

impl IncomingRequest {
    pub async fn wait_for_connection_close(&self) {
        self._connection.closed().await;
    }

    #[frb(sync)]
    pub fn info(&self) -> IncomingRequestInfo {
        match &self.request {
            Request::Pairing(info) => IncomingRequestInfo {
                name: String::new(),
                size: 0,
                sender: self.sender.clone(),
                kind: String::new(),
                files: Vec::new(),
                pairing: Some(info.clone()),
            },
            Request::Transfer(offer) => IncomingRequestInfo {
                name: offer.name.clone(),
                size: offer.size,
                sender: self.sender.clone(),
                kind: offer.kind.wire_name().into(),
                files: offer.files.iter().map(|file| file.name.clone()).collect(),
                pairing: None,
            },
        }
    }

    pub async fn decline(&self) -> Result<()> {
        let mut send = self
            .send
            .lock()
            .await
            .take()
            .ok_or_else(|| anyhow!("offer already handled"))?;
        send.write_u8(0).await?;
        if matches!(self.request, Request::Pairing(_)) {
            return self.finish_pairing_response(&mut send).await;
        }
        send.finish()?;
        let result = tokio::time::timeout(std::time::Duration::from_secs(2), send.stopped())
            .await
            .context("decline acknowledgement timed out")?;
        response_acknowledged(result)
    }

    pub async fn decline_pair_conflict(&self) -> Result<()> {
        if !matches!(self.request, Request::Pairing(_)) {
            bail!("not a pairing request")
        }
        let mut send = self
            .send
            .lock()
            .await
            .take()
            .ok_or_else(|| anyhow!("offer already handled"))?;
        send.write_u8(2).await?;
        self.finish_pairing_response(&mut send).await
    }

    pub async fn accept_pair(&self, name: String, device_type: String) -> Result<()> {
        if !matches!(self.request, Request::Pairing(_))
            || !valid_device_name(&name)
            || !valid_device_type(&device_type)
        {
            bail!("invalid pairing information")
        }
        let mut send = self
            .send
            .lock()
            .await
            .take()
            .ok_or_else(|| anyhow!("offer already handled"))?;
        let data = serde_json::to_vec(&DeviceInfo { name, device_type })?;
        send.write_u8(1).await?;
        send.write_u32(data.len() as u32).await?;
        send.write_all(&data).await?;
        self.finish_pairing_response(&mut send).await
    }

    async fn finish_pairing_response(&self, send: &mut iroh::endpoint::SendStream) -> Result<()> {
        send.finish()?;
        let mut recv = self
            .recv
            .lock()
            .await
            .take()
            .ok_or_else(|| anyhow!("pairing already handled"))?;
        let confirmation = tokio::time::timeout(std::time::Duration::from_secs(10), recv.read_u8())
            .await
            .context("pairing confirmation timed out")??;
        if confirmation != 1 {
            bail!("invalid pairing confirmation")
        }
        let mut extra = [0u8; 1];
        match tokio::time::timeout(std::time::Duration::from_secs(10), recv.read(&mut extra))
            .await
            .context("pairing confirmation timed out")??
        {
            None => {}
            Some(_) => bail!("unexpected pairing confirmation data"),
        }
        self._connection
            .close(PAIRING_COMPLETE.into(), b"pairing complete");
        Ok(())
    }

    async fn accept_transfer(&self, send: &mut iroh::endpoint::SendStream) -> Result<()> {
        let state = self.trust.read().await;
        let Some(session) = self.session.as_ref() else {
            bail!("sender is no longer paired")
        };
        if !state.is_current(&self.sender, session) {
            bail!("sender is no longer paired")
        }
        tokio::time::timeout(std::time::Duration::from_secs(2), send.write_u8(1))
            .await
            .context("acceptance timed out")??;
        Ok(())
    }

    fn transfer_offer(&self, job: &TransferJob) -> Result<&TransferOffer> {
        if !Arc::ptr_eq(&self.trust, &job.trust) {
            bail!("transfer job belongs to another node")
        }
        match &self.request {
            Request::Transfer(offer) => Ok(offer),
            Request::Pairing(_) => bail!("not a transfer request"),
        }
    }

    async fn take_transfer_streams(&self) -> Result<(SendStream, RecvStream)> {
        let send = self
            .send
            .lock()
            .await
            .take()
            .ok_or_else(|| anyhow!("offer already handled"))?;
        let recv = self
            .recv
            .lock()
            .await
            .take()
            .ok_or_else(|| anyhow!("offer already handled"))?;
        Ok((send, recv))
    }

    pub async fn receive_files(&self, directory: String, job: &TransferJob) -> Result<Vec<String>> {
        let _run = job.start()?;
        let metadata = self.transfer_offer(job)?;
        if metadata.kind != ContentKind::Batch {
            bail!("not a batch transfer")
        }
        let (mut send, mut recv) = self.take_transfer_streams().await?;
        set_transfer_connection(&job.transfer, &self._connection, false)?;
        let cancel = job.transfer.lock().unwrap().cancel.subscribe();
        *job.progress.lock().unwrap() = (0, metadata.size);
        let mut paths = Vec::new();
        let mut saved = false;
        let receive = async {
            self.accept_transfer(&mut send).await?;
            let mut last_report = (0, tokio::time::Instant::now());
            let mut buf = vec![0u8; 64 * 1024];
            for entry in &metadata.files {
                let (path, mut file) =
                    create_unique_destination(Path::new(&directory), &entry.name).await?;
                paths.push(path);
                receive_file_contents_and_checksum(
                    &mut recv,
                    &mut send,
                    &mut file,
                    entry.size,
                    &mut buf,
                    &job.progress,
                    &mut last_report,
                )
                .await?;
            }
            saved = true;
            acknowledge_saved_files(&mut send).await
        };
        let result = tokio::select! {
            biased;
            _ = wait_for_cancellation(cancel) => Err(FailureCode::Cancelled.error("transfer cancelled")),
            result = with_path_monitor(receive, receive_transfer_path(&self._connection, &job.transfer)) => result,
        };
        if !saved {
            for path in &paths {
                let _ = tokio::fs::remove_file(path).await;
            }
            result?;
        }
        Ok(paths
            .iter()
            .map(|path| path.to_string_lossy().into_owned())
            .collect())
    }

    pub async fn receive_file(&self, directory: String, job: &TransferJob) -> Result<String> {
        let _run = job.start()?;
        let metadata = self.transfer_offer(job)?;
        if metadata.kind == ContentKind::Batch {
            bail!("not a single-file transfer")
        }
        let (mut send, mut recv) = self.take_transfer_streams().await?;
        set_transfer_connection(&job.transfer, &self._connection, false)?;
        let cancel = job.transfer.lock().unwrap().cancel.subscribe();
        let (path, mut file) =
            create_unique_destination(Path::new(&directory), &metadata.name).await?;
        *job.progress.lock().unwrap() = (0, metadata.size);
        let mut saved = false;
        let receive = async {
            self.accept_transfer(&mut send).await?;
            let mut last_report = (0, tokio::time::Instant::now());
            let mut buf = vec![0u8; 64 * 1024];
            receive_file_contents_and_checksum(
                &mut recv,
                &mut send,
                &mut file,
                metadata.size,
                &mut buf,
                &job.progress,
                &mut last_report,
            )
            .await?;
            saved = true;
            acknowledge_saved_files(&mut send).await
        };
        let result = tokio::select! {
            biased;
            _ = wait_for_cancellation(cancel) => Err(FailureCode::Cancelled.error("transfer cancelled")),
            result = with_path_monitor(receive, receive_transfer_path(&self._connection, &job.transfer)) => result,
        };
        if result.is_err() && !saved {
            drop(file);
            let _ = tokio::fs::remove_file(&path).await;
        }
        if !saved {
            result?;
        }
        Ok(path.to_string_lossy().into_owned())
    }
}

async fn acknowledge_saved_files(send: &mut SendStream) -> Result<()> {
    send.write_u8(1).await?;
    send.finish()?;
    let _ = send.stopped().await?;
    Ok(())
}
