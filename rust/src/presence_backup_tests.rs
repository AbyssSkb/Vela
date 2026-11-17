use super::test_support::publish_response;
use super::*;
use crate::trust::{PeerSession, SharedTrust, TrustState};
use iroh::endpoint::presets;

fn test_trust(id: Option<&str>) -> SharedTrust {
    let mut state = TrustState {
        initialized: true,
        ..Default::default()
    };
    if let Some(id) = id {
        state
            .sessions
            .insert(id.to_owned(), Arc::new(PeerSession::default()));
    }
    Arc::new(RwLock::new(state))
}

struct Harness {
    receiver: Endpoint,
    observer: Endpoint,
    manager: PresenceManager,
    peer: Arc<PeerProbeState>,
    status: watch::Receiver<Status>,
    first: Connection,
    client: tokio::task::JoinHandle<()>,
    id: String,
}

fn reply(conn: &Connection, ping: &[u8]) {
    let info = DeviceInfo {
        name: "Phone".into(),
        device_type: "mobile".into(),
    };
    let mut pong = vec![2];
    pong.extend_from_slice(&ping[1..]);
    pong.extend_from_slice(&serde_json::to_vec(&info).unwrap());
    conn.send_datagram(pong.into()).unwrap();
}

impl Harness {
    async fn new() -> Self {
        let receiver = Endpoint::builder(presets::Minimal)
            .alpns(vec![alpn::PRESENCE.to_vec()])
            .bind()
            .await
            .unwrap();
        let observer = Endpoint::builder(presets::Minimal)
            .alpns(vec![alpn::PRESENCE.to_vec()])
            .bind()
            .await
            .unwrap();
        let id = receiver.id().to_string();
        let manager = PresenceManager::new(
            observer.clone(),
            test_trust(Some(&id)),
            Arc::new(Mutex::new(HashMap::new())),
            Arc::new(RwLock::new(None)),
        );
        let now = Instant::now();
        let peer = Arc::new(PeerProbeState {
            session: manager
                .trust
                .read()
                .await
                .sessions
                .get(&id)
                .cloned()
                .unwrap(),
            trace: NEXT_TRACE.fetch_add(1, Ordering::Relaxed),
            network_epoch: AtomicU64::new(0),
            last_used: StdMutex::new(now),
            min_sent: StdMutex::new(Barriers::new(proof_clock::now())),
            status: watch::channel(Status::default()).0,
            wake: Notify::new(),
            stopped: AtomicBool::new(false),
            monitored: AtomicBool::new(false),
        });
        let mut status = peer.status.subscribe();
        manager.probes.lock().await.insert(id.clone(), peer.clone());
        let client = tokio::spawn(run_peer_presence(
            observer.clone(),
            receiver.addr(),
            id.clone(),
            peer.clone(),
            manager.probes.clone(),
            manager.trust.clone(),
            manager.info.clone(),
        ));
        let first = tokio::time::timeout(Duration::from_secs(3), async {
            receiver.accept().await.unwrap().await.unwrap()
        })
        .await
        .unwrap();
        let ping = tokio::time::timeout(Duration::from_secs(3), first.read_datagram())
            .await
            .unwrap()
            .unwrap();
        reply(&first, &ping);
        tokio::time::timeout(Duration::from_secs(3), status.changed())
            .await
            .unwrap()
            .unwrap();
        assert!(status.borrow().proof.is_some());
        Self {
            receiver,
            observer,
            manager,
            peer,
            status,
            first,
            client,
            id,
        }
    }

    async fn backup(&self) -> Connection {
        tokio::time::timeout(Duration::from_secs(2), async {
            self.receiver.accept().await.unwrap().await.unwrap()
        })
        .await
        .expect("backup was not dialed")
    }

    async fn stop(self) {
        self.peer.stopped.store(true, Ordering::Relaxed);
        self.peer.wake.notify_one();
        tokio::time::timeout(Duration::from_secs(2), self.client)
            .await
            .unwrap()
            .unwrap();
        self.first.close(0u32.into(), b"test complete");
        self.observer.close().await;
        self.receiver.close().await;
    }
}

#[tokio::test]
async fn unresponsive_backup_does_not_replace_recovered_old_session() {
    let mut h = Harness::new().await;
    h.manager.on_network_changed().await;
    let after_wake = h.peer.min_sent.lock().unwrap().network;
    let backup = h.backup().await;
    tokio::time::timeout(Duration::from_secs(2), async {
        loop {
            tokio::select! {
                result = h.first.read_datagram() => {
                    let ping = result.expect("old session closed before backup returned a PONG");
                    if ping.len() == 9 && ping[0] == 1 { reply(&h.first, &ping); }
                }
                result = h.status.changed() => {
                    result.unwrap();
                    if h.status.borrow().proof.as_ref().is_some_and(|(sent, _)| *sent >= after_wake) { break; }
                }
            }
        }
    }).await.expect("old session did not recover");
    assert!(
        h.first.close_reason().is_none(),
        "old session must survive until backup proves reachability"
    );
    tokio::time::timeout(Duration::from_secs(2), backup.closed())
        .await
        .expect("unneeded backup must be dropped");
    h.stop().await;
}

