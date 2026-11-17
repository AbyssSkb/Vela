use super::request_io::check_response_end;
use super::{TransferJob, TransferProgress, TransferState, VelaNode};
use crate::failure_code::FailureCode;
use anyhow::{bail, Result};
use flutter_rust_bridge::frb;
use std::future::Future;
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Mutex as StdMutex,
};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::watch;

pub(super) fn selected_path(conn: &iroh::endpoint::Connection) -> &'static str {
    for path in conn.paths().iter() {
        if path.is_selected() {
            return if path.is_relay() {
                "relay"
            } else if path.is_ip() {
                "direct"
            } else {
                ""
            };
        }
    }
    ""
}

pub(super) async fn publish_transfer_path(conn: &iroh::endpoint::Connection) {
    let Ok(mut stream) = conn.open_uni().await else {
        return;
    };
    let mut previous = None;
    loop {
        let value = match selected_path(conn) {
            "direct" => 1,
            "relay" => 2,
            _ => 0,
        };
        if previous != Some(value) {
            if stream.write_u8(value).await.is_err() {
                return;
            }
            previous = Some(value);
        }
        tokio::time::sleep(std::time::Duration::from_millis(300)).await;
    }
}

pub(super) async fn receive_transfer_path(
    conn: &iroh::endpoint::Connection,
    transfer: &StdMutex<TransferState>,
) {
    let Ok(mut stream) = conn.accept_uni().await else {
        return;
    };
    while let Ok(value) = stream.read_u8().await {
        let path = match value {
            0 => "",
            1 => "direct",
            2 => "relay",
            _ => break,
        };
        transfer.lock().unwrap().remote_path = path.to_owned();
    }
    transfer.lock().unwrap().remote_path.clear();
}

pub(super) async fn with_path_monitor<F: Future, M: Future<Output = ()>>(
    work: F,
    monitor: M,
) -> F::Output {
    tokio::pin!(work);
    tokio::select! { result = &mut work => result, _ = monitor => work.await }
}

pub(super) async fn wait_for_cancellation(mut receiver: watch::Receiver<bool>) {
    if !*receiver.borrow() {
        let _ = receiver.changed().await;
    }
}

pub(super) async fn read_receipt_progress(
    recv: &mut iroh::endpoint::RecvStream,
    progress: &StdMutex<(u64, u64)>,
    total: u64,
) -> Result<()> {
    let mut previous = 0;
    loop {
        match recv.read_u8().await? {
            1 => return check_response_end(recv).await,
            2 => {
                let done = recv.read_u64().await?;
                if done < previous || done > total {
                    bail!("invalid receive progress")
                }
                previous = done;
                *progress.lock().unwrap() = (done.min(total.saturating_sub(1)), total);
            }
            _ => bail!("receiver could not save file"),
        }
    }
}

pub(super) async fn report_receipt_progress(
    send: &mut iroh::endpoint::SendStream,
    done: u64,
    last: &mut (u64, tokio::time::Instant),
) -> Result<()> {
    if done.saturating_sub(last.0) >= 512 * 1024
        || last.1.elapsed() >= std::time::Duration::from_millis(300)
    {
        send.write_u8(2).await?;
        send.write_u64(done).await?;
        *last = (done, tokio::time::Instant::now());
    }
    Ok(())
}

pub(super) fn set_transfer_connection(
    transfer: &StdMutex<TransferState>,
    conn: &iroh::endpoint::Connection,
    sending: bool,
) -> Result<()> {
    let mut state = transfer.lock().unwrap();
    if *state.cancel.borrow() {
        conn.close(0u32.into(), b"transfer cancelled");
        return Err(FailureCode::Cancelled.error("transfer cancelled"));
    }
    state.connection = Some(conn.clone());
    state.sending = sending;
    state.remote_path.clear();
    Ok(())
}

impl VelaNode {
    #[frb(sync)]
    pub fn new_transfer_job(&self) -> Result<TransferJob> {
        let permit = self
            .transfer_slots
            .clone()
            .try_acquire_owned()
            .map_err(|_| anyhow::anyhow!("transfer already active"))?;
        Ok(TransferJob {
            endpoint: self.endpoint.clone(),
            trust: self.trust.clone(),
            progress: StdMutex::new((0, 0)),
            transfer: StdMutex::new(TransferState {
                cancel: watch::channel(false).0,
                connection: None,
                sending: false,
                remote_path: String::new(),
            }),
            started: AtomicBool::new(false),
            permit: StdMutex::new(Some(permit)),
        })
    }
}

pub(super) struct TransferRun<'a>(&'a TransferJob);

impl Drop for TransferRun<'_> {
    fn drop(&mut self) {
        self.0.permit.lock().unwrap().take();
    }
}

impl TransferJob {
    pub(super) fn start(&self) -> Result<TransferRun<'_>> {
        if self.started.swap(true, Ordering::AcqRel) {
            bail!("transfer job already started")
        }
        let run = TransferRun(self);
        if *self.transfer.lock().unwrap().cancel.borrow() {
            return Err(FailureCode::Cancelled.error("transfer cancelled"));
        }
        Ok(run)
    }

    #[frb(sync)]
    pub fn progress(&self) -> TransferProgress {
        let (done, total) = *self.progress.lock().unwrap();
        let state = self.transfer.lock().unwrap();
        let Some(conn) = state.connection.clone() else {
            return TransferProgress {
                done,
                total,
                path: String::new(),
                udp_bytes_sent: 0,
            };
        };
        let path = if state.sending {
            selected_path(&conn)
        } else {
            &state.remote_path
        }
        .to_owned();
        TransferProgress {
            done,
            total,
            path,
            udp_bytes_sent: conn.stats().udp_tx.bytes,
        }
    }

    #[frb(sync)]
    pub fn cancel(&self) {
        let state = self.transfer.lock().unwrap();
        state.cancel.send_replace(true);
        if let Some(conn) = &state.connection {
            conn.close(0u32.into(), b"transfer cancelled");
        }
        if !self.started.load(Ordering::Acquire) {
            self.permit.lock().unwrap().take();
        }
    }
}
