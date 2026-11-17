use super::network::{run_network_change_worker, spawn_home_relay_diagnostics};
use super::request_io::{check_response_end, response_acknowledged};
use super::transfer::{
    publish_transfer_path, read_receipt_progress, receive_transfer_path, report_receipt_progress,
    set_transfer_connection, with_path_monitor,
};
use super::transfer_io::create_unique_destination;
use super::validation::valid_file_name;
use super::*;
use iroh::{EndpointId, RelayUrl};

use crate::protocol::{alpn, RequestHeader};
use std::str::FromStr;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

async fn start_local_test_node(secret: Vec<u8>) -> Result<VelaNode> {
    let key: [u8; 32] = secret
        .try_into()
        .map_err(|_| anyhow!("invalid identity key"))?;
    let endpoint = Endpoint::builder(presets::Minimal)
        .relay_mode(RelayMode::Disabled)
        .secret_key(SecretKey::from_bytes(&key))
        .alpns(vec![
            alpn::TRANSFER.to_vec(),
            alpn::PAIRING.to_vec(),
            alpn::PRESENCE.to_vec(),
        ])
        .bind()
        .await?;
    Ok(runtime::start_node_with_endpoint(endpoint))
}

impl VelaNode {
    async fn send_file_to(
        &self,
        target: iroh::EndpointAddr,
        path: String,
        kind: String,
    ) -> Result<()> {
        let job = self.new_transfer_job()?;
        let _run = job.start()?;
        job.send_file_cancellable_to(target, path, kind).await
    }

    async fn send_files_to(&self, target: iroh::EndpointAddr, paths: Vec<String>) -> Result<()> {
        let job = self.new_transfer_job()?;
        let _run = job.start()?;
        job.send_files_cancellable_to(target, paths).await
    }

    async fn request_pair_to(
        &self,
        target: iroh::EndpointAddr,
        name: String,
        device_type: String,
    ) -> Result<DeviceInfo> {
        pairing::exchange_pairing_request(&self.endpoint, target, name, device_type).await
    }
}

async fn relay_candidates(node: &VelaNode, id: EndpointId) -> Vec<RelayUrl> {
    use n0_future::StreamExt;
    let mut results = std::pin::pin!(node.endpoint.address_lookup().unwrap().resolve(id));
    let item = results.next().await.unwrap().unwrap().unwrap();
    let address: iroh::EndpointAddr = item.endpoint_info().clone().into();
    address.relay_urls().cloned().collect()
}
#[tokio::test]
async fn network_change_worker_coalesces_while_send_is_blocked() {
    use super::*;
    let (changes, rx) = watch::channel(0u64);
    let (close, closed) = tokio::sync::oneshot::channel::<()>();
    let (release, blocked) = tokio::sync::oneshot::channel::<()>();
    let (started, mut calls) = mpsc::unbounded_channel();
    let mut blocked = Some(blocked);
    let worker = tokio::spawn(run_network_change_worker(
        rx,
        async {
            let _ = closed.await;
        },
        move || {
            let blocked = blocked.take();
            let started = started.clone();
            async move {
                started.send(()).unwrap();
                if let Some(blocked) = blocked {
                    let _ = blocked.await;
                }
            }
        },
    ));
    changes.send_replace(1);
    calls.recv().await.unwrap();
    for revision in 2..=6 {
        changes.send_replace(revision);
    }
    assert!(
        tokio::time::timeout(std::time::Duration::from_millis(50), calls.recv())
            .await
            .is_err()
    );
    release.send(()).unwrap();
    tokio::time::timeout(std::time::Duration::from_secs(1), calls.recv())
        .await
        .unwrap()
        .unwrap();
    assert!(
        tokio::time::timeout(std::time::Duration::from_millis(50), calls.recv())
            .await
            .is_err()
    );
    close.send(()).unwrap();
    tokio::time::timeout(std::time::Duration::from_secs(1), worker)
        .await
        .unwrap()
        .unwrap();
}

#[tokio::test]
async fn network_change_worker_retries_and_delivers_after_queue_unblocks() {
    use super::*;
    let (changes, rx) = watch::channel(0u64);
    let (close, closed) = tokio::sync::oneshot::channel::<()>();
    let (queue, mut receiver) = mpsc::channel(1);
    queue.send(0).await.unwrap();
    let (started, mut attempts) = mpsc::unbounded_channel();
    let worker = tokio::spawn(run_network_change_worker(
        rx,
        async {
            let _ = closed.await;
        },
        move || {
            let queue = queue.clone();
            let started = started.clone();
            async move {
                started.send(()).unwrap();
                queue.send(1).await.unwrap();
            }
        },
    ));
    changes.send_replace(1);
    attempts.recv().await.unwrap();
    changes.send_replace(2);
    tokio::time::timeout(std::time::Duration::from_secs(2), attempts.recv())
        .await
        .expect("blocked send must be retried")
        .unwrap();
    assert_eq!(receiver.recv().await, Some(0));
    assert_eq!(
        tokio::time::timeout(std::time::Duration::from_secs(2), receiver.recv())
            .await
            .unwrap(),
        Some(1)
    );
    close.send(()).unwrap();
    worker.await.unwrap();
}

#[tokio::test]
async fn closing_network_change_worker_interrupts_blocked_send() {
    use super::*;
    let (changes, rx) = watch::channel(0u64);
    let (close, closed) = tokio::sync::oneshot::channel::<()>();
    let (started, mut calls) = mpsc::unbounded_channel();
    let worker = tokio::spawn(run_network_change_worker(
        rx,
        async {
            let _ = closed.await;
        },
        move || {
            let started = started.clone();
            async move {
                started.send(()).unwrap();
                std::future::pending::<()>().await;
            }
        },
    ));
    changes.send_replace(1);
    calls.recv().await.unwrap();
    close.send(()).unwrap();
    tokio::time::timeout(std::time::Duration::from_secs(1), worker)
        .await
        .unwrap()
        .unwrap();
}

#[tokio::test]
async fn node_network_change_returns_while_transport_notification_is_blocked() {
    use super::*;
    let endpoint = Endpoint::builder(presets::Minimal)
        .relay_mode(RelayMode::Disabled)
        .bind()
        .await
        .unwrap();
    let (network_changes, rx) = watch::channel(0u64);
    let (close, closed) = tokio::sync::oneshot::channel::<()>();
    let (started, mut calls) = mpsc::unbounded_channel();
    let worker = tokio::spawn(run_network_change_worker(
        rx,
        async {
            let _ = closed.await;
        },
        move || {
            let started = started.clone();
            async move {
                started.send(()).unwrap();
                std::future::pending::<()>().await;
            }
        },
    ));
    let (_offer_tx, offers) = mpsc::channel(1);
    let node = VelaNode {
        presence: None,
        endpoint,
        trust: Arc::new(RwLock::new(crate::trust::TrustState::default())),
        network_changes,
        device_info: Arc::new(RwLock::new(None)),
        transfer_slots: Arc::new(tokio::sync::Semaphore::new(1)),
        incoming_requests: Mutex::new(offers),
    };
    node.network_change(false).await;
    calls.recv().await.unwrap();
    tokio::time::timeout(std::time::Duration::from_secs(1), node.network_change(true))
        .await
        .expect("resume must not wait for the transport queue");
    close.send(()).unwrap();
    worker.await.unwrap();
    node.close().await;
}

#[tokio::test]
async fn closing_node_wakes_pending_presence_snapshot() {
    use super::*;
    let endpoint = Endpoint::builder(presets::Minimal)
        .relay_mode(RelayMode::Disabled)
        .bind()
        .await
        .unwrap();
    let trust = Arc::new(RwLock::new(crate::trust::TrustState::default()));
    let presence = Arc::new(crate::presence::PresenceManager::new(
        endpoint.clone(),
        trust.clone(),
        Arc::new(Mutex::new(std::collections::HashMap::new())),
        Arc::new(RwLock::new(None)),
    ));
    let (_offer_tx, offers) = mpsc::channel(1);
    let node = Arc::new(VelaNode {
        presence: Some(presence),
        endpoint,
        trust,
        network_changes: watch::channel(0).0,
        device_info: Arc::new(RwLock::new(None)),
        transfer_slots: Arc::new(tokio::sync::Semaphore::new(1)),
        incoming_requests: Mutex::new(offers),
    });
    node.set_presence_monitoring(true).await.unwrap();
    let revision = node.wait_presence_snapshot(0).await.unwrap().revision;
    let waiting = {
        let node = node.clone();
        tokio::spawn(async move { node.wait_presence_snapshot(revision).await })
    };
    tokio::task::yield_now().await;
    assert!(
        !waiting.is_finished(),
        "snapshot wait must remain pending before close"
    );
    node.close().await;
    let result = tokio::time::timeout(std::time::Duration::from_secs(2), waiting)
        .await
        .expect("closed node must wake snapshot wait")
        .unwrap();
    assert!(
        result.is_err(),
        "closed node must not return a live snapshot"
    );
}

#[tokio::test]
async fn home_relay_watcher_records_initial_snapshot_and_stops_with_endpoint() {
    use super::*;
    let endpoint = Endpoint::builder(presets::Minimal)
        .relay_mode(RelayMode::Disabled)
        .bind()
        .await
        .unwrap();
    let local_id = endpoint.id().to_string();
    let observer = spawn_home_relay_diagnostics(&endpoint);
    tokio::time::timeout(std::time::Duration::from_secs(3), async {
        loop {
            if crate::diagnostics::events().iter().any(|event| {
                event.kind == "home_relay_snapshot"
                    && serde_json::from_str::<serde_json::Value>(&event.details)
                        .ok()
                        .is_some_and(|data| {
                            data["local_endpoint_id"] == local_id
                                && data["home_relays"]
                                    .as_array()
                                    .is_some_and(|items| items.is_empty())
                        })
            }) {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(10)).await;
        }
    })
    .await
    .expect("initial empty snapshot should be recorded");
    endpoint.close().await;
    assert!(
        tokio::time::timeout(std::time::Duration::from_secs(3), observer)
            .await
            .unwrap()
            .unwrap()
            .is_none(),
        "endpoint close should stop the observer"
    );
}
#[tokio::test]
async fn default_node_keeps_official_discovery() {
    use super::*;
    let node = start_node(generate_secret()).await.unwrap();
    assert!(!node.endpoint.address_lookup().unwrap().is_empty());
    node.close().await;
}

