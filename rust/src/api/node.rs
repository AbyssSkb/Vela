mod incoming_request;
mod network;
mod outgoing_transfer;
mod pairing;
mod peer_state;
mod relay;
mod request_io;
mod runtime;
mod transfer;
mod transfer_io;
mod validation;

use relay::relay_origin;
pub(crate) use validation::{valid_device_name, valid_device_type};

use anyhow::{anyhow, bail, Result};
use flutter_rust_bridge::frb;
use iroh::{endpoint::presets, Endpoint, RelayConfig, RelayMap, RelayMode, SecretKey, Watcher};
use serde::{Deserialize, Serialize};
use std::sync::{atomic::AtomicBool, Arc, Mutex as StdMutex};
use tokio::sync::{mpsc, watch, Mutex, OwnedSemaphorePermit, RwLock, Semaphore};

use crate::content_kind::ContentKind;
use crate::protocol::TransferFileHeader;
use crate::trust::{IncomingPairGuard, OutgoingAttempt, PeerSession, SharedTrust};

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_log_to_console(log::LevelFilter::Warn);
    flutter_rust_bridge::setup_backtrace();
}

#[frb(opaque)]
pub struct VelaNode {
    presence: Option<Arc<crate::presence::PresenceManager>>,
    endpoint: Endpoint,
    trust: SharedTrust,
    network_changes: watch::Sender<u64>,
    device_info: Arc<RwLock<Option<DeviceInfo>>>,
    transfer_slots: Arc<Semaphore>,
    incoming_requests: Mutex<mpsc::Receiver<IncomingRequest>>,
}

#[frb(opaque)]
pub struct OutgoingPairing {
    endpoint: Endpoint,
    target: iroh::EndpointAddr,
    attempt: Arc<OutgoingAttempt>,
}

#[frb(opaque)]
pub struct IncomingRequest {
    _connection: iroh::endpoint::Connection,
    send: Mutex<Option<iroh::endpoint::SendStream>>,
    recv: Mutex<Option<iroh::endpoint::RecvStream>>,
    sender: String,
    request: Request,
    trust: SharedTrust,
    session: Option<Arc<PeerSession>>,
    _pairing_guard: Option<Arc<IncomingPairGuard>>,
}

enum Request {
    Pairing(DeviceInfo),
    Transfer(TransferOffer),
}

struct TransferOffer {
    name: String,
    size: u64,
    kind: ContentKind,
    files: Vec<TransferFileHeader>,
}

#[frb(opaque)]
pub struct TransferJob {
    endpoint: Endpoint,
    trust: SharedTrust,
    progress: StdMutex<(u64, u64)>,
    transfer: StdMutex<TransferState>,
    started: AtomicBool,
    permit: StdMutex<Option<OwnedSemaphorePermit>>,
}

struct TransferState {
    cancel: watch::Sender<bool>,
    connection: Option<iroh::endpoint::Connection>,
    sending: bool,
    remote_path: String,
}

pub struct TransferProgress {
    pub done: u64,
    pub total: u64,
    pub path: String,
    pub udp_bytes_sent: u64,
}

pub struct PresenceSnapshot {
    pub revision: u64,
    pub peers: Vec<PeerPresenceSnapshot>,
}

pub struct PeerPresenceSnapshot {
    pub peer_id: String,
    pub unpaired: bool,
    pub info: Option<DeviceInfo>,
    pub proof_valid_until_ns: Option<u64>,
}

#[derive(Clone)]
pub struct DiagnosticEvent {
    pub timestamp_ms: u64,
    pub monotonic_ms: u64,
    pub kind: String,
    pub details: String,
    pub trace: u64,
    pub attempt: u64,
    pub elapsed_ms: u64,
    pub rtt_ms: u64,
    pub ping_failures: u64,
    pub relays_before: u32,
    pub relays_after: u32,
}

#[frb(sync)]
pub fn diagnostics_monotonic_ms() -> u64 {
    crate::diagnostics::monotonic_ms()
}

#[frb(sync)]
pub fn proof_clock_now_ns() -> u64 {
    crate::proof_clock::now_ns()
}

