use super::validation::{valid_device_name, valid_device_type};
use super::{DeviceInfo, OutgoingPairing, VelaNode};
use crate::failure_code::FailureCode;
use crate::protocol::{alpn, RequestHeader, MAX_HEADER, PAIRING_COMPLETE};
use anyhow::{bail, Context, Result};
use flutter_rust_bridge::frb;
use iroh::{
    endpoint::{Connection, ConnectionError},
    Endpoint, EndpointAddr, EndpointId,
};
use std::{str::FromStr, sync::atomic::Ordering};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

impl VelaNode {
    /// Create a cancellable request after `begin_pairing` isolates the old session.
    /// After the handshake, persist/sync trust before calling `end_pairing`.
    pub async fn begin_outgoing_pairing(&self, peer_id: String) -> Result<OutgoingPairing> {
        let target = EndpointId::from_str(&peer_id).context("invalid device ID")?;
        let attempt = self.trust.write().await.begin_outgoing_pairing(peer_id)?;
        Ok(OutgoingPairing {
            endpoint: self.endpoint.clone(),
            target: iroh::EndpointAddr::new(target),
            attempt,
        })
    }
}

impl OutgoingPairing {
    #[frb(sync)]
    pub fn cancel(&self) {
        self.attempt.cancel();
    }

    pub async fn request(&self, name: String, device_type: String) -> Result<DeviceInfo> {
        if self.attempt.started.swap(true, Ordering::AcqRel) {
            if *self.attempt.cancel.borrow() {
                return Err(FailureCode::Cancelled.error("pairing cancelled"));
            }
            bail!("pairing already started")
        }
        let mut cancelled = self.attempt.cancel.subscribe();
        let result = if *cancelled.borrow_and_update() {
            Err(FailureCode::Cancelled.error("pairing cancelled"))
        } else {
            tokio::select! {
                biased;
                _ = cancelled.changed() => Err(FailureCode::Cancelled.error("pairing cancelled")),
                result = tokio::time::timeout(std::time::Duration::from_secs(90), exchange_pairing_request(&self.endpoint, self.target.clone(), name, device_type)) => result.context("pairing timed out").and_then(|value| value),
            }
        };
        self.attempt.finished.store(true, Ordering::Release);
        result
    }
}

impl Drop for OutgoingPairing {
    fn drop(&mut self) {
        self.cancel();
    }
}

pub(super) async fn exchange_pairing_request(
    endpoint: &Endpoint,
    target: EndpointAddr,
    name: String,
    device_type: String,
) -> Result<DeviceInfo> {
    if !valid_device_name(&name) || !valid_device_type(&device_type) {
        bail!("invalid pairing information")
    }
    let conn = PairConnection(endpoint.connect(target, alpn::PAIRING).await?);
    let (mut send, mut recv) = conn.0.open_bi().await?;
    let data = serde_json::to_vec(&RequestHeader {
        name,
        size: 0,
        kind: format!("pair_{device_type}"),
        files: vec![],
    })?;
    send.write_u32(data.len() as u32).await?;
    send.write_all(&data).await?;
    match recv.read_u8().await? {
        1 => {}
        2 => {
            confirm_pairing_response(&conn.0, &mut send, &mut recv).await?;
            bail!("pairing conflict")
        }
        _ => {
            confirm_pairing_response(&conn.0, &mut send, &mut recv).await?;
            return Err(FailureCode::PairingDeclined.error("pairing declined"));
        }
    }
    let len = recv.read_u32().await? as usize;
    if len > MAX_HEADER {
        bail!("invalid device information")
    }
    let mut data = vec![0; len];
    recv.read_exact(&mut data).await?;
    let info: DeviceInfo = serde_json::from_slice(&data)?;
    if !valid_device_name(&info.name) || !valid_device_type(&info.device_type) {
        bail!("invalid device information")
    }
    confirm_pairing_response(&conn.0, &mut send, &mut recv).await?;
    Ok(info)
}

async fn confirm_pairing_response(
    conn: &Connection,
    send: &mut iroh::endpoint::SendStream,
    recv: &mut iroh::endpoint::RecvStream,
) -> Result<()> {
    let mut extra = [0u8; 1];
    match tokio::time::timeout(std::time::Duration::from_secs(10), recv.read(&mut extra))
        .await
        .context("pairing response timed out")??
    {
        None => {}
        Some(_) => bail!("unexpected pairing response data"),
    }
    send.write_u8(1).await?;
    send.finish()?;
    let reason = tokio::time::timeout(std::time::Duration::from_secs(10), conn.closed())
        .await
        .context("pairing confirmation timed out")?;
    match reason {
        ConnectionError::ApplicationClosed(close)
            if close.error_code.into_inner() == u64::from(PAIRING_COMPLETE) =>
        {
            Ok(())
        }
        error => bail!("pairing was not confirmed: {error}"),
    }
}

struct PairConnection(Connection);
impl Drop for PairConnection {
    fn drop(&mut self) {
        self.0.close(0u32.into(), b"pairing finished");
    }
}