#[tokio::test]
async fn unavailable_custom_relay_does_not_fall_back_to_official() {
    use super::*;
    let node = start_node_with_relays(
        generate_secret(),
        vec!["https://127.0.0.1:9/".into()],
        vec![String::new()],
    )
    .await
    .unwrap();
    assert!(!node.endpoint.address_lookup().unwrap().is_empty());
    assert!(
        tokio::time::timeout(std::time::Duration::from_secs(3), node.wait_until_online())
            .await
            .is_err()
    );
    let id = SecretKey::generate().public();
    let candidates = relay_candidates(&node, id).await;
    assert_eq!(candidates.len(), 1);
    assert_eq!(candidates[0].as_str(), "https://127.0.0.1:9/");
    node.add_relay("https://127.0.0.1:10/".into(), None)
        .await
        .unwrap();
    assert_eq!(relay_candidates(&node, id).await.len(), 2);
    node.remove_relay("https://127.0.0.1:9/".into())
        .await
        .unwrap();
    let updated = relay_candidates(&node, id).await;
    assert_eq!(updated.len(), 1);
    assert_eq!(updated[0].as_str(), "https://127.0.0.1:10/");
    node.close().await;
}
#[tokio::test]
#[ignore = "requires VELA_RELAY_TEST_URL and VELA_RELAY_TEST_TOKEN_FILE"]
async fn custom_relay_without_official_discovery() {
    use super::*;
    let url = std::env::var("VELA_RELAY_TEST_URL").unwrap();
    let token = std::fs::read_to_string(std::env::var("VELA_RELAY_TEST_TOKEN_FILE").unwrap())
        .unwrap()
        .trim()
        .to_owned();
    let urls = vec!["https://127.0.0.1:9/".into(), url];
    let tokens = vec![String::new(), token];
    let a = start_node_with_relays(generate_secret(), urls.clone(), tokens.clone())
        .await
        .unwrap();
    let b = start_node_with_relays(
        generate_secret(),
        vec![urls[1].clone()],
        vec![tokens[1].clone()],
    )
    .await
    .unwrap();
    let candidates = relay_candidates(&a, b.endpoint.id()).await;
    assert_eq!(candidates.len(), 2);
    assert!(candidates
        .iter()
        .all(|url| !iroh::defaults::prod::default_relay_map().contains(url)));
    a.set_device_info("A".into(), "desktop".into())
        .await
        .unwrap();
    b.set_device_info("B".into(), "mobile".into())
        .await
        .unwrap();
    a.replace_trusted_peers(vec![b.id()]).await.unwrap();
    b.replace_trusted_peers(vec![a.id()]).await.unwrap();
    a.replace_trusted_peers(vec![b.id()]).await.unwrap();
    let started = std::time::Instant::now();
    let ready = tokio::time::timeout(std::time::Duration::from_secs(45), async {
        tokio::join!(a.wait_until_online(), b.wait_until_online())
    })
    .await;
    if ready.is_err() {
        eprintln!(
            "a relay: {:?}, b relay: {:?}",
            a.endpoint.home_relay_status().get(),
            b.endpoint.home_relay_status().get()
        );
    }
    ready.unwrap();
    eprintln!("custom relay startup took {:?}", started.elapsed());
    a.begin_pairing(b.id()).await.unwrap();
    let attempt = a.begin_outgoing_pairing(b.id()).await.unwrap();
    let (pair, _) = tokio::time::timeout(std::time::Duration::from_secs(30), async {
        tokio::join!(attempt.request("A".into(), "desktop".into()), async {
            let offer = b.next_request().await.unwrap();
            assert_eq!(offer.info().pairing.unwrap().device_type, "desktop");
            offer
                .accept_pair("B".into(), "mobile".into())
                .await
                .unwrap();
        })
    })
    .await
    .unwrap();
    assert_eq!(pair.unwrap().name, "B");
    a.end_pairing(b.id()).await.unwrap();
    assert_eq!(a.check_peer(b.id()).await.unwrap().name, "B");
    let base = std::env::temp_dir().join(format!("vela-custom-relay-{}", std::process::id()));
    std::fs::create_dir_all(&base).unwrap();
    let file = base.join("test.txt");
    std::fs::write(&file, b"custom relay").unwrap();
    let receive = async {
        b.next_request()
            .await
            .unwrap()
            .receive_file(
                base.join("received").to_string_lossy().into_owned(),
                &b.new_transfer_job().unwrap(),
            )
            .await
            .unwrap()
    };
    std::fs::create_dir_all(base.join("received")).unwrap();
    let (sent, received) = tokio::time::timeout(std::time::Duration::from_secs(30), async {
        tokio::join!(
            a.send_file_to(
                b.endpoint.addr(),
                file.to_string_lossy().into_owned(),
                "file".into()
            ),
            receive
        )
    })
    .await
    .unwrap();
    sent.unwrap();
    assert_eq!(std::fs::read(received).unwrap(), b"custom relay");
    a.close().await;
    b.close().await;
    std::fs::remove_dir_all(base).unwrap();
}
#[tokio::test]
#[ignore = "requires VELA_RELAY_TEST_URL and VELA_RELAY_TEST_TOKEN_FILE"]
async fn private_relay_transfers_and_rejects_bad_token() {
    use super::*;
    use iroh::{RelayMap, RelayMode};
    let path = std::env::var("VELA_RELAY_TEST_TOKEN_FILE").unwrap();
    let credentials = std::fs::read_to_string(path).unwrap();
    let token = credentials.trim();
    let url = RelayUrl::from_str(&std::env::var("VELA_RELAY_TEST_URL").unwrap()).unwrap();
    assert_eq!(
        test_relay(url.to_string(), Some(token.to_string()))
            .await
            .unwrap(),
        "connected"
    );
    assert_eq!(
        test_relay(url.to_string(), Some("invalid".to_string()))
            .await
            .unwrap(),
        "auth"
    );
    let make_map =
        |token: &str| RelayMap::from(RelayConfig::from(url.clone()).with_auth_token(token));
    let bad = Endpoint::builder(presets::N0)
        .relay_mode(RelayMode::Custom(make_map("invalid")))
        .clear_ip_transports()
        .alpns(vec![alpn::TRANSFER.to_vec()])
        .bind()
        .await
        .unwrap();
    assert!(
        tokio::time::timeout(std::time::Duration::from_secs(8), bad.online())
            .await
            .is_err()
    );
    bad.close().await;
    let a = Endpoint::builder(presets::N0)
        .relay_mode(RelayMode::Custom(RelayMap::empty()))
        .clear_ip_transports()
        .alpns(vec![alpn::TRANSFER.to_vec()])
        .bind()
        .await
        .unwrap();
    let (_, offers) = mpsc::channel(1);
    let node = VelaNode {
        presence: None,
        endpoint: a.clone(),
        trust: Arc::new(RwLock::new(crate::trust::TrustState::default())),
        network_changes: watch::channel(0).0,
        device_info: Arc::new(RwLock::new(None)),
        transfer_slots: Arc::new(tokio::sync::Semaphore::new(1)),
        incoming_requests: Mutex::new(offers),
    };
    assert!(node
        .add_relay("http://example.com/".into(), None)
        .await
        .is_err());
    node.add_relay(url.to_string(), Some(token.to_string()))
        .await
        .unwrap();
    let b = Endpoint::builder(presets::N0)
        .relay_mode(RelayMode::Custom(make_map(token)))
        .clear_ip_transports()
        .alpns(vec![alpn::TRANSFER.to_vec()])
        .bind()
        .await
        .unwrap();
    tokio::time::timeout(std::time::Duration::from_secs(30), async {
        tokio::join!(a.online(), b.online())
    })
    .await
    .unwrap();
    let (client, server) = tokio::time::timeout(std::time::Duration::from_secs(30), async {
        tokio::join!(a.connect(b.addr(), alpn::TRANSFER), async {
            b.accept().await.unwrap().accept().unwrap().await
        })
    })
    .await
    .unwrap();
    let client = client.unwrap();
    let server = server.unwrap();
    let send_job = node.new_transfer_job().unwrap();
    set_transfer_connection(&send_job.transfer, &client, true).unwrap();
    let (_, receiver_offers) = mpsc::channel(1);
    let receiver = VelaNode {
        presence: None,
        endpoint: b.clone(),
        trust: Arc::new(RwLock::new(crate::trust::TrustState::default())),
        network_changes: watch::channel(0).0,
        device_info: Arc::new(RwLock::new(None)),
        transfer_slots: Arc::new(tokio::sync::Semaphore::new(1)),
        incoming_requests: Mutex::new(receiver_offers),
    };
    let receive_job = receiver.new_transfer_job().unwrap();
    set_transfer_connection(&receive_job.transfer, &server, false).unwrap();
    assert_eq!(send_job.progress().path, "relay");
    assert_eq!(receive_job.progress().path, "");
    let synced = tokio::time::timeout(std::time::Duration::from_secs(10), async {
        tokio::select! {
            _ = async { while receive_job.progress().path != "relay" { tokio::time::sleep(std::time::Duration::from_millis(10)).await; } } => true,
            _ = publish_transfer_path(&client) => false,
            _ = receive_transfer_path(&server, &receive_job.transfer) => false,
        }
    }).await.unwrap();
    assert!(synced);
    let payload = vec![42u8; 128 * 1024];
    let (sent, received) = tokio::join!(
        async {
            let mut s = client.open_uni().await?;
            s.write_all(&payload).await?;
            s.finish()?;
            Ok::<_, anyhow::Error>(())
        },
        async {
            let mut r = server.accept_uni().await?;
            let mut b = vec![0; payload.len()];
            r.read_exact(&mut b).await?;
            Ok::<_, anyhow::Error>(b)
        }
    );
    sent.unwrap();
    assert_eq!(received.unwrap(), payload);
    assert!(client.paths().iter().any(|path| path.is_relay()));
    assert_eq!(send_job.progress().path, "relay");
    node.remove_relay(url.to_string()).await.unwrap();
    a.close().await;
    b.close().await;
}
#[tokio::test]
#[ignore = "requires access to public Iroh relay servers"]
async fn relay_only_connection_reports_relay_traffic() {
    use super::*;
    let a = Endpoint::builder(presets::N0)
        .clear_ip_transports()
        .alpns(vec![alpn::TRANSFER.to_vec()])
        .bind()
        .await
        .unwrap();
    let b = Endpoint::builder(presets::N0)
        .clear_ip_transports()
        .alpns(vec![alpn::TRANSFER.to_vec()])
        .bind()
        .await
        .unwrap();
    tokio::time::timeout(std::time::Duration::from_secs(45), async {
        tokio::join!(a.online(), b.online())
    })
    .await
    .unwrap();
    let (client, server) = tokio::time::timeout(std::time::Duration::from_secs(45), async {
        tokio::join!(a.connect(b.addr(), alpn::TRANSFER), async {
            b.accept().await.unwrap().accept().unwrap().await
        })
    })
    .await
    .unwrap();
    let client = client.unwrap();
    let server = server.unwrap();
    let (_, offers) = mpsc::channel(1);
    let node = VelaNode {
        presence: None,
        endpoint: a.clone(),
        trust: Arc::new(RwLock::new(crate::trust::TrustState::default())),
        network_changes: watch::channel(0).0,
        device_info: Arc::new(RwLock::new(None)),
        transfer_slots: Arc::new(tokio::sync::Semaphore::new(1)),
        incoming_requests: Mutex::new(offers),
    };
    let send_job = node.new_transfer_job().unwrap();
    set_transfer_connection(&send_job.transfer, &client, true).unwrap();
    let _ = send_job.progress();
    let data = vec![5u8; 512 * 1024];
    let (sent, received) = tokio::time::timeout(std::time::Duration::from_secs(45), async {
        tokio::join!(
            async {
                let mut s = client.open_uni().await?;
                s.write_all(&data).await?;
                s.finish()?;
                s.stopped().await?;
                Ok::<_, anyhow::Error>(())
            },
            async {
                let mut r = server.accept_uni().await?;
                let mut buf = vec![0; data.len()];
                r.read_exact(&mut buf).await?;
                Ok::<_, anyhow::Error>(buf)
            }
        )
    })
    .await
    .unwrap();
    sent.unwrap();
    assert_eq!(received.unwrap(), data);
    let progress = send_job.progress();
    assert_eq!(progress.path, "relay");
    assert!(progress.udp_bytes_sent > 0);
    a.close().await;
    b.close().await;
}
#[tokio::test]
async fn sender_network_counter_tracks_real_connection_traffic() {
    use super::*;
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
    let sender = start_node(generate_secret()).await.unwrap();
    let receiver = start_node(generate_secret()).await.unwrap();
    receiver
        .replace_trusted_peers(vec![sender.id()])
        .await
        .unwrap();
    sender
        .replace_trusted_peers(vec![receiver.id()])
        .await
        .unwrap();
    let base = std::env::temp_dir().join(format!("vela-rate-test-{}", std::process::id()));
    std::fs::create_dir_all(&base).unwrap();
    let source = base.join("data.bin");
    let size = 8 * 1024 * 1024;
    std::fs::write(&source, vec![7u8; size]).unwrap();
    let send_job = sender.new_transfer_job().unwrap();
    let receive_job = receiver.new_transfer_job().unwrap();
    let finished = AtomicBool::new(false);
    let received_bytes = AtomicUsize::new(0);
    let completion_sent = AtomicBool::new(false);
    let sending = async {
        let _run = send_job.start().unwrap();
        let result = send_job
            .send_file_to(
                receiver.endpoint.addr(),
                source.to_string_lossy().into_owned(),
                "file".into(),
            )
            .await;
        finished.store(true, Ordering::Relaxed);
        result
    };
    let receiving = async {
        let offer = receiver.next_request().await.unwrap();
        let mut send = offer.send.lock().await.take().unwrap();
        let mut recv = offer.recv.lock().await.take().unwrap();
        set_transfer_connection(&receive_job.transfer, &offer._connection, false).unwrap();
        with_path_monitor(
            async {
                send.write_u8(1).await.unwrap();
                let mut remaining = size;
                let mut last_report = (0, tokio::time::Instant::now());
                let mut buf = vec![0u8; 16 * 1024];
                while remaining > 0 {
                    let cap = remaining.min(buf.len());
                    let n = recv.read(&mut buf[..cap]).await.unwrap().unwrap();
                    remaining -= n;
                    received_bytes.store(size - remaining, Ordering::Relaxed);
                    report_receipt_progress(&mut send, (size - remaining) as u64, &mut last_report)
                        .await
                        .unwrap();
                    tokio::time::sleep(std::time::Duration::from_millis(4)).await;
                }
                let mut hash = [0; 32];
                recv.read_exact(&mut hash).await.unwrap();
                completion_sent.store(true, Ordering::Relaxed);
                send.write_u8(1).await.unwrap();
                send.finish().unwrap();
                let _ = send.stopped().await;
            },
            receive_transfer_path(&offer._connection, &receive_job.transfer),
        )
        .await;
    };
    let observing = async {
        let mut previous = send_job.progress();
        let mut saw_network_activity = false;
        let mut saw_matching_path = false;
        while !finished.load(Ordering::Relaxed) {
            tokio::time::sleep(std::time::Duration::from_millis(150)).await;
            let now = send_job.progress();
            assert!(
                now.done <= received_bytes.load(Ordering::Relaxed) as u64,
                "sender progress exceeded received bytes"
            );
            if !completion_sent.load(Ordering::Relaxed) {
                assert!(
                    now.done < size as u64,
                    "sender reached 100% before receiver confirmed completion"
                );
            }
            if now.done > 0 && now.udp_bytes_sent > previous.udp_bytes_sent + 1024 {
                saw_network_activity = true;
            }
            if !now.path.is_empty() && now.path == receive_job.progress().path {
                saw_matching_path = true;
            }
            previous = now;
        }
        (saw_network_activity, saw_matching_path)
    };
    let (sent, _, observed) = tokio::time::timeout(std::time::Duration::from_secs(45), async {
        tokio::join!(sending, receiving, observing)
    })
    .await
    .unwrap();
    sent.unwrap();
    assert!(
        observed.0,
        "expected connection network counter to advance during transfer"
    );
    assert!(
        observed.1,
        "expected receiver to display the sender's selected path"
    );
    sender.close().await;
    receiver.close().await;
    std::fs::remove_dir_all(base).unwrap();
}
#[tokio::test]
async fn revoked_offer_cannot_start_after_unpair_or_repair() {
    use super::*;
    let a = start_node(generate_secret()).await.unwrap();
    let b = start_node(generate_secret()).await.unwrap();
    a.replace_trusted_peers(vec![b.id()]).await.unwrap();
    let base = std::env::temp_dir().join(format!("vela-revoked-offer-{}", std::process::id()));
    std::fs::create_dir_all(&base).unwrap();
    let first = base.join("one.txt");
    let second = base.join("two.txt");
    std::fs::write(&first, b"one").unwrap();
    std::fs::write(&second, b"two").unwrap();
    for batch in [false, true] {
        for change in 0..3 {
            b.replace_trusted_peers(vec![a.id()]).await.unwrap();
            let output = base.join(format!("out-{batch}-{change}"));
            std::fs::create_dir_all(&output).unwrap();
            let send = async {
                if batch {
                    a.send_files_to(
                        b.endpoint.addr(),
                        vec![
                            first.to_string_lossy().into_owned(),
                            second.to_string_lossy().into_owned(),
                        ],
                    )
                    .await
                } else {
                    a.send_file_to(
                        b.endpoint.addr(),
                        first.to_string_lossy().into_owned(),
                        "file".into(),
                    )
                    .await
                }
            };
            tokio::pin!(send);
            let offer = tokio::select! {
                result = &mut send => panic!("sender finished before acceptance: {result:?}"),
                offer = b.next_request() => offer.unwrap(),
            };
            if change < 2 {
                b.replace_trusted_peers(vec![]).await.unwrap();
            }
            if change == 1 {
                b.replace_trusted_peers(vec![a.id()]).await.unwrap();
            }
            if change == 2 {
                b.begin_pairing(a.id()).await.unwrap();
                b.end_pairing(a.id()).await.unwrap();
            }
            let result = if batch {
                offer
                    .receive_files(
                        output.to_string_lossy().into_owned(),
                        &b.new_transfer_job().unwrap(),
                    )
                    .await
                    .map(|_| ())
            } else {
                offer
                    .receive_file(
                        output.to_string_lossy().into_owned(),
                        &b.new_transfer_job().unwrap(),
                    )
                    .await
                    .map(|_| ())
            };
            assert!(
                result.is_err(),
                "a request from a revoked session must not be accepted"
            );
            assert!(std::fs::read_dir(&output).unwrap().next().is_none());
            assert!(
                tokio::time::timeout(std::time::Duration::from_secs(10), &mut send)
                    .await
                    .unwrap()
                    .is_err()
            );
        }
    }
    a.close().await;
    b.close().await;
    std::fs::remove_dir_all(base).unwrap();
}
#[tokio::test]
async fn unrelated_trust_change_does_not_invalidate_offer() {
    use super::*;
    let a = start_node(generate_secret()).await.unwrap();
    let b = start_node(generate_secret()).await.unwrap();
    let other = SecretKey::generate().public().to_string();
    b.replace_trusted_peers(vec![a.id()]).await.unwrap();
    a.replace_trusted_peers(vec![b.id()]).await.unwrap();
    let base = std::env::temp_dir().join(format!("vela-unrelated-trust-{}", std::process::id()));
    std::fs::create_dir_all(base.join("out")).unwrap();
    let source = base.join("one.txt");
    std::fs::write(&source, b"one").unwrap();
    let send = a.send_file_to(
        b.endpoint.addr(),
        source.to_string_lossy().into_owned(),
        "file".into(),
    );
    tokio::pin!(send);
    let offer = tokio::select! {
        result = &mut send => panic!("sender finished before acceptance: {result:?}"),
        offer = b.next_request() => offer.unwrap(),
    };
    b.replace_trusted_peers(vec![a.id(), other]).await.unwrap();
    let receive_job = b.new_transfer_job().unwrap();
    let receive = offer.receive_file(
        base.join("out").to_string_lossy().into_owned(),
        &receive_job,
    );
    let (sent, received) = tokio::time::timeout(std::time::Duration::from_secs(20), async {
        tokio::join!(send, receive)
    })
    .await
    .unwrap();
    sent.unwrap();
    assert_eq!(std::fs::read(received.unwrap()).unwrap(), b"one");
    assert!(b
        .replace_trusted_peers(vec!["invalid-device-id".into()])
        .await
        .is_err());
    a.close().await;
    b.close().await;
    std::fs::remove_dir_all(base).unwrap();
}
#[tokio::test]
async fn presence_session_authenticates_and_stops_after_unpair() {
    use super::*;
    let a = start_node(generate_secret()).await.unwrap();
    let b = start_node(generate_secret()).await.unwrap();
    b.set_device_info("Phone".into(), "mobile".into())
        .await
        .unwrap();
    b.replace_trusted_peers(vec![a.id()]).await.unwrap();
    a.replace_trusted_peers(vec![b.id()]).await.unwrap();
    let conn = tokio::time::timeout(
        std::time::Duration::from_secs(10),
        a.endpoint.connect(b.endpoint.addr(), alpn::PRESENCE),
    )
    .await
    .unwrap()
    .unwrap();
    let mut ping = vec![1];
    ping.extend_from_slice(&[3; 8]);
    conn.send_datagram(ping.clone().into()).unwrap();
    let pong = tokio::time::timeout(std::time::Duration::from_secs(5), conn.read_datagram())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(&pong[..9], &[2, 3, 3, 3, 3, 3, 3, 3, 3]);
    assert_eq!(
        serde_json::from_slice::<DeviceInfo>(&pong[9..])
            .unwrap()
            .name,
        "Phone"
    );
    b.replace_trusted_peers(vec![]).await.unwrap();
    conn.send_datagram(ping.into()).unwrap();
    assert!(matches!(
        tokio::time::timeout(std::time::Duration::from_secs(5), conn.read_datagram()).await,
        Ok(Err(_))
    ));
    a.close().await;
    b.close().await;
}

