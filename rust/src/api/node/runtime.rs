use super::network::{run_network_change_worker, spawn_home_relay_diagnostics};
use super::{DeviceInfo, IncomingRequest, Request, VelaNode};
use crate::protocol::{alpn, RequestHeader, MAX_HEADER};
use crate::trust::{begin_incoming_pair, TrustState, TrustStatus};
use anyhow::{anyhow, Result};
use iroh::endpoint::presets;
use iroh::{Endpoint, RelayConfig, RelayMap, RelayMode, RelayUrl, SecretKey};
use std::sync::Arc;
use tokio::io::AsyncReadExt;
use tokio::sync::{mpsc, watch, Mutex, RwLock, Semaphore};

pub(super) async fn start_node(
    secret: Vec<u8>,
    relays: Vec<(RelayUrl, RelayConfig)>,
) -> Result<VelaNode> {
    let key: [u8; 32] = secret
        .try_into()
        .map_err(|_| anyhow!("invalid identity key"))?;
    for (_, config) in &relays {
        if let Some(token) = &config.auth_token {
            crate::diagnostics::register_secret(token);
        }
    }
    let relay_map = RelayMap::empty();
    for (url, config) in relays {
        relay_map.insert(url, Arc::new(config));
    }
    let builder = if relay_map.is_empty() {
        Endpoint::builder(presets::N0)
    } else {
        Endpoint::builder(presets::Minimal)
            .relay_mode(RelayMode::Custom(relay_map.clone()))
            .address_lookup(crate::relay_lookup::RelayLookup(relay_map))
    };
    let endpoint = builder
        .secret_key(SecretKey::from_bytes(&key))
        .alpns(vec![
            alpn::TRANSFER.to_vec(),
            alpn::PAIRING.to_vec(),
            alpn::PRESENCE.to_vec(),
        ])
        .bind()
        .await?;
    Ok(start_node_with_endpoint(endpoint))
}