#[frb(sync)]
pub fn set_diagnostics_enabled(enabled: bool) {
    crate::diagnostics::set_enabled(enabled);
}

pub struct IncomingRequestInfo {
    pub name: String,
    pub size: u64,
    pub sender: String,
    pub kind: String,
    pub files: Vec<String>,
    pub pairing: Option<DeviceInfo>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct DeviceInfo {
    pub name: String,
    pub device_type: String,
}

pub async fn start_node(secret: Vec<u8>) -> Result<VelaNode> {
    runtime::start_node(secret, Vec::new()).await
}

pub async fn start_node_with_relays(
    secret: Vec<u8>,
    urls: Vec<String>,
    tokens: Vec<String>,
) -> Result<VelaNode> {
    if urls.is_empty() || urls.len() != tokens.len() {
        bail!("invalid custom relay settings")
    }
    let mut relays = Vec::new();
    for (url, token) in urls.into_iter().zip(tokens) {
        let relay = relay_origin(&url)?;
        let mut config = RelayConfig::from(relay.clone());
        if !token.is_empty() {
            config = config.with_auth_token(token);
        }
        relays.push((relay, config));
    }
    runtime::start_node(secret, relays).await
}

pub fn generate_secret() -> Vec<u8> {
    SecretKey::generate().to_bytes().to_vec()
}

pub async fn test_relay(url: String, token: Option<String>) -> Result<String> {
    let relay = relay_origin(&url)?;
    let mut config = RelayConfig::from(relay);
    if let Some(token) = token.filter(|s| !s.is_empty()) {
        config = config.with_auth_token(token);
    }
    let endpoint = Endpoint::builder(presets::Minimal)
        .relay_mode(RelayMode::Custom(RelayMap::from(config)))
        .clear_ip_transports()
        .bind()
        .await?;
    let outcome = tokio::time::timeout(std::time::Duration::from_secs(15), async {
        let mut watcher = endpoint.home_relay_status();
        loop {
            let statuses = watcher.get();
            if statuses.iter().any(|status| status.is_connected()) {
                break "connected";
            }
            if statuses
                .iter()
                .any(|status| status.auth_denied_reason().is_some())
            {
                break "auth";
            }
            if watcher.updated().await.is_err() {
                break "failed";
            }
        }
    })
    .await
    .unwrap_or("timeout");
    endpoint.close().await;
    Ok(outcome.to_string())
}

impl VelaNode {
    #[frb(sync)]
    pub fn id(&self) -> String {
        self.endpoint.id().to_string()
    }

    pub async fn wait_until_online(&self) {
        self.endpoint.online().await;
    }

    #[frb(sync)]
    pub fn diagnostics_events(&self) -> Vec<DiagnosticEvent> {
        crate::diagnostics::events()
    }

    #[frb(sync)]
    pub fn clear_diagnostics(&self) {
        crate::diagnostics::clear();
    }

    #[frb(sync)]
    pub fn diagnostics_connected_relay_count(&self) -> u32 {
        self.endpoint
            .home_relay_status()
            .get()
            .iter()
            .filter(|relay| relay.is_connected())
            .count() as u32
    }

    #[frb(sync)]
    pub fn diagnostics_total_relay_count(&self) -> u32 {
        self.endpoint.home_relay_status().get().iter().count() as u32
    }

    pub async fn network_change(&self, resumed: bool) {
        if resumed {
            crate::diagnostics::system_wake();
            if let Some(presence) = &self.presence {
                presence.invalidate_for_resume().await;
            }
        } else {
            crate::diagnostics::network_changed();
        }
        if let Some(presence) = &self.presence {
            presence.on_network_changed().await;
        }
        self.network_changes
            .send_modify(|revision| *revision = revision.wrapping_add(1));
    }

    pub async fn next_request(&self) -> Result<IncomingRequest> {
        self.incoming_requests
            .lock()
            .await
            .recv()
            .await
            .ok_or_else(|| anyhow!("endpoint closed"))
    }

    pub async fn close(&self) {
        if let Some(presence) = &self.presence {
            presence.shutdown().await;
        }
        self.endpoint.close().await;
    }
}

#[cfg(test)]
#[path = "node_tests.rs"]
mod tests;