#[cfg(target_os = "macos")]
#[tokio::test]
async fn folder_archive_transfers_and_restores_over_local_iroh() {
    use super::*;
    use crate::api::folder::new_folder_archive_job;
    let a = start_local_test_node(generate_secret()).await.unwrap();
    let b = start_local_test_node(generate_secret()).await.unwrap();
    a.replace_trusted_peers(vec![b.id()]).await.unwrap();
    b.replace_trusted_peers(vec![a.id()]).await.unwrap();
    a.replace_trusted_peers(vec![b.id()]).await.unwrap();
    let temp = tempfile::tempdir().unwrap();
    let source = temp.path().join("source");
    let staging = temp.path().join("staging");
    let output = temp.path().join("output");
    std::fs::create_dir_all(source.join("nested/empty")).unwrap();
    std::fs::create_dir(&staging).unwrap();
    std::fs::create_dir(&output).unwrap();
    std::fs::write(source.join("nested/data.txt"), b"folder transfer").unwrap();
    let archive = new_folder_archive_job()
        .pack(
            source.to_string_lossy().into_owned(),
            staging.to_string_lossy().into_owned(),
        )
        .await
        .unwrap();
    let receive = async {
        let offer = b.next_request().await.unwrap();
        assert_eq!(offer.info().kind, "file");
        assert!(offer.info().name.ends_with(".vela-folder.zip"));
        offer
            .receive_file(
                output.to_string_lossy().into_owned(),
                &b.new_transfer_job().unwrap(),
            )
            .await
            .unwrap()
    };
    let send = a.send_file_to(b.endpoint.addr(), archive, "file".into());
    let (sent, received) = tokio::time::timeout(std::time::Duration::from_secs(30), async {
        tokio::join!(send, receive)
    })
    .await
    .unwrap();
    sent.unwrap();
    let restored = new_folder_archive_job()
        .restore(received, output.to_string_lossy().into_owned())
        .await
        .unwrap();
    assert_eq!(
        std::fs::read(std::path::Path::new(&restored).join("nested/data.txt")).unwrap(),
        b"folder transfer"
    );
    assert!(std::path::Path::new(&restored)
        .join("nested/empty")
        .is_dir());
    a.close().await;
    b.close().await;
}