#[tokio::test]
async fn silent_sessions_do_not_extend_original_proof() {
    let h = Harness::new().await;
    let sent = h.status.borrow().proof.as_ref().unwrap().0;
    h.manager.on_network_changed().await;
    let backup = h.backup().await;
    ProofTimer::new()
        .wait_until(sent + LEASE + Duration::from_millis(30))
        .await;
    let result = tokio::time::timeout(Duration::from_millis(200), h.manager.check(&h.id, false))
        .await
        .expect("expired proof must return immediately");
    assert!(result.is_err());
    assert_eq!(
        h.status.borrow().proof.as_ref().map(|(at, _)| *at),
        Some(sent)
    );
    drop(backup);
    h.stop().await;
}

#[tokio::test]
async fn frequent_network_changes_keep_valid_delayed_pongs() {
    let h = Harness::new().await;
    let mut responses = tokio::task::JoinSet::new();
    let mut wake = tokio::time::interval(Duration::from_millis(400));
    let mut poll = tokio::time::interval(Duration::from_millis(250));
    let until = tokio::time::sleep(Duration::from_secs(4));
    tokio::pin!(until);
    loop {
        tokio::select! {
            _ = &mut until => break,
            _ = wake.tick() => h.manager.on_network_changed().await,
            _ = poll.tick() => assert!(h.manager.check(&h.id, false).await.is_ok(), "fresh PONGs should keep a reachable peer online"),
            data = h.first.read_datagram() => {
                let ping = data.unwrap();
                let conn = h.first.clone();
                responses.spawn(async move {
                    tokio::time::sleep(Duration::from_millis(600)).await;
                    reply(&conn, &ping);
                });
            }
        }
    }
    responses.shutdown().await;
    h.stop().await;
}