pub(super) fn start_node_with_endpoint(endpoint: Endpoint) -> VelaNode {
    let _home_relay_observer = spawn_home_relay_diagnostics(&endpoint);
    let trust = Arc::new(RwLock::new(TrustState::default()));
    let device_info = Arc::new(RwLock::new(None::<DeviceInfo>));
    let (offer_tx, incoming_requests) = mpsc::channel(32);
    let listener = endpoint.clone();
    let listener_trust = trust.clone();
    let listener_info = device_info.clone();
    let incoming_presence = Arc::new(Mutex::new(std::collections::HashMap::<
        String,
        Vec<iroh::endpoint::Connection>,
    >::new()));
    let listener_presence = incoming_presence.clone();
    let presence = Arc::new(crate::presence::PresenceManager::new(
        endpoint.clone(),
        trust.clone(),
        incoming_presence,
        device_info.clone(),
    ));
    let (network_changes, network_change_rx) = watch::channel(0u64);
    let network_endpoint = endpoint.clone();
    let closed_endpoint = endpoint.clone();
    let network_presence = presence.clone();
    tokio::spawn(run_network_change_worker(
        network_change_rx,
        async move { closed_endpoint.closed().await },
        move || {
            let endpoint = network_endpoint.clone();
            let presence = network_presence.clone();
            async move {
                endpoint.network_change().await;
                presence.request_probe().await;
            }
        },
    ));
    let listener_manager = presence.clone();
    tokio::spawn(async move {
        let limit = Arc::new(Semaphore::new(64));
        let presence_limit = Arc::new(Semaphore::new(64));
        while let Some(incoming) = listener.accept().await {
            let Ok(permit) = limit.clone().try_acquire_owned() else {
                continue;
            };
            let trust = listener_trust.clone();
            let presence_limit = presence_limit.clone();
            let incoming_presence = listener_presence.clone();
            let presence_manager = listener_manager.clone();
            let device_info = listener_info.clone();
            let offer_tx = offer_tx.clone();
            tokio::spawn(async move {
                let permit = permit;
                let Ok(connecting) = incoming.accept() else {
                    return;
                };
                let Ok(Ok(conn)) =
                    tokio::time::timeout(std::time::Duration::from_secs(15), connecting).await
                else {
                    return;
                };
                let sender = conn.remote_id().to_string();
                let pairing = conn.alpn() == alpn::PAIRING;
                if conn.alpn() == alpn::PRESENCE {
                    let Ok(_presence_permit) = presence_limit.try_acquire_owned() else {
                        conn.close(0u32.into(), b"presence limit");
                        return;
                    };
                    drop(permit);
                    let registered = {
                        let state = trust.read().await;
                        if state.status(&sender) == TrustStatus::Paired {
                            let Some(session) = state.sessions.get(&sender).cloned() else {
                                return;
                            };
                            if !session.register(&conn) {
                                return;
                            }
                            incoming_presence
                                .lock()
                                .await
                                .entry(sender.clone())
                                .or_default()
                                .push(conn.clone());
                            Some(session)
                        } else {
                            None
                        }
                    };
                    presence_manager
                        .respond(&conn, &sender, &device_info, registered)
                        .await;
                    let mut sessions = incoming_presence.lock().await;
                    if let Some(connections) = sessions.get_mut(&sender) {
                        connections.retain(|c| c.stable_id() != conn.stable_id());
                        if connections.is_empty() {
                            sessions.remove(&sender);
                        }
                    }
                    return;
                }
                let session = if pairing {
                    None
                } else {
                    let state = trust.read().await;
                    if state.status(&sender) != TrustStatus::Paired {
                        conn.close(0u32.into(), b"untrusted");
                        return;
                    }
                    let Some(session) = state.sessions.get(&sender).cloned() else {
                        return;
                    };
                    if !session.register(&conn) {
                        return;
                    }
                    Some(session)
                };
                let _permit = permit;
                let (send, mut recv) = match tokio::time::timeout(
                    std::time::Duration::from_secs(15),
                    conn.accept_bi(),
                )
                .await
                {
                    Ok(Ok(s)) => s,
                    _ => return,
                };
                let len =
                    match tokio::time::timeout(std::time::Duration::from_secs(15), recv.read_u32())
                        .await
                    {
                        Ok(Ok(len)) if len as usize <= MAX_HEADER => len,
                        _ => return,
                    };
                let mut buf = vec![0; len as usize];
                if !matches!(
                    tokio::time::timeout(
                        std::time::Duration::from_secs(15),
                        recv.read_exact(&mut buf)
                    )
                    .await,
                    Ok(Ok(_))
                ) {
                    return;
                }
                let offer: RequestHeader = match serde_json::from_slice(&buf) {
                    Ok(offer) => offer,
                    Err(_) => return,
                };
                let request = match Request::from_header(offer, pairing) {
                    Ok(request) => request,
                    Err(_) => return,
                };
                let pairing_guard = if pairing {
                    let guard = begin_incoming_pair(
                        trust.clone(),
                        sender.clone(),
                        conn.clone(),
                        Arc::downgrade(&presence_manager),
                    )
                    .await;
                    presence_manager.reconcile_trusted_peers().await;
                    Some(guard)
                } else {
                    None
                };
                let failed_connection = conn.clone();
                let failed_guard = pairing_guard.clone();
                if offer_tx
                    .try_send(IncomingRequest {
                        _connection: conn,
                        send: Mutex::new(Some(send)),
                        recv: Mutex::new(Some(recv)),
                        sender,
                        request,
                        trust,
                        session,
                        _pairing_guard: pairing_guard,
                    })
                    .is_err()
                {
                    failed_connection.close(0u32.into(), b"incoming queue full");
                    if let Some(guard) = failed_guard {
                        guard.release().await;
                    }
                }
            });
        }
    });
    VelaNode {
        presence,
        endpoint,
        trust,
        network_changes,
        device_info,
        transfer_slots: Arc::new(Semaphore::new(1)),
        incoming_requests: Mutex::new(incoming_requests),
    }
}