#[test]
fn validates_relay_origins() {
    use super::*;
    assert_eq!(
        relay_origin("  https://example.com  ").unwrap().to_string(),
        "https://example.com/"
    );
    for url in [
        "http://example.com/",
        "https://user:password@example.com/",
        "https://example.com/path",
        "https://example.com/?query=1",
        "https://example.com/#fragment",
    ] {
        assert_eq!(
            relay_origin(url).unwrap_err().to_string(),
            "relay must be an HTTPS origin",
            "{url}"
        );
    }
    assert_eq!(
        relay_origin("not a URL").unwrap_err().to_string(),
        "invalid relay URL"
    );
}

#[tokio::test]
async fn truncated_source_fails_and_removes_received_files() {
    use super::*;
    let a = start_node(generate_secret()).await.unwrap();
    let b = start_node(generate_secret()).await.unwrap();
    b.replace_trusted_peers(vec![a.id()]).await.unwrap();
    a.replace_trusted_peers(vec![b.id()]).await.unwrap();
    let temp = tempfile::tempdir().unwrap();
    let base = temp.path();
    std::fs::create_dir_all(base.join("in")).unwrap();
    let first = base.join("in/first.txt");
    let second = base.join("in/second.txt");
    for batch in [false, true] {
        std::fs::write(&first, b"first").unwrap();
        std::fs::write(&second, b"second").unwrap();
        let output = base.join(format!("out-{batch}"));
        std::fs::create_dir_all(&output).unwrap();
        let send = async {
            if batch {
                a.send_files_to(
                    b.endpoint.addr(),
                    vec![
                        first.to_string_lossy().into_owned(),
                        second.to_string_lossy().into_owned(),
                    ],
                )
                .await
            } else {
                a.send_file_to(
                    b.endpoint.addr(),
                    first.to_string_lossy().into_owned(),
                    "file".into(),
                )
                .await
            }
        };
        tokio::pin!(send);
        let offer = tokio::select! {
            result = &mut send => panic!("sender finished before acceptance: {result:?}"),
            offer = b.next_request() => offer.unwrap(),
        };
        std::fs::write(if batch { &second } else { &first }, b"").unwrap();
        let receive = async {
            if batch {
                offer
                    .receive_files(
                        output.to_string_lossy().into_owned(),
                        &b.new_transfer_job().unwrap(),
                    )
                    .await
                    .map(|_| ())
            } else {
                offer
                    .receive_file(
                        output.to_string_lossy().into_owned(),
                        &b.new_transfer_job().unwrap(),
                    )
                    .await
                    .map(|_| ())
            }
        };
        let (sent, received) = tokio::time::timeout(std::time::Duration::from_secs(20), async {
            tokio::join!(send, receive)
        })
        .await
        .unwrap();
        assert_eq!(sent.unwrap_err().to_string(), "file changed while sending");
        assert!(received.is_err());
        assert!(std::fs::read_dir(&output).unwrap().next().is_none());
    }
    a.close().await;
    b.close().await;
}