#[tokio::test]
async fn cold_start_keeps_responding_session_through_frequent_network_notifications() {
    let receiver = Endpoint::builder(presets::Minimal)
        .alpns(vec![alpn::PRESENCE.to_vec()])
        .bind()
        .await
        .unwrap();
    let observer = Endpoint::builder(presets::Minimal)
        .alpns(vec![alpn::PRESENCE.to_vec()])
        .bind()
        .await
        .unwrap();
    let id = receiver.id().to_string();
    let manager = Arc::new(PresenceManager::new(
        observer.clone(),
        test_trust(Some(&id)),
        Arc::new(Mutex::new(HashMap::new())),
        Arc::new(RwLock::new(None)),
    ));
    let now = Instant::now();
    let peer = Arc::new(PeerProbeState {
        session: manager
            .trust
            .read()
            .await
            .sessions
            .get(&id)
            .cloned()
            .unwrap(),
        trace: NEXT_TRACE.fetch_add(1, Ordering::Relaxed),
        network_epoch: AtomicU64::new(0),
        last_used: StdMutex::new(now),
        min_sent: StdMutex::new(Barriers::new(proof_clock::now())),
        status: watch::channel(Status::default()).0,
        wake: Notify::new(),
        stopped: AtomicBool::new(false),
        monitored: AtomicBool::new(false),
    });
    manager.probes.lock().await.insert(id.clone(), peer.clone());
    let client = tokio::spawn(run_peer_presence(
        observer.clone(),
        receiver.addr(),
        id.clone(),
        peer.clone(),
        manager.probes.clone(),
        manager.trust.clone(),
        manager.info.clone(),
    ));
    let (first_sender, first_receiver) = tokio::sync::oneshot::channel();
    let accepted = Arc::new(StdMutex::new(Vec::<(u64, Connection)>::new()));
    let sequence = Arc::new(AtomicU64::new(0));
    let blocked_through = Arc::new(AtomicU64::new(0));
    let server = {
        let receiver = receiver.clone();
        let accepted = accepted.clone();
        let sequence = sequence.clone();
        let blocked_through = blocked_through.clone();
        tokio::spawn(async move {
            let mut first_sender = Some(first_sender);
            while let Some(incoming) = receiver.accept().await {
                let sender = first_sender.take();
                let accepted = accepted.clone();
                let sequence = sequence.clone();
                let blocked_through = blocked_through.clone();
                tokio::spawn(async move {
                    let Ok(conn) = incoming.await else { return };
                    let number = sequence.fetch_add(1, Ordering::Relaxed) + 1;
                    accepted.lock().unwrap().push((number, conn.clone()));
                    if let Some(sender) = sender {
                        let _ = sender.send(conn.clone());
                    }
                    while let Ok(ping) = conn.read_datagram().await {
                        let conn = conn.clone();
                        let blocked_through = blocked_through.clone();
                        tokio::spawn(async move {
                            tokio::time::sleep(Duration::from_millis(600)).await;
                            if number <= blocked_through.load(Ordering::Relaxed) {
                                return;
                            }
                            let info = DeviceInfo {
                                name: "Phone".into(),
                                device_type: "mobile".into(),
                            };
                            let mut pong = vec![2];
                            pong.extend_from_slice(&ping[1..]);
                            pong.extend_from_slice(&serde_json::to_vec(&info).unwrap());
                            let _ = conn.send_datagram(pong.into());
                        });
                    }
                });
            }
        })
    };
    let first = tokio::time::timeout(Duration::from_secs(3), first_receiver)
        .await
        .unwrap()
        .unwrap();
    let wake = {
        let manager = manager.clone();
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_millis(100)).await;
            loop {
                manager.on_network_changed().await;
                tokio::time::sleep(Duration::from_millis(400)).await;
            }
        })
    };
    let poll = {
        let manager = manager.clone();
        let id = id.clone();
        tokio::spawn(async move {
            loop {
                let _ = manager.check(&id, false).await;
                tokio::time::sleep(Duration::from_millis(250)).await;
            }
        })
    };
    let proof = tokio::time::timeout(Duration::from_secs(3), async {
        loop {
            if manager.check(&id, false).await.is_ok() {
                break;
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
    })
    .await;
    let stays_online = tokio::time::timeout(Duration::from_secs(4), async {
        let mut interval = tokio::time::interval(Duration::from_millis(250));
        loop {
            tokio::select! {
                _ = first.closed() => return false,
                _ = interval.tick() => if manager.check(&id, false).await.is_err() { return false; },
            }
        }
    }).await.unwrap_or(true);
    wake.abort();
    let settled_network = peer.min_sent.lock().unwrap().network;
    let active = tokio::time::timeout(Duration::from_secs(3), async {
        loop {
            let proof_is_current = peer
                .status
                .borrow()
                .proof
                .as_ref()
                .is_some_and(|(sent, _)| *sent >= settled_network);
            let live: Vec<_> = accepted
                .lock()
                .unwrap()
                .iter()
                .filter(|(_, conn)| conn.close_reason().is_none())
                .cloned()
                .collect();
            if proof_is_current && live.len() == 1 {
                return live[0].1.clone();
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    })
    .await;
    let promoted = if let Ok(active) = active {
        blocked_through.store(sequence.load(Ordering::Relaxed), Ordering::Relaxed);
        manager.on_network_changed().await;
        let changed = peer.min_sent.lock().unwrap().network;
        tokio::time::timeout(Duration::from_secs(3), async {
            loop {
                let current_proof = peer
                    .status
                    .borrow()
                    .proof
                    .as_ref()
                    .is_some_and(|(sent, _)| *sent >= changed);
                if active.close_reason().is_some()
                    && current_proof
                    && manager.check(&id, false).await.is_ok()
                {
                    break;
                }
                tokio::time::sleep(Duration::from_millis(20)).await;
            }
        })
        .await
        .is_ok()
    } else {
        false
    };
    poll.abort();
    server.abort();
    peer.stopped.store(true, Ordering::Relaxed);
    peer.wake.notify_one();
    let _ = tokio::time::timeout(Duration::from_secs(2), client).await;
    observer.close().await;
    receiver.close().await;
    assert!(
        proof.is_ok(),
        "a valid delayed PONG should establish online proof despite notifications"
    );
    assert!(stays_online, "a healthy responding candidate should remain online and not be repeatedly torn down during network notifications");
    assert!(promoted, "after notifications settle, a current-epoch PONG must promote a candidate to the active session");
}

#[tokio::test]
async fn previous_network_pong_keeps_proof_without_cancelling_backup() {
    let mut h = Harness::new().await;
    let previous = h.status.borrow().proof.as_ref().unwrap().0;
    let old_ping = tokio::time::timeout(Duration::from_secs(2), h.first.read_datagram())
        .await
        .unwrap()
        .unwrap();
    h.manager.on_network_changed().await;
    let backup = h.backup().await;
    reply(&h.first, &old_ping);
    tokio::time::timeout(Duration::from_secs(1), async {
        loop {
            if h.status
                .borrow_and_update()
                .proof
                .as_ref()
                .is_some_and(|(sent, _)| *sent > previous)
            {
                break;
            }
            h.status.changed().await.unwrap();
        }
    })
    .await
    .expect("a valid old-network PONG must update the proof");
    assert!(
        tokio::time::timeout(Duration::from_millis(300), backup.closed())
            .await
            .is_err(),
        "a prior-network PONG must not cancel the new backup"
    );
    drop(backup);
    h.stop().await;
}

#[tokio::test]
async fn previous_network_backup_pong_does_not_cancel_other_candidate() {
    let mut h = Harness::new().await;
    let previous = h.status.borrow().proof.as_ref().unwrap().0;
    h.manager.on_network_changed().await;
    let first_backup = h.backup().await;
    let old_ping = tokio::time::timeout(Duration::from_secs(1), first_backup.read_datagram())
        .await
        .unwrap()
        .unwrap();
    let second_backup = h.backup().await;
    h.manager.on_network_changed().await;
    reply(&first_backup, &old_ping);
    tokio::time::timeout(Duration::from_secs(1), async {
        loop {
            if h.status
                .borrow_and_update()
                .proof
                .as_ref()
                .is_some_and(|(sent, _)| *sent > previous)
            {
                break;
            }
            h.status.changed().await.unwrap();
        }
    })
    .await
    .expect("a valid PONG from the previous network should update proof");
    assert!(
        tokio::time::timeout(Duration::from_millis(250), second_backup.closed())
            .await
            .is_err(),
        "a prior-network backup must not win and cancel another candidate"
    );
    assert!(
        first_backup.close_reason().is_none(),
        "the older backup must remain available for a fresh PONG"
    );
    assert!(
        h.first.close_reason().is_none(),
        "an older PONG must not replace the active connection"
    );
    drop(first_backup);
    drop(second_backup);
    h.stop().await;
}

#[tokio::test]
async fn polled_status_reports_silent_peer_offline_within_three_seconds() {
    let h = Harness::new().await;
    assert!(h.manager.check(&h.id, false).await.is_ok());
    let original = h.status.borrow().proof.as_ref().unwrap().0;

    // Keep the connection open but withhold the next PONG as if the peer vanished.
    let vanished_at = Instant::now();
    let stale_ping = tokio::time::timeout(Duration::from_secs(1), h.first.read_datagram())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(stale_ping.len(), 9);
    assert_eq!(stale_ping[0], 1);

    let mut poll = tokio::time::interval(Duration::from_millis(250));
    tokio::time::timeout(Duration::from_secs(3), async {
        loop {
            poll.tick().await;
            if h.manager.check(&h.id, false).await.is_err() {
                break;
            }
        }
    })
    .await
    .expect("a silent peer must become unavailable within three seconds");
    assert!(vanished_at.elapsed() < Duration::from_secs(3));
    assert!(
        h.first.close_reason().is_none(),
        "offline detection must not depend on a graceful connection close"
    );

    tokio::time::sleep_until((vanished_at + LEASE + Duration::from_millis(100)).into()).await;
    while let Ok(Ok(_)) =
        tokio::time::timeout(Duration::from_millis(20), h.first.read_datagram()).await
    {}
    reply(&h.first, &stale_ping);
    tokio::time::sleep(Duration::from_millis(200)).await;
    assert!(
        h.manager.check(&h.id, false).await.is_err(),
        "a late PONG must not bring the peer back online"
    );
    assert_eq!(
        h.status.borrow().proof.as_ref().map(|(sent, _)| *sent),
        Some(original)
    );

    let fresh_ping = tokio::time::timeout(Duration::from_secs(1), h.first.read_datagram())
        .await
        .unwrap()
        .unwrap();
    reply(&h.first, &fresh_ping);
    tokio::time::timeout(Duration::from_secs(1), async {
        loop {
            if h.manager.check(&h.id, false).await.is_ok() {
                break;
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    })
    .await
    .expect("a fresh PONG on the same connection must restore availability");
    h.stop().await;
}

#[tokio::test]
async fn repeated_network_changes_keep_one_backup_and_revoke_stops_it() {
    let h = Harness::new().await;
    h.manager.on_network_changed().await;
    let backup = h.backup().await;
    for _ in 0..5 {
        h.manager.on_network_changed().await;
        tokio::time::sleep(Duration::from_millis(60)).await;
    }
    assert!(
        tokio::time::timeout(Duration::from_millis(600), h.receiver.accept())
            .await
            .is_err(),
        "must not create another backup while one is pending"
    );
    {
        let mut trust = h.manager.trust.write().await;
        if let Some(session) = trust.sessions.remove(&h.id) {
            session.revoke();
        }
    }
    h.manager.reconcile_trusted_peers().await;
    assert!(h.peer.stopped.load(Ordering::Relaxed));
    tokio::time::timeout(Duration::from_secs(2), backup.closed())
        .await
        .expect("revocation must drop the backup");
    h.stop().await;
}

#[tokio::test]
async fn pending_backup_handshake_restarts_once_after_network_changes_settle() {
    let mut h = Harness::new().await;
    h.manager.on_network_changed().await;
    let old_incoming = tokio::time::timeout(Duration::from_secs(2), h.receiver.accept())
        .await
        .expect("first backup must start")
        .expect("receiver closed");
    // Keep the first incoming handshake pending while the network changes again.
    h.manager.on_network_changed().await;
    tokio::time::sleep(Duration::from_millis(100)).await;
    h.manager.on_network_changed().await;
    let latest_change = h.peer.min_sent.lock().unwrap().network;
    let next = tokio::time::timeout(Duration::from_secs(2), h.receiver.accept()).await;
    if next.is_err() {
        drop(old_incoming);
        h.stop().await;
        panic!("backup handshake did not restart for the latest network");
    }
    let candidate = tokio::time::timeout(Duration::from_secs(2), next.unwrap().unwrap())
        .await
        .unwrap()
        .unwrap();
    let ping = tokio::time::timeout(Duration::from_secs(2), candidate.read_datagram())
        .await
        .unwrap()
        .unwrap();
    reply(&candidate, &ping);
    tokio::time::timeout(Duration::from_secs(2), async {
        loop {
            if h.status
                .borrow_and_update()
                .proof
                .as_ref()
                .is_some_and(|(sent, _)| *sent >= latest_change)
            {
                break;
            }
            h.status.changed().await.unwrap();
        }
    })
    .await
    .expect("latest backup did not produce a fresh proof");
    assert!(
        tokio::time::timeout(Duration::from_millis(500), h.receiver.accept())
            .await
            .is_err(),
        "one settled network change must not create extra backups"
    );
    drop(old_incoming);
    candidate.close(0u32.into(), b"test complete");
    h.stop().await;
}

#[tokio::test]
async fn expired_proof_keeps_old_session_while_backup_handshake_is_pending() {
    let mut h = Harness::new().await;
    let sent = h.status.borrow().proof.as_ref().unwrap().0;
    ProofTimer::new()
        .wait_until(sent + LEASE + Duration::from_millis(80))
        .await;
    let offline =
        tokio::time::timeout(Duration::from_millis(200), h.manager.check(&h.id, false)).await;
    let old_live = h.first.close_reason().is_none();
    let backup_incoming =
        tokio::time::timeout(Duration::from_millis(800), h.receiver.accept()).await;
    let backup_started = matches!(&backup_incoming, Ok(Some(_)));
    let events = crate::diagnostics::events();
    let proof_expired = events.iter().any(|event| {
        event.trace == h.peer.trace && event.attempt == 1 && event.kind == "session_proof_expired"
    });
    let session_expired = events.iter().any(|event| {
        event.trace == h.peer.trace && event.attempt == 1 && event.kind == "session_expired"
    });
    let recovered = tokio::time::timeout(Duration::from_millis(1500), async {
        loop {
            tokio::select! {
                result = h.first.read_datagram() => {
                    let Ok(ping) = result else { return false; };
                    if ping.len() == 9 && ping[0] == 1 {
                        let info = DeviceInfo { name: "Phone".into(), device_type: "mobile".into() };
                        let mut pong = vec![2]; pong.extend_from_slice(&ping[1..]); pong.extend_from_slice(&serde_json::to_vec(&info).unwrap());
                        if h.first.send_datagram(pong.into()).is_err() { return false; }
                    }
                }
                result = h.status.changed() => {
                    if result.is_err() { return false; }
                    if h.status.borrow().proof.as_ref().is_some_and(|(new_sent, _)| *new_sent > sent) { return true; }
                }
            }
        }
    }).await.unwrap_or(false);
    drop(backup_incoming);
    h.stop().await;
    assert!(
        matches!(offline, Ok(Err(_))),
        "old proof must expire on its original deadline"
    );
    assert!(
        backup_started,
        "a backup must already be started after the proof expires"
    );
    assert!(
        old_live,
        "old session must remain available while a backup handshake is pending"
    );
    assert!(
        proof_expired,
        "proof expiry must be recorded for the original session"
    );
    assert!(
        !session_expired,
        "session expiry must not be recorded while it is still in grace"
    );
    assert!(
        recovered,
        "a fresh PONG on the old session must restore reachability"
    );
}

#[tokio::test]
async fn silent_old_session_grace_and_backup_are_bounded() {
    let h = Harness::new().await;
    let sent = h.status.borrow().proof.as_ref().unwrap().0;
    ProofTimer::new()
        .wait_until(sent + LEASE + Duration::from_millis(80))
        .await;
    let offline =
        tokio::time::timeout(Duration::from_millis(200), h.manager.check(&h.id, false)).await;
    assert!(
        matches!(offline, Ok(Err(_))),
        "the old proof must expire even while the connection remains open"
    );
    let backup = h.backup().await;
    let mut interval = tokio::time::interval(Duration::from_millis(250));
    tokio::time::timeout(Duration::from_secs(6), async {
        loop {
            tokio::select! {
                _ = h.first.closed() => break,
                _ = interval.tick() => {
                    let result = tokio::time::timeout(Duration::from_millis(200), h.manager.check(&h.id, false)).await;
                    assert!(matches!(result, Ok(Err(_))), "silent sessions must not renew the expired proof");
                }
            }
        }
    }).await.expect("silent old session must end within the grace period");
    tokio::time::timeout(Duration::from_secs(2), backup.closed())
        .await
        .expect("silent backup connection must also end");
    assert_eq!(
        h.status.borrow().proof.as_ref().map(|(at, _)| *at),
        Some(sent)
    );
    h.stop().await;
}

#[tokio::test]
async fn repeated_network_changes_during_grace_keep_one_backup_and_revoke_cleans_it() {
    let h = Harness::new().await;
    let sent = h.status.borrow().proof.as_ref().unwrap().0;
    ProofTimer::new()
        .wait_until(sent + LEASE + Duration::from_millis(80))
        .await;
    assert!(
        h.manager.check(&h.id, false).await.is_err(),
        "proof must be expired before grace-period wakes"
    );
    let backup = h.backup().await;
    assert!(
        h.first.close_reason().is_none(),
        "old session must still be in its grace period"
    );
    for _ in 0..5 {
        h.manager.on_network_changed().await;
        tokio::time::sleep(Duration::from_millis(60)).await;
    }
    assert!(
        tokio::time::timeout(Duration::from_millis(600), h.receiver.accept())
            .await
            .is_err(),
        "grace-period wakes must not start overlapping backups"
    );
    assert!(
        h.manager.check(&h.id, false).await.is_err(),
        "network changes must not renew the old proof"
    );
    {
        let mut trust = h.manager.trust.write().await;
        if let Some(session) = trust.sessions.remove(&h.id) {
            session.revoke();
        }
    }
    h.manager.reconcile_trusted_peers().await;
    assert!(h.peer.stopped.load(Ordering::Relaxed));
    tokio::time::timeout(Duration::from_secs(2), h.first.closed())
        .await
        .expect("revocation must close the old session");
    tokio::time::timeout(Duration::from_secs(2), backup.closed())
        .await
        .expect("revocation must close the backup");
    h.stop().await;
}

async fn diagnostic_event(
    trace: u64,
    attempt: Option<u64>,
    kind: &str,
) -> crate::api::node::DiagnosticEvent {
    tokio::time::timeout(Duration::from_secs(4), async {
        loop {
            if let Some(event) = crate::diagnostics::events().into_iter().find(|event| {
                event.trace == trace
                    && attempt.is_none_or(|value| event.attempt == value)
                    && event.kind == kind
            }) {
                return event;
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    })
    .await
    .unwrap_or_else(|_| panic!("missing {kind} diagnostic for trace {trace}"))
}

#[tokio::test]
async fn silent_backup_records_expired_for_its_own_attempt() {
    let h = Harness::new().await;
    h.manager.on_network_changed().await;
    let backup = h.backup().await;
    let dial = diagnostic_event(h.peer.trace, Some(2), "dial_connected").await;
    let expired = diagnostic_event(h.peer.trace, Some(dial.attempt), "backup_expired").await;
    assert_eq!(expired.attempt, dial.attempt);
    assert!(expired.elapsed_ms >= LEASE.as_millis() as u64);
    drop(backup);
    h.stop().await;
}

#[tokio::test]
async fn remotely_closed_backup_records_closed_for_its_own_attempt() {
    let h = Harness::new().await;
    h.manager.on_network_changed().await;
    let backup = h.backup().await;
    let dial = diagnostic_event(h.peer.trace, Some(2), "dial_connected").await;
    backup.close(0u32.into(), b"test close");
    let closed = diagnostic_event(h.peer.trace, Some(dial.attempt), "backup_closed").await;
    assert_eq!(closed.attempt, dial.attempt);
    h.stop().await;
}

#[tokio::test]
async fn local_selected_ip_path_records_real_peer_and_address() {
    let h = Harness::new().await;
    let path = diagnostic_event(h.peer.trace, Some(1), "path_ip").await;
    assert_eq!(path.kind, "path_ip");
    let details: serde_json::Value = serde_json::from_str(&path.details).unwrap();
    assert_eq!(details["peer_id"].as_str(), Some(h.id.as_str()));
    assert_eq!(details["path_kind"].as_str(), Some("ip"));
    let remote = details["remote_addr"]
        .as_str()
        .expect("IP path must record a remote address");
    let remote: std::net::SocketAddr = remote
        .strip_prefix("ip:")
        .expect("IP transport prefix")
        .parse()
        .expect("remote must be a real IP and port");
    assert!(!remote.ip().is_unspecified());
    assert_ne!(remote.port(), 0);
    assert!(
        h.receiver
            .addr()
            .ip_addrs()
            .any(|address| *address == remote),
        "recorded remote must be one of the real receiver addresses"
    );
    h.stop().await;
}

#[tokio::test]
async fn failed_backup_is_retried_during_unchanged_network_grace() {
    let mut h = Harness::new().await;
    let original = h.status.borrow().proof.as_ref().unwrap().0;
    ProofTimer::new()
        .wait_until(original + LEASE + Duration::from_millis(80))
        .await;
    assert!(
        h.manager.check(&h.id, false).await.is_err(),
        "expired proof must be offline"
    );
    let failed = h.backup().await;
    failed.close(0u32.into(), b"test backup failure");
    let result = tokio::time::timeout(Duration::from_secs(2), async {
        let candidate = h.receiver.accept().await.unwrap().await.unwrap();
        let ping = candidate.read_datagram().await.unwrap();
        reply(&candidate, &ping);
        loop {
            if h.status
                .borrow_and_update()
                .proof
                .as_ref()
                .is_some_and(|(sent, _)| *sent > original)
            {
                return candidate;
            }
            h.status.changed().await.unwrap();
        }
    })
    .await;
    let recovered = result.is_ok();
    drop(result);
    h.stop().await;
    assert!(
        recovered,
        "a failed backup must be retried before the original grace period expires"
    );
}

async fn pending_dial_fixture() -> (Endpoint, PresenceManager, Arc<PeerProbeState>) {
    let endpoint = Endpoint::builder(presets::N0DisableRelay)
        .bind()
        .await
        .unwrap();
    let manager = PresenceManager::new(
        endpoint.clone(),
        test_trust(None),
        Arc::new(Mutex::new(HashMap::new())),
        Arc::new(RwLock::new(None)),
    );
    let now = Instant::now();
    let peer = Arc::new(PeerProbeState {
        session: Arc::new(PeerSession::default()),
        trace: NEXT_TRACE.fetch_add(1, Ordering::Relaxed),
        network_epoch: AtomicU64::new(0),
        last_used: StdMutex::new(now),
        min_sent: StdMutex::new(Barriers::new(proof_clock::now())),
        status: watch::channel(Status::default()).0,
        wake: Notify::new(),
        stopped: AtomicBool::new(false),
        monitored: AtomicBool::new(false),
    });
    manager
        .probes
        .lock()
        .await
        .insert("test".into(), peer.clone());
    (endpoint, manager, peer)
}

fn spawn_pending_backup(
    peer: Arc<PeerProbeState>,
) -> (
    tokio::sync::oneshot::Sender<()>,
    tokio::sync::oneshot::Receiver<Instant>,
    tokio::task::JoinHandle<Result<(), crate::diagnostics::DialOutcome>>,
) {
    let (complete, finished) = tokio::sync::oneshot::channel();
    let (started, clock) = tokio::sync::oneshot::channel();
    let epoch = peer.network_epoch.load(Ordering::Relaxed);
    let task = tokio::spawn(async move {
        wait_for_candidate_dial(
            async move {
                let _ = started.send(Instant::now());
                let _ = finished.await;
            },
            &peer,
            epoch,
        )
        .await
    });
    (complete, clock, task)
}

#[tokio::test]
async fn backup_dial_reacts_to_change_after_one_debounce_interval() {
    let (endpoint, manager, peer) = pending_dial_fixture().await;
    let (_complete, started, mut task) = spawn_pending_backup(peer.clone());
    let start = started.await.unwrap();
    tokio::time::sleep_until((start + Duration::from_millis(550)).into()).await;
    manager.on_network_changed().await;
    let changed = peer.min_sent.lock().unwrap().network;
    let result = tokio::time::timeout(Duration::from_millis(750), &mut task).await;
    let elapsed = changed.elapsed();
    if result.is_err() {
        task.abort();
    }
    endpoint.close().await;
    assert!(
        matches!(
            result,
            Ok(Ok(Err(crate::diagnostics::DialOutcome::NetworkChanged)))
        ),
        "pending dial must restart within one debounce interval plus scheduling tolerance"
    );
    assert!(
        elapsed >= Duration::from_millis(450),
        "network changes must be allowed to settle"
    );
}

#[tokio::test]
async fn backup_dial_debounce_follows_the_last_network_change() {
    let (endpoint, manager, peer) = pending_dial_fixture().await;
    let (_complete, started, mut task) = spawn_pending_backup(peer.clone());
    let start = started.await.unwrap();
    tokio::time::sleep_until((start + Duration::from_millis(550)).into()).await;
    manager.on_network_changed().await;
    tokio::time::sleep(Duration::from_millis(300)).await;
    manager.on_network_changed().await;
    let last_change = peer.min_sent.lock().unwrap().network;
    let result = tokio::time::timeout(Duration::from_millis(750), &mut task).await;
    let elapsed = last_change.elapsed();
    if result.is_err() {
        task.abort();
    }
    endpoint.close().await;
    assert!(matches!(
        result,
        Ok(Ok(Err(crate::diagnostics::DialOutcome::NetworkChanged)))
    ));
    assert!(
        elapsed >= Duration::from_millis(450),
        "restart must be delayed until the final change has settled"
    );
}

#[tokio::test]
async fn backup_dial_completion_and_stop_win_over_debounce() {
    let (endpoint, manager, peer) = pending_dial_fixture().await;
    let (complete, started, task) = spawn_pending_backup(peer.clone());
    started.await.unwrap();
    manager.on_network_changed().await;
    complete.send(()).unwrap();
    assert!(
        matches!(
            tokio::time::timeout(Duration::from_secs(1), task).await,
            Ok(Ok(Ok(())))
        ),
        "a completed connection must not be discarded while debouncing"
    );
    let (_complete, started, task) = spawn_pending_backup(peer.clone());
    started.await.unwrap();
    manager.reconcile_trusted_peers().await;
    assert!(
        matches!(
            tokio::time::timeout(Duration::from_secs(1), task).await,
            Ok(Ok(Err(crate::diagnostics::DialOutcome::Inactive)))
        ),
        "a stopped peer must cancel its pending backup"
    );
    endpoint.close().await;
}

#[tokio::test]
async fn resume_invalidates_unexpired_proof_but_network_wake_preserves_it() {
    let (endpoint, manager, peer) = pending_dial_fixture().await;
    let sent = proof_clock::now() - Duration::from_secs(1);
    let info = DeviceInfo {
        name: "Phone".into(),
        device_type: "mobile".into(),
    };
    let json = serde_json::to_vec(&info).unwrap();
    peer.min_sent.lock().unwrap().network = sent - Duration::from_millis(1);
    peer.status.send_replace(Status {
        proof: Some((sent, info)),
        unpaired: None,
        latest: Some(sent),
    });
    assert!(
        proof_clock::now() < sent + LEASE,
        "simulate wake while the old monotonic proof still appears fresh"
    );

    manager.invalidate_for_resume().await;
    assert!(
        peer.status.borrow().proof.is_none(),
        "resume must invalidate a pre-sleep proof even if its clock did not expire"
    );
    assert!(
        !publish_response(&peer, sent, &json),
        "a delayed pre-sleep PONG must not renew the proof"
    );
    assert!(peer.status.borrow().proof.is_none());

    let new_sent = loop {
        let now = proof_clock::now();
        if now >= peer.min_sent.lock().unwrap().network {
            break now;
        }
        std::hint::spin_loop();
    };
    assert!(
        publish_response(&peer, new_sent, &json),
        "a fresh post-resume PONG must recover presence"
    );
    manager.on_network_changed().await;
    assert_eq!(
        peer.status.borrow().proof.as_ref().map(|(at, _)| *at),
        Some(new_sent),
        "a regular network change must preserve the proof until its original deadline"
    );
    endpoint.close().await;
}

#[test]
fn pong_rejection_reasons_and_anonymous_counters_match() {
    let now = proof_clock::now();
    let peer = PeerProbeState {
        session: Arc::new(PeerSession::default()),
        trace: NEXT_TRACE.fetch_add(1, Ordering::Relaxed),
        network_epoch: AtomicU64::new(0),
        last_used: StdMutex::new(Instant::now()),
        min_sent: StdMutex::new(Barriers::new(now - Duration::from_secs(1))),
        status: watch::channel(Status::default()).0,
        wake: Notify::new(),
        stopped: AtomicBool::new(false),
        monitored: AtomicBool::new(false),
    };
    let mut stats = ProbeStats::new(peer.trace, 1, "backup");
    let info = DeviceInfo {
        name: "Phone".into(),
        device_type: "mobile".into(),
    };
    let valid = [vec![2; 9], serde_json::to_vec(&info).unwrap()].concat();
    let old_fresh = now - Duration::from_millis(1500);
    let expired = now - Duration::from_secs(3);
    let malformed = b"not json";

    peer.stopped.store(true, Ordering::Relaxed);
    let response = peer.accept_response(expired, malformed);
    assert_eq!(response, Err(PongRejection::Stopped));
    stats.record_response(&response);
    peer.stopped.store(false, Ordering::Relaxed);

    let response = peer.accept_response(old_fresh, malformed);
    assert_eq!(response, Err(PongRejection::EpochFresh));
    stats.record_response(&response);
    let response = peer.accept_response(expired, malformed);
    assert_eq!(response, Err(PongRejection::EpochExpired));
    stats.record_response(&response);

    peer.min_sent.lock().unwrap().resume = expired - Duration::from_millis(10);
    let response = peer.accept_response(expired, &valid);
    assert_eq!(response, Err(PongRejection::Expired));
    stats.record_response(&response);

    let invalid_name = [
        vec![2; 9],
        br#"{"name":"","device_type":"mobile"}"#.to_vec(),
    ]
    .concat();
    let invalid_type = [
        vec![2; 9],
        br#"{"name":"Phone","device_type":"unknown"}"#.to_vec(),
    ]
    .concat();
    for invalid in [
        malformed.as_slice(),
        invalid_name.as_slice(),
        invalid_type.as_slice(),
    ] {
        let response = peer.accept_response(now, invalid);
        assert_eq!(response, Err(PongRejection::Invalid));
        stats.record_response(&response);
    }
    assert!(
        peer.status.borrow().proof.is_none(),
        "rejected packets must not create proof"
    );
    let response = peer.accept_response(now, &valid);
    assert_eq!(response, Ok(()));
    stats.record_response(&response);
    assert_eq!(
        peer.status.borrow().proof.as_ref().map(|(sent, _)| *sent),
        Some(now)
    );

    assert_eq!(stats.pong_valid, 1);
    assert_eq!(stats.pong_rejected, 7);
    assert_eq!(
        (
            stats.reject_stopped,
            stats.reject_epoch_fresh,
            stats.reject_epoch_expired,
            stats.reject_expired,
            stats.reject_invalid
        ),
        (1, 1, 1, 1, 3)
    );
    assert_eq!((stats.reject_owner, stats.pong_unmatched), (0, 0));
}