#[tokio::test]
async fn sends_between_two_local_iroh_nodes() {
    use super::*;
    let a = start_node(generate_secret()).await.unwrap();
    let b = start_node(generate_secret()).await.unwrap();
    b.replace_trusted_peers(vec![a.id()]).await.unwrap();
    a.replace_trusted_peers(vec![b.id()]).await.unwrap();
    let base = std::env::temp_dir().join(format!("vela-test-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&base);
    std::fs::create_dir_all(base.join("in")).unwrap();
    std::fs::create_dir_all(base.join("out")).unwrap();
    let source = base.join("in/data.bin");
    let contents = vec![123u8; 256 * 1024 + 7];
    std::fs::write(&source, &contents).unwrap();
    a.replace_trusted_peers(vec![b.id()]).await.unwrap();
    for (sender, receiver, kind) in [
        (&a, &b, "file"),
        (&b, &a, "text"),
        (&a, &b, "typed_text"),
        (&a, &b, "image"),
        (&b, &a, "clipboard_file"),
    ] {
        let destination = base.join(format!("out/{kind}"));
        std::fs::create_dir_all(&destination).unwrap();
        if kind == "file" {
            std::fs::write(destination.join("data.bin"), b"existing").unwrap();
        }
        let receive = async {
            let offer = receiver.next_request().await.unwrap();
            assert_eq!(offer.info().sender, sender.id());
            assert_eq!(offer.info().kind, kind);
            offer
                .receive_file(
                    destination.to_string_lossy().into_owned(),
                    &receiver.new_transfer_job().unwrap(),
                )
                .await
                .unwrap();
        };
        let send = sender.send_file_to(
            receiver.endpoint.addr(),
            source.to_string_lossy().into_owned(),
            kind.into(),
        );
        let (sent, _) = tokio::time::timeout(std::time::Duration::from_secs(30), async {
            tokio::join!(send, receive)
        })
        .await
        .unwrap();
        sent.unwrap();
        let received_name = if kind == "file" {
            "data (1).bin"
        } else {
            "data.bin"
        };
        assert_eq!(
            std::fs::read(destination.join(received_name)).unwrap(),
            contents
        );
        if kind == "file" {
            assert_eq!(
                std::fs::read(destination.join("data.bin")).unwrap(),
                b"existing"
            );
        }
    }
    std::fs::write(&source, vec![0u8; 1024 * 1024 + 1]).unwrap();
    let oversized = a
        .send_file_to(
            b.endpoint.addr(),
            source.to_string_lossy().into_owned(),
            "typed_text".into(),
        )
        .await;
    assert_eq!(oversized.unwrap_err().to_string(), "text is too large");
    a.close().await;
    b.close().await;
    std::fs::remove_dir_all(base).unwrap();
}
#[tokio::test]
async fn receiver_rejects_oversized_typed_text() {
    use super::*;
    let a = start_node(generate_secret()).await.unwrap();
    let b = start_node(generate_secret()).await.unwrap();
    b.replace_trusted_peers(vec![a.id()]).await.unwrap();
    a.replace_trusted_peers(vec![b.id()]).await.unwrap();
    let conn = a
        .endpoint
        .connect(b.endpoint.addr(), alpn::TRANSFER)
        .await
        .unwrap();
    let (mut send, mut recv) = conn.open_bi().await.unwrap();
    let header = serde_json::to_vec(&RequestHeader {
        name: "message.txt".into(),
        size: 1024 * 1024 + 1,
        kind: "typed_text".into(),
        files: vec![],
    })
    .unwrap();
    send.write_u32(header.len() as u32).await.unwrap();
    send.write_all(&header).await.unwrap();
    send.finish().unwrap();
    assert!(
        tokio::time::timeout(std::time::Duration::from_secs(5), recv.read_u8())
            .await
            .unwrap()
            .is_err()
    );
    assert!(
        tokio::time::timeout(std::time::Duration::from_millis(100), b.next_request())
            .await
            .is_err()
    );
    a.close().await;
    b.close().await;
}

#[tokio::test]
async fn sends_multiple_files_with_one_offer() {
    use super::*;
    let a = start_node(generate_secret()).await.unwrap();
    let b = start_node(generate_secret()).await.unwrap();
    b.replace_trusted_peers(vec![a.id()]).await.unwrap();
    a.replace_trusted_peers(vec![b.id()]).await.unwrap();
    let dir = std::env::temp_dir().join(format!("vela-batch-test-{}", std::process::id()));
    std::fs::create_dir_all(dir.join("in")).unwrap();
    std::fs::create_dir_all(dir.join("out")).unwrap();
    let one = dir.join("in/photo.png");
    let two = dir.join("in/video.mp4");
    std::fs::write(&one, [1u8; 100]).unwrap();
    std::fs::write(&two, [2u8; 200]).unwrap();
    std::fs::write(dir.join("out/photo.png"), b"existing").unwrap();
    let send = a.send_files_to(
        b.endpoint.addr(),
        vec![
            one.to_string_lossy().into_owned(),
            two.to_string_lossy().into_owned(),
        ],
    );
    let receive = async {
        let offer = b.next_request().await.unwrap();
        assert_eq!(offer.info().files, vec!["photo.png", "video.mp4"]);
        assert_eq!(offer.info().size, 300);
        offer
            .receive_files(
                dir.join("out").to_string_lossy().into_owned(),
                &b.new_transfer_job().unwrap(),
            )
            .await
            .unwrap()
    };
    let (result, paths) = tokio::time::timeout(std::time::Duration::from_secs(30), async {
        tokio::join!(send, receive)
    })
    .await
    .unwrap();
    result.unwrap();
    assert_eq!(std::fs::read(&paths[0]).unwrap(), [1u8; 100]);
    assert_eq!(std::fs::read(&paths[1]).unwrap(), [2u8; 200]);
    assert_eq!(
        std::fs::read(dir.join("out/photo.png")).unwrap(),
        b"existing"
    );
    a.close().await;
    b.close().await;
    std::fs::remove_dir_all(dir).unwrap();
}

#[tokio::test]
async fn receiver_can_decline_without_creating_a_file() {
    use super::*;
    let a = start_node(generate_secret()).await.unwrap();
    let b = start_node(generate_secret()).await.unwrap();
    b.replace_trusted_peers(vec![a.id()]).await.unwrap();
    a.replace_trusted_peers(vec![b.id()]).await.unwrap();
    let path = std::env::temp_dir().join(format!("vela-decline-{}.txt", std::process::id()));
    std::fs::write(&path, b"private").unwrap();
    let send = a.send_file_to(
        b.endpoint.addr(),
        path.to_string_lossy().into_owned(),
        "file".into(),
    );
    let receive = async { b.next_request().await.unwrap().decline().await.unwrap() };
    let (result, _) = tokio::time::timeout(std::time::Duration::from_secs(30), async {
        tokio::join!(send, receive)
    })
    .await
    .unwrap();
    assert!(result.unwrap_err().to_string().contains("declined"));
    a.close().await;
    b.close().await;
    std::fs::remove_file(path).unwrap();
}
#[tokio::test]
async fn declined_transfer_waits_for_response_fin() {
    use super::*;
    let a = start_node(generate_secret()).await.unwrap();
    let b = start_node(generate_secret()).await.unwrap();
    b.replace_trusted_peers(vec![a.id()]).await.unwrap();
    a.replace_trusted_peers(vec![b.id()]).await.unwrap();
    let path = std::env::temp_dir().join(format!("vela-decline-fin-{}.txt", std::process::id()));
    std::fs::write(&path, b"private").unwrap();
    let send = a.send_file_to(
        b.endpoint.addr(),
        path.to_string_lossy().into_owned(),
        "file".into(),
    );
    let receive = async {
        let offer = b.next_request().await.unwrap();
        let mut response = offer.send.lock().await.take().unwrap();
        response.write_u8(0).await.unwrap();
        tokio::time::sleep(std::time::Duration::from_millis(150)).await;
        response.finish().unwrap();
        let result = tokio::time::timeout(std::time::Duration::from_secs(2), response.stopped())
            .await
            .unwrap();
        response_acknowledged(result)
    };
    let (sent, acknowledged) = tokio::time::timeout(std::time::Duration::from_secs(30), async {
        tokio::join!(send, receive)
    })
    .await
    .unwrap();
    assert!(sent.unwrap_err().to_string().contains("declined"));
    acknowledged.unwrap();
    a.close().await;
    b.close().await;
    std::fs::remove_file(path).unwrap();
}
#[tokio::test]
async fn response_completion_rejects_extra_bytes_and_reset() {
    use super::*;
    const TEST_ALPN: &[u8] = b"vela/test-response-fin";
    let a = Endpoint::builder(presets::N0DisableRelay)
        .bind()
        .await
        .unwrap();
    let b = Endpoint::builder(presets::N0DisableRelay)
        .alpns(vec![TEST_ALPN.to_vec()])
        .bind()
        .await
        .unwrap();
    let (conn_a, conn_b) = tokio::join!(a.connect(b.addr(), TEST_ALPN), async {
        b.accept().await.unwrap().await
    });
    let conn_a = conn_a.unwrap();
    let conn_b = conn_b.unwrap();
    let mut extra = conn_a.open_uni().await.unwrap();
    extra.write_all(&[1, 42]).await.unwrap();
    extra.finish().unwrap();
    let mut recv = conn_b.accept_uni().await.unwrap();
    assert_eq!(recv.read_u8().await.unwrap(), 1);
    assert!(check_response_end(&mut recv)
        .await
        .unwrap_err()
        .to_string()
        .contains("unexpected data"));

    let mut incomplete = conn_a.open_uni().await.unwrap();
    incomplete.write_u8(1).await.unwrap();
    let mut recv = conn_b.accept_uni().await.unwrap();
    assert_eq!(recv.read_u8().await.unwrap(), 1);
    incomplete.reset(7u32.into()).unwrap();
    assert!(check_response_end(&mut recv).await.is_err());
    a.close().await;
    b.close().await;
}
#[tokio::test]
async fn complete_transfer_receipt_survives_delayed_fin() {
    use super::*;
    const TEST_ALPN: &[u8] = b"vela/test-delayed-receipt-fin";
    let a = Endpoint::builder(presets::N0DisableRelay)
        .bind()
        .await
        .unwrap();
    let b = Endpoint::builder(presets::N0DisableRelay)
        .alpns(vec![TEST_ALPN.to_vec()])
        .bind()
        .await
        .unwrap();
    let (conn_a, conn_b) = tokio::join!(a.connect(b.addr(), TEST_ALPN), async {
        b.accept().await.unwrap().await
    });
    let conn_a = conn_a.unwrap();
    let conn_b = conn_b.unwrap();
    let mut send = conn_a.open_uni().await.unwrap();
    send.write_u8(2).await.unwrap();
    send.write_u64(3).await.unwrap();
    send.write_u8(1).await.unwrap();
    let mut recv = conn_b.accept_uni().await.unwrap();
    let progress = StdMutex::new((0, 8));
    let receiver = read_receipt_progress(&mut recv, &progress, 8);
    let sender = async {
        tokio::time::sleep(std::time::Duration::from_millis(2300)).await;
        let _ = send.finish();
    };
    let (received, _) = tokio::join!(receiver, sender);
    received.unwrap();
    assert_eq!(*progress.lock().unwrap(), (3, 8));
    a.close().await;
    b.close().await;
}
#[tokio::test]
async fn cancel_while_waiting_for_acceptance_closes_offer() {
    use super::*;
    let a = start_node(generate_secret()).await.unwrap();
    let b = start_node(generate_secret()).await.unwrap();
    b.replace_trusted_peers(vec![a.id()]).await.unwrap();
    a.replace_trusted_peers(vec![b.id()]).await.unwrap();
    let path = std::env::temp_dir().join(format!("vela-cancel-offer-{}.txt", std::process::id()));
    std::fs::write(&path, b"test").unwrap();
    let send_job = a.new_transfer_job().unwrap();
    let send = async {
        let _run = send_job.start()?;
        send_job
            .send_file_cancellable_to(
                b.endpoint.addr(),
                path.to_string_lossy().into_owned(),
                "file".into(),
            )
            .await
    };
    let cancel = async {
        let offer = b.next_request().await.unwrap();
        send_job.cancel();
        offer.wait_for_connection_close().await;
    };
    let (result, _) = tokio::time::timeout(std::time::Duration::from_secs(30), async {
        tokio::join!(send, cancel)
    })
    .await
    .unwrap();
    assert!(result.unwrap_err().to_string().contains("cancelled"));
    a.close().await;
    b.close().await;
    std::fs::remove_file(path).unwrap();
}

#[tokio::test]
async fn cancelling_receiver_removes_incomplete_file() {
    use super::*;
    let a = start_node(generate_secret()).await.unwrap();
    let b = start_node(generate_secret()).await.unwrap();
    b.replace_trusted_peers(vec![a.id()]).await.unwrap();
    a.replace_trusted_peers(vec![b.id()]).await.unwrap();
    let dir = std::env::temp_dir().join(format!("vela-cancel-receive-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let sender = async {
        let conn = a
            .endpoint
            .connect(b.endpoint.addr(), alpn::TRANSFER)
            .await
            .unwrap();
        let (mut send, mut recv) = conn.open_bi().await.unwrap();
        let header = serde_json::to_vec(&RequestHeader {
            name: "partial.bin".into(),
            size: 1024 * 1024,
            kind: "file".into(),
            files: vec![],
        })
        .unwrap();
        send.write_u32(header.len() as u32).await.unwrap();
        send.write_all(&header).await.unwrap();
        assert_eq!(recv.read_u8().await.unwrap(), 1);
        send.write_all(&[7; 4096]).await.unwrap();
        conn.closed().await;
    };
    let receiver = async {
        let offer = b.next_request().await.unwrap();
        let receive_job = b.new_transfer_job().unwrap();
        let receive = offer.receive_file(dir.to_string_lossy().into_owned(), &receive_job);
        let cancel = async {
            while receive_job.progress().done == 0 {
                tokio::time::sleep(std::time::Duration::from_millis(5)).await;
            }
            receive_job.cancel();
        };
        let (result, _) = tokio::join!(receive, cancel);
        assert!(result.is_err());
        assert!(!dir.join("partial.bin").exists());
    };
    tokio::time::timeout(std::time::Duration::from_secs(30), async {
        tokio::join!(sender, receiver)
    })
    .await
    .unwrap();
    a.close().await;
    b.close().await;
    std::fs::remove_dir_all(dir).unwrap();
}

#[test]
fn rejects_unsafe_filenames() {
    for name in ["", ".", "..", "../secret", "x/y", "x\\y", "a\0b"] {
        assert!(!valid_file_name(name));
    }
    assert!(valid_file_name("报告.pdf"));
}
#[tokio::test]
async fn same_name_does_not_overwrite_existing_file() {
    let dir = std::env::temp_dir().join(format!("vela-collision-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("报告.pdf"), b"original").unwrap();
    let (path, _file) = create_unique_destination(&dir, "报告.pdf").await.unwrap();
    assert_eq!(path.file_name().unwrap(), "报告 (1).pdf");
    assert_eq!(std::fs::read(dir.join("报告.pdf")).unwrap(), b"original");
    drop(_file);
    std::fs::remove_dir_all(dir).unwrap();
}
#[tokio::test]
async fn pairing_exchanges_authenticated_device_info_after_acceptance() {
    use super::*;
    let a = start_local_test_node(generate_secret()).await.unwrap();
    let b = start_local_test_node(generate_secret()).await.unwrap();
    b.replace_trusted_peers(vec![]).await.unwrap();
    let request = a.request_pair_to(b.endpoint.addr(), "Phone".into(), "mobile".into());
    let accept = async {
        let offer = b.next_request().await.unwrap();
        assert_eq!(offer.info().sender, a.id());
        assert_eq!(offer.info().pairing.unwrap().name, "Phone");
        assert_eq!(offer.info().pairing.unwrap().device_type, "mobile");
        assert_eq!(
            b.trust.read().await.status(&a.id()),
            crate::trust::TrustStatus::Pending
        );
        assert!(b.trust.read().await.sessions.is_empty());
        offer
            .accept_pair("Laptop".into(), "desktop".into())
            .await
            .unwrap();
    };
    let (result, ()) = tokio::time::timeout(std::time::Duration::from_secs(30), async {
        tokio::join!(request, accept)
    })
    .await
    .unwrap();
    let info = result.unwrap();
    assert_eq!(info.name, "Laptop");
    assert_eq!(info.device_type, "desktop");
    a.close().await;
    b.close().await;
}

#[tokio::test]
async fn repeated_pairing_requests_each_require_acceptance() {
    use super::*;
    let a = start_local_test_node(generate_secret()).await.unwrap();
    let b = start_local_test_node(generate_secret()).await.unwrap();
    for _ in 0..2 {
        let request = a.request_pair_to(b.endpoint.addr(), "Phone".into(), "mobile".into());
        let receive = async {
            let offer = b.next_request().await.unwrap();
            assert_eq!(offer.info().sender, a.id());
            offer
                .accept_pair("Laptop".into(), "desktop".into())
                .await
                .unwrap();
        };
        let (result, ()) = tokio::time::timeout(std::time::Duration::from_secs(30), async {
            tokio::join!(request, receive)
        })
        .await
        .unwrap();
        assert_eq!(result.unwrap().name, "Laptop");
    }
    let invalid = a
        .request_pair_to(b.endpoint.addr(), "".into(), "mobile".into())
        .await;
    assert!(invalid
        .unwrap_err()
        .to_string()
        .contains("invalid pairing information"));
    a.close().await;
    b.close().await;
}

#[tokio::test]
async fn stopped_pair_response_is_not_accepted() {
    use super::*;
    let a = Endpoint::builder(presets::N0DisableRelay)
        .bind()
        .await
        .unwrap();
    let b = Endpoint::builder(presets::N0DisableRelay)
        .alpns(vec![alpn::PAIRING.to_vec()])
        .bind()
        .await
        .unwrap();
    let (conn_a, conn_b) = tokio::join!(a.connect(b.addr(), alpn::PAIRING), async {
        b.accept().await.unwrap().await
    });
    let conn_a = conn_a.unwrap();
    let conn_b = conn_b.unwrap();
    let (mut request, mut response) = conn_a.open_bi().await.unwrap();
    request.write_u8(1).await.unwrap();
    let (response_sender, _) = conn_b.accept_bi().await.unwrap();
    response.stop(7u32.into()).unwrap();
    let result = tokio::time::timeout(
        std::time::Duration::from_secs(10),
        response_sender.stopped(),
    )
    .await
    .unwrap();
    assert!(matches!(&result, Ok(Some(code)) if code.into_inner() == 7));
    assert!(response_acknowledged(result).is_err());
    a.close().await;
    b.close().await;
}

#[tokio::test]
async fn pairing_collision_is_distinct_from_explicit_decline() {
    use super::*;
    let a = start_node(generate_secret()).await.unwrap();
    let b = start_node(generate_secret()).await.unwrap();
    let request = a.request_pair_to(b.endpoint.addr(), "Phone".into(), "mobile".into());
    let collision = async {
        b.next_request()
            .await
            .unwrap()
            .decline_pair_conflict()
            .await
            .unwrap()
    };
    let (result, _) = tokio::time::timeout(std::time::Duration::from_secs(30), async {
        tokio::join!(request, collision)
    })
    .await
    .unwrap();
    assert!(result.unwrap_err().to_string().contains("pairing conflict"));
    assert!(b.trust.read().await.sessions.is_empty());
    a.close().await;
    b.close().await;
}
#[tokio::test]
async fn pairing_can_be_declined() {
    use super::*;
    let a = start_node(generate_secret()).await.unwrap();
    let b = start_node(generate_secret()).await.unwrap();
    let request = a.request_pair_to(b.endpoint.addr(), "Phone".into(), "mobile".into());
    let decline = async { b.next_request().await.unwrap().decline().await.unwrap() };
    let (result, _) = tokio::time::timeout(std::time::Duration::from_secs(30), async {
        tokio::join!(request, decline)
    })
    .await
    .unwrap();
    assert!(result.unwrap_err().to_string().contains("declined"));
    assert!(b.trust.read().await.sessions.is_empty());
    a.close().await;
    b.close().await;
}
#[tokio::test]
async fn authenticated_presence_query_reports_pending_until_initialized_and_while_pairing() {
    use super::*;
    let a = start_local_test_node(generate_secret()).await.unwrap();
    let b = start_local_test_node(generate_secret()).await.unwrap();
    let probe = async |nonce: u8| {
        let conn = a
            .endpoint
            .connect(b.endpoint.addr(), alpn::PRESENCE)
            .await
            .unwrap();
        let mut ping = vec![1];
        ping.extend_from_slice(&[nonce; 8]);
        conn.send_datagram(ping.into()).unwrap();
        let response =
            tokio::time::timeout(std::time::Duration::from_secs(5), conn.read_datagram())
                .await
                .unwrap()
                .unwrap();
        conn.close(0u32.into(), b"test complete");
        response
    };
    let response = probe(1).await;
    assert_eq!(&response[..], &[3, 1, 1, 1, 1, 1, 1, 1, 1]);
    b.replace_trusted_peers(vec![]).await.unwrap();
    let response = probe(2).await;
    assert_eq!(&response[..], &[4, 2, 2, 2, 2, 2, 2, 2, 2]);
    b.begin_pairing(a.id()).await.unwrap();
    let response = probe(3).await;
    assert_eq!(&response[..], &[3, 3, 3, 3, 3, 3, 3, 3, 3]);
    b.end_pairing(a.id()).await.unwrap();
    a.close().await;
    b.close().await;
}

#[tokio::test]
async fn untrusted_presence_query_never_exposes_device_metadata() {
    use super::*;
    let a = start_local_test_node(generate_secret()).await.unwrap();
    let b = start_local_test_node(generate_secret()).await.unwrap();
    b.set_device_info("Private device name".into(), "desktop".into())
        .await
        .unwrap();
    b.replace_trusted_peers(vec![]).await.unwrap();
    let conn = a
        .endpoint
        .connect(b.endpoint.addr(), alpn::PRESENCE)
        .await
        .unwrap();
    conn.send_datagram(vec![1, 7, 7, 7, 7, 7, 7, 7, 7].into())
        .unwrap();
    let response = tokio::time::timeout(std::time::Duration::from_secs(5), conn.read_datagram())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(&response[..], &[4, 7, 7, 7, 7, 7, 7, 7, 7]);
    a.close().await;
    b.close().await;
}

#[tokio::test]
async fn obsolete_status_protocol_is_not_accepted() {
    use super::*;
    let a = start_node(generate_secret()).await.unwrap();
    let b = start_node(generate_secret()).await.unwrap();
    for old_protocol in [
        b"vela/status/1".as_slice(),
        b"vela/file/2".as_slice(),
        b"vela/pair/1".as_slice(),
        b"vela/unpair/1".as_slice(),
        b"vela/presence/1".as_slice(),
    ] {
        let result = tokio::time::timeout(
            std::time::Duration::from_secs(10),
            a.endpoint.connect(b.endpoint.addr(), old_protocol),
        )
        .await
        .unwrap();
        assert!(result.is_err(), "old protocol must be rejected");
    }
    a.close().await;
    b.close().await;
}
#[tokio::test]
async fn revoked_presence_session_cannot_be_registered_after_repair() {
    use super::*;
    let a = start_local_test_node(generate_secret()).await.unwrap();
    let b = start_local_test_node(generate_secret()).await.unwrap();
    let sender = a.id();
    b.replace_trusted_peers(vec![sender.clone()]).await.unwrap();
    b.set_device_info("Before".into(), "desktop".into())
        .await
        .unwrap();
    let old_session = b.trust.read().await.sessions.get(&sender).unwrap().clone();
    let old = a
        .endpoint
        .connect(b.endpoint.addr(), alpn::PRESENCE)
        .await
        .unwrap();
    old.send_datagram(vec![1, 2, 3, 4, 5, 6, 7, 8, 9].into())
        .unwrap();
    let response = tokio::time::timeout(std::time::Duration::from_secs(5), old.read_datagram())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(response[0], 2);
    b.replace_trusted_peers(vec![]).await.unwrap();
    b.replace_trusted_peers(vec![sender.clone()]).await.unwrap();
    assert!(old_session.is_revoked());
    assert!(!b.trust.read().await.is_current(&sender, &old_session));
    let replacement = b.trust.read().await.sessions.get(&sender).unwrap().clone();
    assert!(!Arc::ptr_eq(&old_session, &replacement));
    tokio::time::timeout(std::time::Duration::from_secs(3), old.closed())
        .await
        .expect("old connection must close");
    let stale = a
        .endpoint
        .connect(b.endpoint.addr(), alpn::PRESENCE)
        .await
        .unwrap();
    assert!(
        !old_session.register(&stale),
        "revoked session cannot register a connection"
    );
    tokio::time::timeout(std::time::Duration::from_secs(3), stale.closed())
        .await
        .expect("stale registration must close connection");
    let fresh = a
        .endpoint
        .connect(b.endpoint.addr(), alpn::PRESENCE)
        .await
        .unwrap();
    fresh
        .send_datagram(vec![1, 2, 3, 4, 5, 6, 7, 8, 9].into())
        .unwrap();
    let response = tokio::time::timeout(std::time::Duration::from_secs(5), fresh.read_datagram())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(response[0], 2);
    a.close().await;
    b.close().await;
}

#[tokio::test]
async fn established_presence_session_is_closed_on_pairing_change() {
    use super::*;
    let a = Endpoint::builder(presets::Minimal)
        .relay_mode(RelayMode::Disabled)
        .bind()
        .await
        .unwrap();
    let b = start_node_with_relays(
        generate_secret(),
        vec!["https://127.0.0.1:9/".into()],
        vec![String::new()],
    )
    .await
    .unwrap();
    let sender = a.id().to_string();
    b.replace_trusted_peers(vec![sender.clone()]).await.unwrap();
    b.set_device_info("Before".into(), "desktop".into())
        .await
        .unwrap();
    let conn = a.connect(b.endpoint.addr(), alpn::PRESENCE).await.unwrap();
    conn.send_datagram(vec![1, 2, 3, 4, 5, 6, 7, 8, 9].into())
        .unwrap();
    let pong = tokio::time::timeout(std::time::Duration::from_secs(5), conn.read_datagram())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        pong.first(),
        Some(&2),
        "the old session must be registered before the pairing changes"
    );
    b.begin_pairing(sender.clone()).await.unwrap();
    tokio::time::timeout(std::time::Duration::from_secs(3), conn.closed())
        .await
        .expect("an established old-epoch session must close when the pairing changes");
    a.close().await;
    b.close().await;
}
#[tokio::test]
async fn removing_trust_interrupts_an_accepted_transfer_and_removes_partial_file() {
    use super::*;
    let a = start_local_test_node(generate_secret()).await.unwrap();
    let b = start_local_test_node(generate_secret()).await.unwrap();
    b.replace_trusted_peers(vec![a.id()]).await.unwrap();
    let dir = tempfile::tempdir().unwrap();
    let sender = async {
        let connection = a
            .endpoint
            .connect(b.endpoint.addr(), alpn::TRANSFER)
            .await
            .unwrap();
        let (mut send, mut recv) = connection.open_bi().await.unwrap();
        let header = serde_json::to_vec(&RequestHeader {
            name: "partial.bin".into(),
            size: 1024 * 1024,
            kind: "file".into(),
            files: vec![],
        })
        .unwrap();
        send.write_u32(header.len() as u32).await.unwrap();
        send.write_all(&header).await.unwrap();
        assert_eq!(recv.read_u8().await.unwrap(), 1);
        send.write_all(&[7; 4096]).await.unwrap();
        connection.closed().await;
    };
    let receiver = async {
        let offer = b.next_request().await.unwrap();
        let receive_job = b.new_transfer_job().unwrap();
        let receive = offer.receive_file(dir.path().to_string_lossy().into_owned(), &receive_job);
        let revoke = async {
            while receive_job.progress().done == 0 {
                tokio::task::yield_now().await;
            }
            b.replace_trusted_peers(vec![]).await.unwrap();
        };
        let (result, ()) = tokio::join!(receive, revoke);
        assert!(result.is_err(), "revocation must interrupt the transfer");
        assert!(
            !dir.path().join("partial.bin").exists(),
            "partial file must be removed"
        );
    };
    tokio::time::timeout(std::time::Duration::from_secs(20), async {
        tokio::join!(sender, receiver)
    })
    .await
    .unwrap();
    a.close().await;
    b.close().await;
}

async fn test_pairing_initiator(target: &super::VelaNode) -> super::VelaNode {
    use super::*;
    use iroh::address_lookup::memory::MemoryLookup;
    let lookup = MemoryLookup::new();
    lookup.add_endpoint_info(target.endpoint.addr());
    let endpoint = Endpoint::builder(presets::Minimal)
        .address_lookup(lookup)
        .bind()
        .await
        .unwrap();
    let (_tx, requests) = mpsc::channel(1);
    let a = VelaNode {
        presence: None,
        endpoint,
        trust: Arc::new(RwLock::new(crate::trust::TrustState::default())),
        network_changes: watch::channel(0).0,
        device_info: Arc::new(RwLock::new(None)),
        transfer_slots: Arc::new(tokio::sync::Semaphore::new(1)),
        incoming_requests: Mutex::new(requests),
    };
    a
}

#[tokio::test]
async fn cancelling_outgoing_pairing_closes_the_actual_connection() {
    use super::*;
    let b = start_local_test_node(generate_secret()).await.unwrap();
    b.replace_trusted_peers(vec![]).await.unwrap();
    let a = test_pairing_initiator(&b).await;
    a.replace_trusted_peers(vec![]).await.unwrap();
    a.begin_pairing(b.id()).await.unwrap();
    let attempt = a.begin_outgoing_pairing(b.id()).await.unwrap();
    let request = attempt.request("Phone".into(), "mobile".into());
    let cancel = async {
        let offer = b.next_request().await.unwrap();
        attempt.cancel();
        tokio::time::timeout(
            std::time::Duration::from_secs(5),
            offer.wait_for_connection_close(),
        )
        .await
        .expect("cancel must close the in-flight pairing connection");
    };
    let (result, ()) = tokio::time::timeout(std::time::Duration::from_secs(10), async {
        tokio::join!(request, cancel)
    })
    .await
    .unwrap();
    assert!(result.unwrap_err().to_string().contains("cancelled"));
    a.end_pairing(b.id()).await.unwrap();
    a.close().await;
    b.close().await;
}

#[tokio::test]
async fn incoming_pairing_guard_and_outgoing_pairing_do_not_clear_each_others_pending() {
    use super::*;
    let a = start_local_test_node(generate_secret()).await.unwrap();
    let b = start_local_test_node(generate_secret()).await.unwrap();
    b.replace_trusted_peers(vec![]).await.unwrap();
    let request = a.request_pair_to(b.endpoint.addr(), "Phone".into(), "mobile".into());
    let decline = async {
        let offer = b.next_request().await.unwrap();
        assert_eq!(
            b.trust.read().await.status(&a.id()),
            crate::trust::TrustStatus::Pending
        );
        b.begin_pairing(a.id()).await.unwrap();
        offer.decline().await.unwrap();
    };
    let (result, ()) = tokio::time::timeout(std::time::Duration::from_secs(10), async {
        tokio::join!(request, decline)
    })
    .await
    .unwrap();
    assert!(result.is_err());
    tokio::time::timeout(std::time::Duration::from_secs(3), async {
        loop {
            if !b.trust.read().await.incoming_pairings.contains_key(&a.id()) {
                break;
            }
            tokio::task::yield_now().await;
        }
    })
    .await
    .expect("closed incoming connection must release its pending guard");
    assert_eq!(
        b.trust.read().await.status(&a.id()),
        crate::trust::TrustStatus::Pending,
        "incoming completion must not clear outgoing pending state"
    );
    b.end_pairing(a.id()).await.unwrap();
    assert_eq!(
        b.trust.read().await.status(&a.id()),
        crate::trust::TrustStatus::Unpaired
    );
    a.close().await;
    b.close().await;
}

#[tokio::test]
async fn cancelled_old_pairing_attempt_cannot_cancel_a_new_attempt() {
    use super::*;
    let b = start_local_test_node(generate_secret()).await.unwrap();
    b.replace_trusted_peers(vec![]).await.unwrap();
    let a = test_pairing_initiator(&b).await;
    a.replace_trusted_peers(vec![]).await.unwrap();
    a.begin_pairing(b.id()).await.unwrap();
    let old = a.begin_outgoing_pairing(b.id()).await.unwrap();
    old.cancel();
    assert!(old.request("Phone".into(), "mobile".into()).await.is_err());
    let current = a.begin_outgoing_pairing(b.id()).await.unwrap();
    old.cancel();
    let request = current.request("Phone".into(), "mobile".into());
    let receive = async {
        let offer = b.next_request().await.unwrap();
        offer
            .accept_pair("Laptop".into(), "desktop".into())
            .await
            .unwrap();
    };
    let (result, ()) = tokio::time::timeout(std::time::Duration::from_secs(10), async {
        tokio::join!(request, receive)
    })
    .await
    .unwrap();
    assert_eq!(result.unwrap().name, "Laptop");
    a.end_pairing(b.id()).await.unwrap();
    a.close().await;
    b.close().await;
}

#[tokio::test]
async fn dropping_pairing_attempt_before_start_does_not_block_retry() {
    use super::*;
    let b = start_local_test_node(generate_secret()).await.unwrap();
    let a = test_pairing_initiator(&b).await;
    a.replace_trusted_peers(vec![]).await.unwrap();
    a.begin_pairing(b.id()).await.unwrap();
    let abandoned = a.begin_outgoing_pairing(b.id()).await.unwrap();
    drop(abandoned);
    let retry = a.begin_outgoing_pairing(b.id()).await.unwrap();
    retry.cancel();
    a.end_pairing(b.id()).await.unwrap();
    a.close().await;
    b.close().await;
}

#[tokio::test]
async fn full_pairing_queue_releases_the_rejected_request_guard() {
    use super::*;
    let a = start_local_test_node(generate_secret()).await.unwrap();
    let b = start_local_test_node(generate_secret()).await.unwrap();
    b.replace_trusted_peers(vec![]).await.unwrap();
    let mut connections = Vec::new();
    for index in 0..33 {
        let connection = a
            .endpoint
            .connect(b.endpoint.addr(), alpn::PAIRING)
            .await
            .unwrap();
        let (mut send, recv) = connection.open_bi().await.unwrap();
        let header = serde_json::to_vec(&RequestHeader {
            name: "Phone".into(),
            size: 0,
            kind: "pair_mobile".into(),
            files: vec![],
        })
        .unwrap();
        send.write_u32(header.len() as u32).await.unwrap();
        send.write_all(&header).await.unwrap();
        if index < 32 {
            tokio::time::timeout(std::time::Duration::from_secs(5), async {
                loop {
                    if b.trust.read().await.incoming_pairings.get(&a.id()).copied()
                        == Some(index + 1)
                    {
                        break;
                    }
                    tokio::task::yield_now().await;
                }
            })
            .await
            .expect("queued pairing guard must register");
            connections.push((connection, send, recv));
        } else {
            tokio::time::timeout(std::time::Duration::from_secs(5), connection.closed())
                .await
                .expect("full queue must close rejected pairing");
        }
    }
    assert_eq!(
        b.trust.read().await.incoming_pairings.get(&a.id()).copied(),
        Some(32)
    );
    for (connection, _, _) in connections {
        connection.close(0u32.into(), b"test complete");
    }
    tokio::time::timeout(std::time::Duration::from_secs(5), async {
        loop {
            if !b.trust.read().await.incoming_pairings.contains_key(&a.id()) {
                break;
            }
            tokio::task::yield_now().await;
        }
    })
    .await
    .expect("closed connections must release all pairing guards");
    assert_eq!(
        b.trust.read().await.status(&a.id()),
        crate::trust::TrustStatus::Unpaired
    );
    a.close().await;
    b.close().await;
}

#[tokio::test]
async fn pairing_acceptance_fails_if_requester_closes_before_acknowledging() {
    use super::*;
    let a = start_local_test_node(generate_secret()).await.unwrap();
    let b = start_local_test_node(generate_secret()).await.unwrap();
    b.replace_trusted_peers(vec![]).await.unwrap();
    let connection = a
        .endpoint
        .connect(b.endpoint.addr(), alpn::PAIRING)
        .await
        .unwrap();
    let (mut send, mut recv) = connection.open_bi().await.unwrap();
    let header = serde_json::to_vec(&RequestHeader {
        name: "Phone".into(),
        size: 0,
        kind: "pair_mobile".into(),
        files: vec![],
    })
    .unwrap();
    send.write_u32(header.len() as u32).await.unwrap();
    send.write_all(&header).await.unwrap();
    let accept = async {
        let offer = b.next_request().await.unwrap();
        offer.accept_pair("Laptop".into(), "desktop".into()).await
    };
    let disconnect = async {
        assert_eq!(recv.read_u8().await.unwrap(), 1);
        let len = recv.read_u32().await.unwrap() as usize;
        let mut data = vec![0; len];
        recv.read_exact(&mut data).await.unwrap();
        assert_eq!(
            serde_json::from_slice::<DeviceInfo>(&data).unwrap().name,
            "Laptop"
        );
        assert!(
            recv.read(&mut [0u8; 1]).await.unwrap().is_none(),
            "response must finish before ACK"
        );
        connection.close(0u32.into(), b"closed before acknowledgement");
    };
    let (result, ()) = tokio::time::timeout(std::time::Duration::from_secs(10), async {
        tokio::join!(accept, disconnect)
    })
    .await
    .unwrap();
    assert!(
        result.is_err(),
        "receiver must not report success without requester ACK"
    );
    a.close().await;
    b.close().await;
}

#[tokio::test]
async fn pairing_request_fails_when_success_response_is_truncated() {
    use super::*;
    let a = start_local_test_node(generate_secret()).await.unwrap();
    let b = Endpoint::builder(presets::Minimal)
        .relay_mode(RelayMode::Disabled)
        .alpns(vec![alpn::PAIRING.to_vec()])
        .bind()
        .await
        .unwrap();
    let request = a.request_pair_to(b.addr(), "Phone".into(), "mobile".into());
    let truncate = async {
        let connection = b.accept().await.unwrap().await.unwrap();
        let (mut send, mut recv) = connection.accept_bi().await.unwrap();
        let len = recv.read_u32().await.unwrap() as usize;
        let mut data = vec![0; len];
        recv.read_exact(&mut data).await.unwrap();
        send.write_u8(1).await.unwrap();
        send.write_u32(10).await.unwrap();
        send.write_all(b"abc").await.unwrap();
        send.finish().unwrap();
        let _ = send.stopped().await;
    };
    let (result, ()) = tokio::time::timeout(std::time::Duration::from_secs(10), async {
        tokio::join!(request, truncate)
    })
    .await
    .unwrap();
    assert!(
        result.is_err(),
        "a partial response cannot complete pairing"
    );
    a.close().await;
    b.close().await;
}

#[tokio::test]
async fn pairing_completion_handshake_succeeds_repeatedly_without_close_race() {
    use super::*;
    let a = start_local_test_node(generate_secret()).await.unwrap();
    let b = start_local_test_node(generate_secret()).await.unwrap();
    b.replace_trusted_peers(vec![]).await.unwrap();
    for _ in 0..12 {
        let request = a.request_pair_to(b.endpoint.addr(), "Phone".into(), "mobile".into());
        let accept = async {
            let offer = b.next_request().await.unwrap();
            offer.accept_pair("Laptop".into(), "desktop".into()).await
        };
        let (sent, received) = tokio::time::timeout(std::time::Duration::from_secs(10), async {
            tokio::join!(request, accept)
        })
        .await
        .unwrap();
        assert_eq!(sent.unwrap().name, "Laptop");
        received.expect("receiver must observe the acknowledgement before completion");
    }
    a.close().await;
    b.close().await;
}

#[tokio::test]
async fn unstarted_transfer_job_reserves_one_slot_and_drop_releases_it() {
    let node = start_local_test_node(generate_secret()).await.unwrap();
    let job = node.new_transfer_job().unwrap();
    assert!(node.new_transfer_job().is_err());
    drop(job);
    assert!(node.new_transfer_job().is_ok());
    node.close().await;
}

#[tokio::test]
async fn cancelling_old_job_before_start_does_not_cancel_its_replacement() {
    let node = start_local_test_node(generate_secret()).await.unwrap();
    let cancelled = node.new_transfer_job().unwrap();
    cancelled.cancel();
    let replacement = node.new_transfer_job().unwrap();
    let error = cancelled
        .send_file(node.id(), "unused".into(), "file".into())
        .await
        .unwrap_err();
    assert!(error.to_string().starts_with("[vela:cancelled] "));
    cancelled.cancel();
    drop(cancelled);
    assert!(!*replacement.transfer.lock().unwrap().cancel.borrow());
    assert!(node.new_transfer_job().is_err());
    drop(replacement);
    assert!(node.new_transfer_job().is_ok());
    node.close().await;
}

#[tokio::test]
async fn failed_transfer_releases_slot_and_cannot_be_started_twice() {
    let node = start_local_test_node(generate_secret()).await.unwrap();
    let failed = node.new_transfer_job().unwrap();
    assert!(failed
        .send_file("invalid-device-id".into(), "unused".into(), "file".into())
        .await
        .is_err());
    let replacement = node.new_transfer_job().unwrap();
    let error = failed
        .send_file(node.id(), "unused".into(), "file".into())
        .await
        .unwrap_err();
    assert_eq!(error.to_string(), "transfer job already started");
    failed.cancel();
    assert!(!*replacement.transfer.lock().unwrap().cancel.borrow());
    assert!(node.new_transfer_job().is_err());
    node.close().await;
}

#[tokio::test]
async fn completed_transfer_keeps_progress_while_releasing_both_slots() {
    let sender = start_local_test_node(generate_secret()).await.unwrap();
    let receiver = start_local_test_node(generate_secret()).await.unwrap();
    sender
        .replace_trusted_peers(vec![receiver.id()])
        .await
        .unwrap();
    receiver
        .replace_trusted_peers(vec![sender.id()])
        .await
        .unwrap();
    let temp = tempfile::tempdir().unwrap();
    let source = temp.path().join("source.txt");
    let destination = temp.path().join("received");
    std::fs::write(&source, b"completed transfer").unwrap();
    std::fs::create_dir(&destination).unwrap();
    let send_job = sender.new_transfer_job().unwrap();
    let receive_job = receiver.new_transfer_job().unwrap();
    let send = async {
        let _run = send_job.start()?;
        send_job
            .send_file_cancellable_to(
                receiver.endpoint.addr(),
                source.to_string_lossy().into_owned(),
                "file".into(),
            )
            .await
    };
    let receive = async {
        receiver
            .next_request()
            .await
            .unwrap()
            .receive_file(destination.to_string_lossy().into_owned(), &receive_job)
            .await
    };
    let (sent, received) = tokio::time::timeout(std::time::Duration::from_secs(10), async {
        tokio::join!(send, receive)
    })
    .await
    .unwrap();
    sent.unwrap();
    assert_eq!(
        std::fs::read(received.unwrap()).unwrap(),
        b"completed transfer"
    );
    assert_eq!(send_job.progress().done, 18);
    assert_eq!(receive_job.progress().done, 18);
    assert!(sender.new_transfer_job().is_ok());
    assert!(receiver.new_transfer_job().is_ok());
    sender.close().await;
    receiver.close().await;
}
