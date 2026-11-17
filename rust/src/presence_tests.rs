use super::test_support::{accept_response, publish_response};
use super::*;
fn paired(id: &str, session: &Arc<PeerSession>) -> SharedTrust {
    Arc::new(RwLock::new(crate::trust::TrustState {
        initialized: true,
        sessions: HashMap::from([(id.to_owned(), session.clone())]),
        ..Default::default()
    }))
}
fn empty_trust() -> SharedTrust {
    Arc::new(RwLock::new(crate::trust::TrustState {
        initialized: true,
        ..Default::default()
    }))
}
fn race_for_test<T>(
    first: CandidateFuture<T>,
    start: impl FnMut(Arc<AtomicBool>) -> Option<CandidateFuture<T>>,
) -> impl Future<Output = Option<T>> {
    race_candidates(
        first,
        Arc::new(AtomicBool::new(false)),
        Arc::new(Notify::new()),
        start,
    )
}
#[tokio::test]
async fn reordered_pong_does_not_expire_newer_connection_proof() {
    let session = Arc::new(PeerSession::default());
    use iroh::endpoint::presets;
    let receiver = Endpoint::builder(presets::N0DisableRelay)
        .alpns(vec![alpn::PRESENCE.to_vec()])
        .bind()
        .await
        .unwrap();
    let observer = Endpoint::builder(presets::N0DisableRelay)
        .alpns(vec![alpn::PRESENCE.to_vec()])
        .bind()
        .await
        .unwrap();
    let address = receiver.addr();
    let id = receiver.id().to_string();
    let server = tokio::spawn(async move {
        let conn = receiver.accept().await.unwrap().await.unwrap();
        let old = conn.read_datagram().await.unwrap();
        let _middle = conn.read_datagram().await.unwrap();
        let new = conn.read_datagram().await.unwrap();
        let info = DeviceInfo {
            name: "Phone".into(),
            device_type: "mobile".into(),
        };
        let json = serde_json::to_vec(&info).unwrap();
        let mut pong = vec![2];
        pong.extend_from_slice(&new[1..]);
        pong.extend_from_slice(&json);
        conn.send_datagram(pong.into()).unwrap();
        tokio::time::sleep(Duration::from_millis(900)).await;
        let mut pong = vec![2];
        pong.extend_from_slice(&old[1..]);
        pong.extend_from_slice(&json);
        conn.send_datagram(pong.into()).unwrap();
        let stayed_open = tokio::time::timeout(Duration::from_millis(900), conn.closed())
            .await
            .is_err();
        receiver.close().await;
        stayed_open
    });
    let now = Instant::now();
    let peer = Arc::new(PeerProbeState {
        session: session.clone(),
        trace: NEXT_TRACE.fetch_add(1, Ordering::Relaxed),
        network_epoch: AtomicU64::new(0),
        last_used: StdMutex::new(now),
        min_sent: StdMutex::new(Barriers::new(proof_clock::now())),
        status: watch::channel(Status::default()).0,
        wake: Notify::new(),
        stopped: AtomicBool::new(false),
        monitored: AtomicBool::new(false),
    });
    let peers = Arc::new(Mutex::new(HashMap::from([(id.clone(), peer.clone())])));
    let trusted = paired(&id, &session);
    let client = tokio::spawn(run_peer_presence(
        observer.clone(),
        address,
        id,
        peer.clone(),
        peers,
        trusted,
        Arc::new(RwLock::new(None)),
    ));
    let stayed_open = tokio::time::timeout(Duration::from_secs(10), server)
        .await
        .unwrap()
        .unwrap();
    peer.stopped.store(true, Ordering::Relaxed);
    peer.wake.notify_one();
    client.await.unwrap();
    observer.close().await;
    assert!(
        stayed_open,
        "an older pong must not shorten the newer proof's deadline"
    );
}

#[tokio::test]
async fn production_outgoing_and_incoming_share_bidirectional_proofs() {
    let session = Arc::new(PeerSession::default());
    use iroh::endpoint::presets;
    let a = Endpoint::builder(presets::N0DisableRelay)
        .alpns(vec![alpn::PRESENCE.to_vec()])
        .bind()
        .await
        .unwrap();
    let b = Endpoint::builder(presets::N0DisableRelay)
        .alpns(vec![alpn::PRESENCE.to_vec()])
        .bind()
        .await
        .unwrap();
    let a_id = a.id().to_string();
    let b_id = b.id().to_string();
    let a_info = Arc::new(RwLock::new(Some(DeviceInfo {
        name: "A".into(),
        device_type: "mobile".into(),
    })));
    let b_info = Arc::new(RwLock::new(Some(DeviceInfo {
        name: "B".into(),
        device_type: "desktop".into(),
    })));
    let b_manager = Arc::new(PresenceManager::new(
        b.clone(),
        paired(&a_id, &session),
        Arc::new(Mutex::new(HashMap::new())),
        b_info.clone(),
    ));
    let now = Instant::now();
    let new_peer = || {
        Arc::new(PeerProbeState {
            session: session.clone(),
            trace: NEXT_TRACE.fetch_add(1, Ordering::Relaxed),
            network_epoch: AtomicU64::new(0),
            last_used: StdMutex::new(now),
            min_sent: StdMutex::new(Barriers::new(proof_clock::now())),
            status: watch::channel(Status::default()).0,
            wake: Notify::new(),
            stopped: AtomicBool::new(false),
            monitored: AtomicBool::new(false),
        })
    };
    let a_peer = new_peer();
    let b_peer = new_peer();
    let mut a_status = a_peer.status.subscribe();
    let mut b_status = b_peer.status.subscribe();
    b_manager
        .probes
        .lock()
        .await
        .insert(a_id.clone(), b_peer.clone());
    let server = {
        let manager = b_manager.clone();
        let info = b_info.clone();
        let b = b.clone();
        tokio::spawn(async move {
            let conn = b.accept().await.unwrap().await.unwrap();
            let registered = {
                let trust = manager.trust.read().await;
                let session = trust.sessions.get(&a_id).unwrap().clone();
                assert!(session.register(&conn));
                Some(session)
            };
            manager.respond(&conn, &a_id, &info, registered).await;
        })
    };
    let peers = Arc::new(Mutex::new(HashMap::from([(b_id.clone(), a_peer.clone())])));
    let client = tokio::spawn(run_peer_presence(
        a.clone(),
        b.addr(),
        b_id.clone(),
        a_peer.clone(),
        peers,
        paired(&b_id, &session),
        a_info,
    ));
    tokio::time::timeout(Duration::from_secs(8), a_status.changed())
        .await
        .unwrap()
        .unwrap();
    tokio::time::timeout(Duration::from_secs(8), b_status.changed())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(a_status.borrow().proof.as_ref().unwrap().1.name, "B");
    assert_eq!(b_status.borrow().proof.as_ref().unwrap().1.name, "A");
    a_peer.stopped.store(true, Ordering::Relaxed);
    a_peer.wake.notify_one();
    client.await.unwrap();
    server.await.unwrap();
    a.close().await;
    b.close().await;
}

#[tokio::test]
async fn incoming_session_probes_only_while_observed() {
    let session = Arc::new(PeerSession::default());
    use iroh::endpoint::presets;
    let observer = Endpoint::builder(presets::N0DisableRelay)
        .alpns(vec![alpn::PRESENCE.to_vec()])
        .bind()
        .await
        .unwrap();
    let remote = Endpoint::builder(presets::N0DisableRelay)
        .alpns(vec![alpn::PRESENCE.to_vec()])
        .bind()
        .await
        .unwrap();
    let id = remote.id().to_string();
    let trusted = paired(&id, &session);
    let info = Arc::new(RwLock::new(Some(DeviceInfo {
        name: "Computer".into(),
        device_type: "desktop".into(),
    })));
    let manager = Arc::new(PresenceManager::new(
        observer.clone(),
        trusted,
        Arc::new(Mutex::new(HashMap::new())),
        info.clone(),
    ));
    let server = {
        let manager = manager.clone();
        let info = info.clone();
        let id = id.clone();
        tokio::spawn(async move {
            let conn = observer.accept().await.unwrap().await.unwrap();
            let registered = {
                let trust = manager.trust.read().await;
                let session = trust.sessions.get(&id).unwrap().clone();
                assert!(session.register(&conn));
                Some(session)
            };
            manager.respond(&conn, &id, &info, registered).await;
            observer.close().await;
        })
    };
    let conn = remote
        .connect(manager.endpoint.addr(), alpn::PRESENCE)
        .await
        .unwrap();
    assert!(
        tokio::time::timeout(Duration::from_millis(750), conn.read_datagram())
            .await
            .is_err(),
        "unobserved peer must not be probed"
    );
    let now = Instant::now();
    let peer = Arc::new(PeerProbeState {
        session: session.clone(),
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
    manager.probes.lock().await.insert(id, peer.clone());
    let ping = tokio::time::timeout(Duration::from_secs(3), conn.read_datagram())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(ping[0], 1);
    let remote_info = DeviceInfo {
        name: "Phone".into(),
        device_type: "mobile".into(),
    };
    let mut pong = vec![2];
    pong.extend_from_slice(&ping[1..]);
    pong.extend_from_slice(&serde_json::to_vec(&remote_info).unwrap());
    conn.send_datagram(pong.into()).unwrap();
    tokio::time::timeout(Duration::from_secs(3), status.changed())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(status.borrow().proof.as_ref().unwrap().1.name, "Phone");
    conn.close(0u32.into(), b"test complete");
    server.await.unwrap();
    remote.close().await;
    let events: Vec<_> = crate::diagnostics::events()
        .into_iter()
        .filter(|event| event.trace == peer.trace)
        .collect();
    assert_eq!(
        events
            .iter()
            .filter(|event| event.kind == "first_ping_inbound_queued")
            .count(),
        1
    );
    assert_eq!(
        events
            .iter()
            .filter(|event| event.kind == "first_pong_inbound")
            .count(),
        1
    );
}

#[tokio::test]
async fn stalled_connections_do_not_block_recovery_without_network_event() {
    let session = Arc::new(PeerSession::default());
    use iroh::endpoint::presets;
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
        paired(&id, &session),
        Arc::new(Mutex::new(HashMap::new())),
        Arc::new(RwLock::new(None)),
    ));
    let now = Instant::now();
    let peer = Arc::new(PeerProbeState {
        session: session.clone(),
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
    let checking = {
        let manager = manager.clone();
        let id = id.clone();
        tokio::spawn(async move {
            loop {
                let _ = manager.check(&id, false).await;
                tokio::time::sleep(Duration::from_millis(250)).await;
            }
        })
    };
    let stalled_a = tokio::time::timeout(Duration::from_secs(2), receiver.accept())
        .await
        .unwrap()
        .unwrap();
    let stalled_b = tokio::time::timeout(
        CANDIDATE_STAGGER + Duration::from_secs(1),
        receiver.accept(),
    )
    .await
    .unwrap()
    .unwrap();
    let recovered_at = proof_clock::now();
    let third = tokio::time::timeout(Duration::from_millis(3500), receiver.accept())
        .await
        .expect("stalled attempts must not prevent another dial after recovery")
        .unwrap()
        .await
        .unwrap();
    let ping = tokio::time::timeout(Duration::from_secs(1), third.read_datagram())
        .await
        .unwrap()
        .unwrap();
    let info = DeviceInfo {
        name: "Phone".into(),
        device_type: "mobile".into(),
    };
    let mut pong = vec![2];
    pong.extend_from_slice(&ping[1..]);
    pong.extend_from_slice(&serde_json::to_vec(&info).unwrap());
    third.send_datagram(pong.into()).unwrap();
    tokio::time::timeout(Duration::from_secs(1), async {
        loop {
            if peer
                .status
                .borrow()
                .proof
                .as_ref()
                .is_some_and(|(sent, _)| *sent >= recovered_at)
            {
                break;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .expect("the new dial must produce a verified proof");
    drop((stalled_a, stalled_b));
    checking.abort();
    peer.stopped.store(true, Ordering::Relaxed);
    peer.wake.notify_one();
    client.await.unwrap();
    observer.close().await;
    receiver.close().await;
}

#[tokio::test]
async fn initial_stalled_handshake_does_not_block_second_connection() {
    let session = Arc::new(PeerSession::default());
    use iroh::endpoint::presets;
    let receiver = Endpoint::builder(presets::N0DisableRelay)
        .alpns(vec![alpn::PRESENCE.to_vec()])
        .bind()
        .await
        .unwrap();
    let observer = Endpoint::builder(presets::N0DisableRelay)
        .alpns(vec![alpn::PRESENCE.to_vec()])
        .bind()
        .await
        .unwrap();
    let id = receiver.id().to_string();
    let now = Instant::now();
    let peer = Arc::new(PeerProbeState {
        session: session.clone(),
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
    let peers = Arc::new(Mutex::new(HashMap::from([(id.clone(), peer.clone())])));
    let client = tokio::spawn(run_peer_presence(
        observer.clone(),
        receiver.addr(),
        id.clone(),
        peer.clone(),
        peers,
        paired(&id, &session),
        Arc::new(RwLock::new(None)),
    ));
    let stalled = tokio::time::timeout(Duration::from_secs(2), receiver.accept())
        .await
        .unwrap()
        .unwrap();
    tokio::time::timeout(Duration::from_secs(1), async {
        loop {
            let events = crate::diagnostics::events();
            if events.iter().any(|event| {
                event.trace == peer.trace && event.attempt == 1 && event.kind == "dial_setup_done"
            }) {
                assert!(!events.iter().any(|event| event.trace == peer.trace
                    && event.attempt == 1
                    && event.kind == "dial_connected"));
                break;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .expect("the pending handshake must record its completed preparation stage");
    let second = tokio::time::timeout(
        CANDIDATE_STAGGER + Duration::from_secs(1),
        receiver.accept(),
    )
    .await
    .unwrap()
    .unwrap()
    .await
    .unwrap();
    let ping = tokio::time::timeout(Duration::from_secs(2), second.read_datagram())
        .await
        .unwrap()
        .unwrap();
    let info = DeviceInfo {
        name: "Phone".into(),
        device_type: "mobile".into(),
    };
    let mut pong = vec![2];
    pong.extend_from_slice(&ping[1..]);
    pong.extend_from_slice(&serde_json::to_vec(&info).unwrap());
    second.send_datagram(pong.into()).unwrap();
    tokio::time::timeout(Duration::from_secs(2), status.changed())
        .await
        .unwrap()
        .unwrap();
    assert!(
        status.borrow().proof.is_some(),
        "the second connection must establish a verified proof"
    );
    drop(stalled);
    peer.stopped.store(true, Ordering::Relaxed);
    peer.wake.notify_one();
    client.await.unwrap();
    observer.close().await;
    receiver.close().await;
}

#[tokio::test]
async fn grace_period_can_recover_on_second_candidate() {
    let session = Arc::new(PeerSession::default());
    use iroh::endpoint::presets;
    let receiver = Endpoint::builder(presets::N0DisableRelay)
        .alpns(vec![alpn::PRESENCE.to_vec()])
        .bind()
        .await
        .unwrap();
    let observer = Endpoint::builder(presets::N0DisableRelay)
        .alpns(vec![alpn::PRESENCE.to_vec()])
        .bind()
        .await
        .unwrap();
    let id = receiver.id().to_string();
    let now = Instant::now();
    let peer = Arc::new(PeerProbeState {
        session: session.clone(),
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
    let peers = Arc::new(Mutex::new(HashMap::from([(id.clone(), peer.clone())])));
    let client = tokio::spawn(run_peer_presence(
        observer.clone(),
        receiver.addr(),
        id.clone(),
        peer.clone(),
        peers,
        paired(&id, &session),
        Arc::new(RwLock::new(None)),
    ));
    let first = receiver.accept().await.unwrap().await.unwrap();
    let info = DeviceInfo {
        name: "Phone".into(),
        device_type: "mobile".into(),
    };
    let ping = first.read_datagram().await.unwrap();
    let mut pong = vec![2];
    pong.extend_from_slice(&ping[1..]);
    pong.extend_from_slice(&serde_json::to_vec(&info).unwrap());
    first.send_datagram(pong.into()).unwrap();
    tokio::time::timeout(Duration::from_secs(2), status.changed())
        .await
        .unwrap()
        .unwrap();
    let sent = status.borrow().proof.as_ref().unwrap().0;
    ProofTimer::new()
        .wait_until(sent + LEASE + Duration::from_millis(50))
        .await;
    *peer.last_used.lock().unwrap() = Instant::now();
    let stalled = tokio::time::timeout(Duration::from_secs(1), receiver.accept())
        .await
        .unwrap()
        .unwrap();
    let second = tokio::time::timeout(
        CANDIDATE_STAGGER + Duration::from_secs(1),
        receiver.accept(),
    )
    .await
    .unwrap()
    .unwrap()
    .await
    .unwrap();
    assert!(
        first.close_reason().is_none(),
        "old session remains open during grace"
    );
    let ping = second.read_datagram().await.unwrap();
    let mut pong = vec![2];
    pong.extend_from_slice(&ping[1..]);
    pong.extend_from_slice(&serde_json::to_vec(&info).unwrap());
    second.send_datagram(pong.into()).unwrap();
    tokio::time::timeout(Duration::from_secs(2), async {
        loop {
            if status
                .borrow_and_update()
                .proof
                .as_ref()
                .is_some_and(|(new_sent, _)| *new_sent > sent)
            {
                break;
            }
            status.changed().await.unwrap();
        }
    })
    .await
    .expect("second candidate must recover before grace ends");
    drop(stalled);
    peer.stopped.store(true, Ordering::Relaxed);
    peer.wake.notify_one();
    client.await.unwrap();
    observer.close().await;
    receiver.close().await;
}

#[tokio::test]
async fn old_session_recovery_cancels_both_backup_candidates() {
    let session = Arc::new(PeerSession::default());
    use iroh::endpoint::presets;
    let receiver = Endpoint::builder(presets::N0DisableRelay)
        .alpns(vec![alpn::PRESENCE.to_vec()])
        .bind()
        .await
        .unwrap();
    let observer = Endpoint::builder(presets::N0DisableRelay)
        .alpns(vec![alpn::PRESENCE.to_vec()])
        .bind()
        .await
        .unwrap();
    let id = receiver.id().to_string();
    let trusted = paired(&id, &session);
    let manager = PresenceManager::new(
        observer.clone(),
        trusted,
        Arc::new(Mutex::new(HashMap::new())),
        Arc::new(RwLock::new(None)),
    );
    let now = Instant::now();
    let peer = Arc::new(PeerProbeState {
        session: session.clone(),
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
        id,
        peer.clone(),
        manager.probes.clone(),
        manager.trust.clone(),
        manager.info.clone(),
    ));
    let first = receiver.accept().await.unwrap().await.unwrap();
    let info = DeviceInfo {
        name: "Phone".into(),
        device_type: "mobile".into(),
    };
    let reply = |ping: &[u8]| {
        let mut pong = vec![2];
        pong.extend_from_slice(&ping[1..]);
        pong.extend_from_slice(&serde_json::to_vec(&info).unwrap());
        first.send_datagram(pong.into()).unwrap();
    };
    let ping = first.read_datagram().await.unwrap();
    reply(&ping);
    tokio::time::timeout(Duration::from_secs(2), status.changed())
        .await
        .unwrap()
        .unwrap();
    manager.on_network_changed().await;
    let after_wake = peer.min_sent.lock().unwrap().network;
    let candidate_a = tokio::time::timeout(Duration::from_secs(2), receiver.accept())
        .await
        .unwrap()
        .unwrap()
        .await
        .unwrap();
    let candidate_b = tokio::time::timeout(
        CANDIDATE_STAGGER + Duration::from_secs(1),
        receiver.accept(),
    )
    .await
    .unwrap()
    .unwrap()
    .await
    .unwrap();
    tokio::time::timeout(Duration::from_secs(2), async {
            loop {
                tokio::select! {
                    ping = first.read_datagram() => { let ping = ping.unwrap(); if ping.len() == 9 && ping[0] == 1 { reply(&ping); } },
                    changed = status.changed() => { changed.unwrap(); if status.borrow().proof.as_ref().is_some_and(|(sent, _)| *sent >= after_wake) { break; } },
                }
            }
        }).await.expect("old session did not recover");
    tokio::time::timeout(Duration::from_secs(2), candidate_a.closed())
        .await
        .expect("first candidate must be closed");
    tokio::time::timeout(Duration::from_secs(2), candidate_b.closed())
        .await
        .expect("second candidate must be closed");
    assert!(first.close_reason().is_none());
    peer.stopped.store(true, Ordering::Relaxed);
    peer.wake.notify_one();
    client.await.unwrap();
    observer.close().await;
    receiver.close().await;
}

#[test]
fn canceled_backup_records_superseded() {
    let session = Arc::new(PeerSession::default());
    let now = Instant::now();
    let peer = Arc::new(PeerProbeState {
        session: session.clone(),
        trace: NEXT_TRACE.fetch_add(1, Ordering::Relaxed),
        network_epoch: AtomicU64::new(0),
        last_used: StdMutex::new(now),
        min_sent: StdMutex::new(Barriers::new(proof_clock::now())),
        status: watch::channel(Status::default()).0,
        wake: Notify::new(),
        stopped: AtomicBool::new(false),
        monitored: AtomicBool::new(false),
    });
    let guard = CandidateGuard {
        peer: peer.clone(),
        attempt: 7,
        started: now,
        completed: false,
        connection: None,
        handed_off: false,
        diagnostic_generation: Some(crate::diagnostics::state().1),
    };
    drop(guard);
    let events = crate::diagnostics::events();
    assert!(events.iter().any(|event| event.trace == peer.trace
        && event.attempt == 7
        && event.kind == "backup_superseded"));
}

#[test]
fn selected_path_keeps_addresses_without_relay_credentials() {
    use iroh::endpoint::LocalTransportAddr;
    let relay = "https://alice:password@relay.example/?token=secret&mode=fast"
        .parse()
        .unwrap();
    let local = diagnostic_local_addr(&LocalTransportAddr::Relay(relay));
    let relay = "https://alice:password@relay.example/?token=secret&mode=fast"
        .parse()
        .unwrap();
    let remote = diagnostic_remote_addr(&iroh::TransportAddr::Relay(relay));
    for address in [local.unwrap(), remote.unwrap()] {
        assert!(address.contains("relay.example"));
        assert!(address.contains("mode=fast"));
        for secret in ["alice", "password", "secret"] {
            assert!(!address.contains(secret));
        }
    }
    let ip = "203.0.113.7".parse().unwrap();
    let socket = "203.0.113.7:1234".parse().unwrap();
    assert_eq!(
        diagnostic_local_addr(&LocalTransportAddr::Ip(Some(ip))).as_deref(),
        Some("203.0.113.7")
    );
    assert!(diagnostic_remote_addr(&iroh::TransportAddr::Ip(socket))
        .unwrap()
        .contains("203.0.113.7:1234"));
}

#[tokio::test]
async fn rolling_retry_keeps_a_slow_candidate_until_it_succeeds() {
    let (first_tx, first_rx) = tokio::sync::oneshot::channel::<Option<u8>>();
    let started = Arc::new(AtomicU64::new(0));
    let starts = started.clone();
    let first: CandidateFuture<u8> = Box::pin(async move { first_rx.await.ok().flatten() });
    let race = tokio::spawn(race_for_test(first, move |_| {
        starts.fetch_add(1, Ordering::Relaxed);
        Some(Box::pin(std::future::pending()) as CandidateFuture<u8>)
    }));
    tokio::time::sleep(CANDIDATE_STAGGER + CANDIDATE_ROTATE + Duration::from_millis(200)).await;
    assert!(
        started.load(Ordering::Relaxed) >= 2,
        "the rolling candidate must be refreshed"
    );
    first_tx
        .send(Some(1))
        .expect("the slow candidate must remain active");
    assert_eq!(
        tokio::time::timeout(Duration::from_secs(1), race)
            .await
            .unwrap()
            .unwrap(),
        Some(1)
    );
}

#[tokio::test]
async fn late_failed_rolling_candidate_is_replaced_without_extra_backoff() {
    let (started_tx, started_rx) = tokio::sync::oneshot::channel();
    let mut started_tx = Some(started_tx);
    let mut count = 0;
    let first: CandidateFuture<u8> = Box::pin(std::future::pending());
    let race = tokio::spawn(race_for_test(first, move |_| {
        count += 1;
        if count == 1 {
            let _ = started_tx.take().unwrap().send(());
            Some(Box::pin(async {
                tokio::time::sleep(CANDIDATE_ROTATE - Duration::from_millis(300)).await;
                None
            }) as CandidateFuture<u8>)
        } else {
            Some(Box::pin(async { Some(3u8) }) as CandidateFuture<u8>)
        }
    }));
    tokio::time::timeout(CANDIDATE_STAGGER + Duration::from_secs(1), started_rx)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        tokio::time::timeout(CANDIDATE_ROTATE + Duration::from_millis(250), race)
            .await
            .expect("late failure should retry without an extra second")
            .unwrap(),
        Some(3)
    );
}

#[tokio::test]
async fn progressed_rolling_candidate_allows_a_third_without_being_cancelled() {
    let (first_tx, first_rx) = tokio::sync::oneshot::channel::<Option<u8>>();
    let (second_tx, second_rx) = tokio::sync::oneshot::channel::<Option<u8>>();
    let (third_tx, third_rx) = tokio::sync::oneshot::channel();
    let connected = Arc::new(AtomicBool::new(false));
    let progress = Arc::new(Notify::new());
    let progress_signal = progress.clone();
    let mut second_rx = Some(second_rx);
    let mut third_tx = Some(third_tx);
    let first: CandidateFuture<u8> = Box::pin(async move { first_rx.await.ok().flatten() });
    let mut starts = 0;
    let race = tokio::spawn(race_candidates(
        first,
        connected,
        progress,
        move |connected| {
            starts += 1;
            if starts == 1 {
                let rx = second_rx.take().unwrap();
                let progress = progress_signal.clone();
                Some(Box::pin(async move {
                    tokio::time::sleep(CANDIDATE_ROTATE - Duration::from_millis(600)).await;
                    connected.store(true, Ordering::Release);
                    progress.notify_one();
                    rx.await.ok().flatten()
                }) as CandidateFuture<u8>)
            } else {
                let _ = third_tx.take().unwrap().send(());
                Some(Box::pin(std::future::pending()) as CandidateFuture<u8>)
            }
        },
    ));
    tokio::time::timeout(
        CANDIDATE_STAGGER + CANDIDATE_ROTATE + Duration::from_secs(1),
        third_rx,
    )
    .await
    .expect("a connected rolling candidate must not prevent a third attempt")
    .unwrap();
    assert!(
        !first_tx.is_closed(),
        "the candidate retained until timeout must remain alive"
    );
    second_tx
        .send(Some(2))
        .expect("the connected candidate must retain its PONG window");
    assert_eq!(
        tokio::time::timeout(Duration::from_secs(1), race)
            .await
            .unwrap()
            .unwrap(),
        Some(2)
    );
}

#[tokio::test]
async fn progressed_candidates_never_exceed_three_in_flight() {
    let progress = Arc::new(Notify::new());
    let signal = progress.clone();
    let first_connected = Arc::new(AtomicBool::new(true));
    let starts = Arc::new(AtomicU64::new(0));
    let observed = starts.clone();
    let first: CandidateFuture<u8> = Box::pin(std::future::pending());
    let race = tokio::spawn(race_candidates(
        first,
        first_connected,
        progress,
        move |connected| {
            observed.fetch_add(1, Ordering::Relaxed);
            connected.store(true, Ordering::Release);
            signal.notify_one();
            Some(Box::pin(std::future::pending()) as CandidateFuture<u8>)
        },
    ));
    tokio::time::sleep(CANDIDATE_STAGGER + CANDIDATE_RETRY * 2 + Duration::from_millis(250)).await;
    assert_eq!(
        starts.load(Ordering::Relaxed),
        2,
        "the anchor plus two candidates are the concurrency limit"
    );
    race.abort();
}

#[tokio::test]
async fn fast_failures_respect_minimum_time_between_starts() {
    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
    let first: CandidateFuture<u8> = Box::pin(std::future::pending());
    let mut attempts = 0;
    let race = tokio::spawn(race_for_test(first, move |_| {
        attempts += 1;
        tx.send(Instant::now()).unwrap();
        Some(Box::pin(async move {
            if attempts < 3 {
                None
            } else {
                Some(3u8)
            }
        }) as CandidateFuture<u8>)
    }));
    let a = tokio::time::timeout(CANDIDATE_STAGGER + Duration::from_secs(1), rx.recv())
        .await
        .unwrap()
        .unwrap();
    let b = tokio::time::timeout(CANDIDATE_RETRY + Duration::from_secs(1), rx.recv())
        .await
        .unwrap()
        .unwrap();
    let c = tokio::time::timeout(CANDIDATE_RETRY + Duration::from_secs(1), rx.recv())
        .await
        .unwrap()
        .unwrap();
    assert!(b.duration_since(a) >= CANDIDATE_RETRY - Duration::from_millis(20));
    assert!(c.duration_since(b) >= CANDIDATE_RETRY - Duration::from_millis(20));
    assert_eq!(race.await.unwrap(), Some(3));
}

#[tokio::test]
async fn connected_rolling_candidate_gets_full_pong_window() {
    let session = Arc::new(PeerSession::default());
    use iroh::endpoint::presets;
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
        paired(&id, &session),
        Arc::new(Mutex::new(HashMap::new())),
        Arc::new(RwLock::new(None)),
    ));
    let now = Instant::now();
    let peer = Arc::new(PeerProbeState {
        session: session.clone(),
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
    let checking = {
        let manager = manager.clone();
        let id = id.clone();
        tokio::spawn(async move {
            loop {
                let _ = manager.check(&id, false).await;
                tokio::time::sleep(Duration::from_millis(250)).await;
            }
        })
    };
    let stalled = tokio::time::timeout(Duration::from_secs(2), receiver.accept())
        .await
        .unwrap()
        .unwrap();
    let second = tokio::time::timeout(
        CANDIDATE_STAGGER + Duration::from_secs(1),
        receiver.accept(),
    )
    .await
    .unwrap()
    .unwrap();
    tokio::time::sleep(CANDIDATE_ROTATE - Duration::from_millis(600)).await;
    let connected = tokio::time::timeout(Duration::from_secs(1), second)
        .await
        .unwrap()
        .unwrap();
    let ping = tokio::time::timeout(Duration::from_secs(1), connected.read_datagram())
        .await
        .unwrap()
        .unwrap();
    tokio::time::sleep(Duration::from_millis(800)).await;
    let info = DeviceInfo {
        name: "Phone".into(),
        device_type: "mobile".into(),
    };
    let mut pong = vec![2];
    pong.extend_from_slice(&ping[1..]);
    pong.extend_from_slice(&serde_json::to_vec(&info).unwrap());
    connected
        .send_datagram(pong.into())
        .expect("established candidate should remain alive until PONG");
    tokio::time::timeout(Duration::from_secs(1), async {
        loop {
            if peer.status.borrow().proof.is_some() {
                break;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .expect("established candidate should become the verified connection");
    drop(stalled);
    checking.abort();
    peer.stopped.store(true, Ordering::Relaxed);
    peer.wake.notify_one();
    client.await.unwrap();
    observer.close().await;
    receiver.close().await;
}

#[tokio::test]
async fn a_live_rolling_candidate_is_promoted_when_the_retained_candidate_fails() {
    let (first_tx, first_rx) = tokio::sync::oneshot::channel::<Option<u8>>();
    let (second_tx, second_rx) = tokio::sync::oneshot::channel::<Option<u8>>();
    let (started_tx, started_rx) = tokio::sync::oneshot::channel();
    let mut second_rx = Some(second_rx);
    let mut started_tx = Some(started_tx);
    let first: CandidateFuture<u8> = Box::pin(async move { first_rx.await.ok().flatten() });
    let race = tokio::spawn(race_for_test(first, move |_| {
        if let Some(rx) = second_rx.take() {
            let _ = started_tx.take().unwrap().send(());
            Some(Box::pin(async move { rx.await.ok().flatten() }) as CandidateFuture<u8>)
        } else {
            Some(Box::pin(std::future::pending()) as CandidateFuture<u8>)
        }
    }));
    tokio::time::timeout(CANDIDATE_STAGGER + Duration::from_secs(1), started_rx)
        .await
        .unwrap()
        .unwrap();
    first_tx.send(None).unwrap();
    tokio::time::sleep(CANDIDATE_ROTATE + Duration::from_millis(200)).await;
    second_tx
        .send(Some(2))
        .expect("the promoted candidate must not be cancelled by its former rotation deadline");
    assert_eq!(
        tokio::time::timeout(Duration::from_secs(1), race)
            .await
            .unwrap()
            .unwrap(),
        Some(2)
    );
}

#[tokio::test]
async fn stalled_backup_does_not_block_parallel_candidate() {
    let (first_tx, first_rx) = tokio::sync::oneshot::channel::<Option<u8>>();
    let (second_tx, second_rx) = tokio::sync::oneshot::channel::<Option<u8>>();
    let mut second_rx = Some(second_rx);
    let first: CandidateFuture<u8> = Box::pin(async move { first_rx.await.ok().flatten() });
    let race = tokio::spawn(race_for_test(first, move |_| {
        second_rx
            .take()
            .map(|rx| Box::pin(async move { rx.await.ok().flatten() }) as CandidateFuture<u8>)
    }));
    tokio::task::yield_now().await;
    assert!(
        !first_tx.is_closed(),
        "the original dial must remain active"
    );
    second_tx.send(Some(2)).unwrap();
    assert_eq!(
        tokio::time::timeout(CANDIDATE_STAGGER + Duration::from_secs(1), race)
            .await
            .unwrap()
            .unwrap(),
        Some(2)
    );
    assert!(
        first_tx.is_closed(),
        "the losing candidate must be released"
    );
}

#[tokio::test]
async fn failed_parallel_candidate_keeps_original_and_retries() {
    let (first_tx, first_rx) = tokio::sync::oneshot::channel::<Option<u8>>();
    let first: CandidateFuture<u8> = Box::pin(async move { first_rx.await.ok().flatten() });
    let mut started = 0;
    let race = tokio::spawn(race_for_test(first, move |_| {
        started += 1;
        Some(Box::pin(async move {
            if started == 1 {
                None
            } else {
                Some(3u8)
            }
        }) as CandidateFuture<u8>)
    }));
    tokio::time::sleep(Duration::from_millis(50)).await;
    assert!(
        !first_tx.is_closed(),
        "failure of the second dial must not cancel the first"
    );
    assert_eq!(
        tokio::time::timeout(
            CANDIDATE_STAGGER + CANDIDATE_RETRY + Duration::from_secs(1),
            race
        )
        .await
        .unwrap()
        .unwrap(),
        Some(3)
    );
    assert!(first_tx.is_closed());
}

#[tokio::test]
async fn stopped_retry_drops_pending_candidate() {
    let (first_tx, first_rx) = tokio::sync::oneshot::channel::<Option<u8>>();
    let first: CandidateFuture<u8> = Box::pin(async move { first_rx.await.ok().flatten() });
    let mut started = false;
    let race = tokio::spawn(race_for_test(first, move |_| {
        if started {
            return None;
        }
        started = true;
        Some(Box::pin(async { None }) as CandidateFuture<u8>)
    }));
    assert_eq!(
        tokio::time::timeout(
            CANDIDATE_STAGGER + CANDIDATE_RETRY + Duration::from_secs(1),
            race
        )
        .await
        .unwrap()
        .unwrap(),
        None
    );
    assert!(first_tx.is_closed());
}

#[tokio::test]
async fn stopped_peer_cancels_pending_connection() {
    let session = Arc::new(PeerSession::default());
    let peer = Arc::new(PeerProbeState {
        session: session.clone(),
        trace: NEXT_TRACE.fetch_add(1, Ordering::Relaxed),
        network_epoch: AtomicU64::new(0),
        last_used: StdMutex::new(Instant::now()),
        min_sent: StdMutex::new(Barriers::new(proof_clock::now())),
        status: watch::channel(Status::default()).0,
        wake: Notify::new(),
        stopped: AtomicBool::new(false),
        monitored: AtomicBool::new(false),
    });
    peer.stopped.store(true, Ordering::Relaxed);
    let epoch = peer.network_epoch.load(Ordering::Relaxed);
    let result = tokio::time::timeout(
        Duration::from_secs(1),
        wait_for_candidate_dial(std::future::pending::<()>(), &peer, epoch),
    )
    .await;
    assert!(matches!(
        result,
        Ok(Err(crate::diagnostics::DialOutcome::Inactive))
    ));
}

#[tokio::test]
async fn slow_connection_survives_short_status_deadline() {
    let session = Arc::new(PeerSession::default());
    let peer = Arc::new(PeerProbeState {
        session: session.clone(),
        trace: NEXT_TRACE.fetch_add(1, Ordering::Relaxed),
        network_epoch: AtomicU64::new(0),
        last_used: StdMutex::new(Instant::now()),
        min_sent: StdMutex::new(Barriers::new(proof_clock::now())),
        status: watch::channel(Status::default()).0,
        wake: Notify::new(),
        stopped: AtomicBool::new(false),
        monitored: AtomicBool::new(false),
    });
    let epoch = peer.network_epoch.load(Ordering::Relaxed);
    let result = wait_for_candidate_dial(
        async {
            tokio::time::sleep(Duration::from_millis(3100)).await;
            42
        },
        &peer,
        epoch,
    )
    .await;
    assert!(matches!(result, Ok(42)));
}

#[tokio::test]
async fn network_change_cancels_pending_connection_but_refresh_does_not() {
    let session = Arc::new(PeerSession::default());
    use iroh::endpoint::presets;
    let endpoint = Endpoint::builder(presets::N0DisableRelay)
        .bind()
        .await
        .unwrap();
    let manager = PresenceManager::new(
        endpoint.clone(),
        empty_trust(),
        Arc::new(Mutex::new(HashMap::new())),
        Arc::new(RwLock::new(None)),
    );
    let now = Instant::now();
    let peer = Arc::new(PeerProbeState {
        session: session.clone(),
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
        .insert("peer".into(), peer.clone());
    let (send, receive) = tokio::sync::oneshot::channel();
    let pending = {
        let peer = peer.clone();
        tokio::spawn(async move { wait_for_candidate_dial(receive, &peer, 0).await })
    };
    peer.wake.notify_one();
    tokio::time::sleep(Duration::from_millis(30)).await;
    assert!(
        !pending.is_finished(),
        "refresh must not cancel an ongoing handshake"
    );
    manager.on_network_changed().await;
    assert!(matches!(
        tokio::time::timeout(Duration::from_secs(1), pending)
            .await
            .unwrap()
            .unwrap(),
        Err(crate::diagnostics::DialOutcome::NetworkChanged)
    ));
    assert!(
        send.send(()).is_err(),
        "the old connection future must be dropped"
    );
    endpoint.close().await;
}

#[tokio::test]
async fn pending_backup_dial_coalesces_repeated_network_changes() {
    let session = Arc::new(PeerSession::default());
    use iroh::endpoint::presets;
    let endpoint = Endpoint::builder(presets::N0DisableRelay)
        .bind()
        .await
        .unwrap();
    let manager = PresenceManager::new(
        endpoint.clone(),
        empty_trust(),
        Arc::new(Mutex::new(HashMap::new())),
        Arc::new(RwLock::new(None)),
    );
    let now = Instant::now();
    let peer = Arc::new(PeerProbeState {
        session: session.clone(),
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
        .insert("peer".into(), peer.clone());
    let (sender, receiver) = tokio::sync::oneshot::channel::<()>();
    let waiting = {
        let peer = peer.clone();
        tokio::spawn(async move { wait_for_candidate_dial(receiver, &peer, 0).await })
    };
    for _ in 0..3 {
        manager.on_network_changed().await;
        tokio::time::sleep(Duration::from_millis(100)).await;
        assert!(
            !waiting.is_finished(),
            "a burst of network events must not repeatedly cancel the dial"
        );
    }
    let result = tokio::time::timeout(Duration::from_secs(2), waiting)
        .await
        .unwrap()
        .unwrap();
    assert!(matches!(
        result,
        Err(crate::diagnostics::DialOutcome::NetworkChanged)
    ));
    assert!(sender.send(()).is_err());
    endpoint.close().await;
}

#[tokio::test]
async fn network_changes_do_not_extend_old_proof_deadline() {
    let session = Arc::new(PeerSession::default());
    use iroh::endpoint::presets;
    let endpoint = Endpoint::builder(presets::N0DisableRelay)
        .bind()
        .await
        .unwrap();
    let remote = Endpoint::builder(presets::N0DisableRelay)
        .bind()
        .await
        .unwrap();
    let id = remote.id().to_string();
    let manager = PresenceManager::new(
        endpoint.clone(),
        paired(&id, &session),
        Arc::new(Mutex::new(HashMap::new())),
        Arc::new(RwLock::new(None)),
    );
    let now = Instant::now();
    let sent = proof_clock::now() - LEASE + Duration::from_millis(150);
    let info = DeviceInfo {
        name: "Phone".into(),
        device_type: "mobile".into(),
    };
    let peer = Arc::new(PeerProbeState {
        session: session.clone(),
        trace: NEXT_TRACE.fetch_add(1, Ordering::Relaxed),
        network_epoch: AtomicU64::new(0),
        last_used: StdMutex::new(now),
        min_sent: StdMutex::new(Barriers::new(sent)),
        status: watch::channel(Status {
            proof: Some((sent, info.clone())),
            unpaired: None,
            latest: Some(sent),
        })
        .0,
        wake: Notify::new(),
        stopped: AtomicBool::new(false),
        monitored: AtomicBool::new(false),
    });
    manager.probes.lock().await.insert(id.clone(), peer.clone());

    manager.on_network_changed().await;
    manager.on_network_changed().await;
    assert_eq!(
        peer.status.borrow().proof.as_ref().map(|(at, _)| *at),
        Some(sent),
        "network changes must preserve the old deadline"
    );
    let json = serde_json::to_vec(&info).unwrap();
    assert!(
        publish_response(&peer, sent, &json),
        "a still-valid pre-change reply may preserve its original proof"
    );
    assert_eq!(
        peer.status.borrow().proof.as_ref().map(|(at, _)| *at),
        Some(sent),
        "a reply cannot extend the send-time deadline"
    );
    ProofTimer::new()
        .wait_until(sent + LEASE + Duration::from_millis(20))
        .await;
    let result = tokio::time::timeout(Duration::from_millis(200), manager.check(&id, false))
        .await
        .expect("expired proof must not wait for a new lease");
    assert!(result.is_err());

    let new_sent = proof_clock::now();
    assert!(
        publish_response(&peer, new_sent, &json),
        "post-change replies can establish a new proof"
    );
    assert!(manager.check(&id, false).await.is_ok());
    endpoint.close().await;
    remote.close().await;
}

#[tokio::test]
async fn background_check_returns_without_waiting_for_the_first_proof() {
    let session = Arc::new(PeerSession::default());
    use iroh::endpoint::presets;
    let endpoint = Endpoint::builder(presets::Minimal).bind().await.unwrap();
    let remote = Endpoint::builder(presets::Minimal).bind().await.unwrap();
    let id = remote.id().to_string();
    let manager = Arc::new(PresenceManager::new(
        endpoint.clone(),
        paired(&id, &session),
        Arc::new(Mutex::new(HashMap::new())),
        Arc::new(RwLock::new(None)),
    ));
    let now = Instant::now();
    let peer = Arc::new(PeerProbeState {
        session: session.clone(),
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
    let first = tokio::time::timeout(Duration::from_millis(200), manager.check(&id, false)).await;
    assert!(
        matches!(first, Ok(Err(_))),
        "a background check must immediately report absence of proof"
    );
    peer.status.send_replace(Status::default());
    let previous =
        tokio::time::timeout(Duration::from_millis(200), manager.check(&id, false)).await;
    assert!(
        matches!(previous, Ok(Err(_))),
        "a previously seen peer without proof is also unavailable"
    );
    peer.status.send_replace(Status::default());
    let check = {
        let manager = manager.clone();
        let id = id.clone();
        tokio::spawn(async move { manager.check(&id, true).await })
    };
    tokio::time::sleep(Duration::from_millis(50)).await;
    assert!(
        !check.is_finished(),
        "a fresh check must wait for a new response"
    );
    let info = DeviceInfo {
        name: "Phone".into(),
        device_type: "mobile".into(),
    };
    assert!(publish_response(
        &peer,
        proof_clock::now(),
        &serde_json::to_vec(&info).unwrap()
    ));
    assert!(tokio::time::timeout(Duration::from_secs(1), check)
        .await
        .unwrap()
        .unwrap()
        .is_ok());
    endpoint.close().await;
    remote.close().await;
}

#[tokio::test]
async fn manual_refresh_respects_existing_proof_deadline() {
    let session = Arc::new(PeerSession::default());
    use iroh::endpoint::presets;
    let endpoint = Endpoint::builder(presets::N0DisableRelay)
        .bind()
        .await
        .unwrap();
    let remote = Endpoint::builder(presets::N0DisableRelay)
        .bind()
        .await
        .unwrap();
    let id = remote.id().to_string();
    let manager = PresenceManager::new(
        endpoint.clone(),
        paired(&id, &session),
        Arc::new(Mutex::new(HashMap::new())),
        Arc::new(RwLock::new(None)),
    );
    let now = Instant::now();
    let sent = proof_clock::now() - LEASE + Duration::from_millis(150);
    let info = DeviceInfo {
        name: "Phone".into(),
        device_type: "mobile".into(),
    };
    let peer = Arc::new(PeerProbeState {
        session: session.clone(),
        trace: NEXT_TRACE.fetch_add(1, Ordering::Relaxed),
        network_epoch: AtomicU64::new(0),
        last_used: StdMutex::new(now),
        min_sent: StdMutex::new(Barriers::new(sent)),
        status: watch::channel(Status {
            proof: Some((sent, info)),
            unpaired: None,
            latest: Some(sent),
        })
        .0,
        wake: Notify::new(),
        stopped: AtomicBool::new(false),
        monitored: AtomicBool::new(false),
    });
    manager.probes.lock().await.insert(id.clone(), peer);
    let result = tokio::time::timeout(Duration::from_millis(500), manager.check(&id, true)).await;
    endpoint.close().await;
    remote.close().await;
    assert!(
        matches!(result, Ok(Err(_))),
        "manual refresh must finish when the existing proof expires"
    );
}

#[tokio::test]
async fn manual_refresh_tracks_newer_proof_without_extending_it() {
    let session = Arc::new(PeerSession::default());
    use iroh::endpoint::presets;
    let endpoint = Endpoint::builder(presets::N0DisableRelay)
        .bind()
        .await
        .unwrap();
    let remote = Endpoint::builder(presets::N0DisableRelay)
        .bind()
        .await
        .unwrap();
    let id = remote.id().to_string();
    let manager = Arc::new(PresenceManager::new(
        endpoint.clone(),
        paired(&id, &session),
        Arc::new(Mutex::new(HashMap::new())),
        Arc::new(RwLock::new(None)),
    ));
    let now = Instant::now();
    let old = proof_clock::now() - LEASE + Duration::from_millis(150);
    let newer = proof_clock::now() - LEASE + Duration::from_millis(800);
    let info = DeviceInfo {
        name: "Phone".into(),
        device_type: "mobile".into(),
    };
    let json = serde_json::to_vec(&info).unwrap();
    let peer = Arc::new(PeerProbeState {
        session: session.clone(),
        trace: NEXT_TRACE.fetch_add(1, Ordering::Relaxed),
        network_epoch: AtomicU64::new(0),
        last_used: StdMutex::new(now),
        min_sent: StdMutex::new(Barriers::new(old)),
        status: watch::channel(Status {
            proof: Some((old, info)),
            unpaired: None,
            latest: Some(old),
        })
        .0,
        wake: Notify::new(),
        stopped: AtomicBool::new(false),
        monitored: AtomicBool::new(false),
    });
    manager.probes.lock().await.insert(id.clone(), peer.clone());
    let check = {
        let manager = manager.clone();
        tokio::spawn(async move { manager.check(&id, true).await })
    };
    tokio::time::sleep(Duration::from_millis(50)).await;
    assert!(publish_response(&peer, newer, &json));
    tokio::time::sleep(Duration::from_millis(150)).await;
    assert!(
        !check.is_finished(),
        "a newer valid proof must update the original deadline"
    );
    assert!(publish_response(&peer, proof_clock::now(), &json));
    assert!(tokio::time::timeout(Duration::from_secs(1), check)
        .await
        .unwrap()
        .unwrap()
        .is_ok());
    endpoint.close().await;
    remote.close().await;
}

#[tokio::test]
async fn manual_refresh_can_recover_a_previously_expired_proof() {
    let session = Arc::new(PeerSession::default());
    use iroh::endpoint::presets;
    let endpoint = Endpoint::builder(presets::N0DisableRelay)
        .bind()
        .await
        .unwrap();
    let remote = Endpoint::builder(presets::N0DisableRelay)
        .bind()
        .await
        .unwrap();
    let id = remote.id().to_string();
    let manager = Arc::new(PresenceManager::new(
        endpoint.clone(),
        paired(&id, &session),
        Arc::new(Mutex::new(HashMap::new())),
        Arc::new(RwLock::new(None)),
    ));
    let now = Instant::now();
    let old = proof_clock::now() - LEASE - Duration::from_millis(100);
    let info = DeviceInfo {
        name: "Phone".into(),
        device_type: "mobile".into(),
    };
    let json = serde_json::to_vec(&info).unwrap();
    let peer = Arc::new(PeerProbeState {
        session: session.clone(),
        trace: NEXT_TRACE.fetch_add(1, Ordering::Relaxed),
        network_epoch: AtomicU64::new(0),
        last_used: StdMutex::new(now),
        min_sent: StdMutex::new(Barriers::new(old)),
        status: watch::channel(Status {
            proof: Some((old, info)),
            unpaired: None,
            latest: Some(old),
        })
        .0,
        wake: Notify::new(),
        stopped: AtomicBool::new(false),
        monitored: AtomicBool::new(false),
    });
    manager.probes.lock().await.insert(id.clone(), peer.clone());
    let check = {
        let manager = manager.clone();
        tokio::spawn(async move { manager.check(&id, true).await })
    };
    tokio::time::sleep(Duration::from_millis(100)).await;
    assert!(publish_response(&peer, proof_clock::now(), &json));
    let result = tokio::time::timeout(Duration::from_secs(1), check)
        .await
        .unwrap()
        .unwrap();
    endpoint.close().await;
    remote.close().await;
    assert!(
        result.is_ok(),
        "refreshing an already offline peer must allow a fresh reply"
    );
}

#[tokio::test]
async fn network_change_starts_backup_before_old_session_expires() {
    let session = Arc::new(PeerSession::default());
    use iroh::endpoint::presets;
    let receiver = Endpoint::builder(presets::N0DisableRelay)
        .alpns(vec![alpn::PRESENCE.to_vec()])
        .bind()
        .await
        .unwrap();
    let observer = Endpoint::builder(presets::N0DisableRelay)
        .alpns(vec![alpn::PRESENCE.to_vec()])
        .bind()
        .await
        .unwrap();
    let address = receiver.addr();
    let id = receiver.id().to_string();
    let server = {
        let receiver = receiver.clone();
        tokio::spawn(async move {
            let first = receiver.accept().await.unwrap().await.unwrap();
            let ping = first.read_datagram().await.unwrap();
            let info = DeviceInfo {
                name: "Phone".into(),
                device_type: "mobile".into(),
            };
            let json = serde_json::to_vec(&info).unwrap();
            let mut pong = vec![2];
            pong.extend_from_slice(&ping[1..]);
            pong.extend_from_slice(&json);
            first.send_datagram(pong.into()).unwrap();
            let second = receiver.accept().await.unwrap().await.unwrap();
            let ping = second.read_datagram().await.unwrap();
            let mut pong = vec![2];
            pong.extend_from_slice(&ping[1..]);
            pong.extend_from_slice(&json);
            second.send_datagram(pong.into()).unwrap();
            (first, second)
        })
    };
    let manager = PresenceManager::new(
        observer.clone(),
        paired(&id, &session),
        Arc::new(Mutex::new(HashMap::new())),
        Arc::new(RwLock::new(None)),
    );
    let now = Instant::now();
    let peer = Arc::new(PeerProbeState {
        session: session.clone(),
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
        address,
        id,
        peer.clone(),
        manager.probes.clone(),
        manager.trust.clone(),
        manager.info.clone(),
    ));
    tokio::time::timeout(Duration::from_secs(3), status.changed())
        .await
        .unwrap()
        .unwrap();
    let original = status.borrow().proof.as_ref().unwrap().0;
    manager.on_network_changed().await;
    let new_proof = tokio::time::timeout(Duration::from_millis(1200), async {
        loop {
            if status
                .borrow_and_update()
                .proof
                .as_ref()
                .is_some_and(|(sent, _)| *sent > original)
            {
                break;
            }
            status.changed().await.unwrap();
        }
    })
    .await;
    let replaced = tokio::time::timeout(Duration::from_secs(1), async {
        loop {
            if crate::diagnostics::events()
                .iter()
                .any(|event| event.trace == peer.trace && event.kind == "session_replaced")
            {
                break;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await;
    tokio::time::sleep(INTERVAL + Duration::from_millis(50)).await;
    let events = crate::diagnostics::events();
    let backup_attempt = events
        .iter()
        .find(|event| event.trace == peer.trace && event.kind == "session_replaced")
        .and_then(|replaced| {
            events.iter().find(|event| {
                event.trace == peer.trace
                    && event.kind == "first_pong"
                    && event.attempt != replaced.attempt
            })
        })
        .map(|event| event.attempt);
    let backup_ping_count = events
        .iter()
        .filter(|event| {
            event.trace == peer.trace
                && Some(event.attempt) == backup_attempt
                && (event.kind == "first_ping_queued" || event.kind == "first_ping_failed")
        })
        .count();
    peer.stopped.store(true, Ordering::Relaxed);
    peer.wake.notify_one();
    client.await.unwrap();
    server.abort();
    observer.close().await;
    receiver.close().await;
    assert!(
        new_proof.is_ok(),
        "network change should establish a backup proof before the old session expires"
    );
    assert!(replaced.is_ok(), "handoff should be visible in diagnostics");
    assert!(backup_attempt.is_some());
    assert_eq!(
        backup_ping_count, 1,
        "handoff must not duplicate the backup's first-ping event"
    );
}

#[tokio::test]
async fn connection_close_does_not_discard_unexpired_proof() {
    let session = Arc::new(PeerSession::default());
    use iroh::endpoint::presets;
    let receiver = Endpoint::builder(presets::N0DisableRelay)
        .alpns(vec![alpn::PRESENCE.to_vec()])
        .bind()
        .await
        .unwrap();
    let observer = Endpoint::builder(presets::N0DisableRelay)
        .alpns(vec![alpn::PRESENCE.to_vec()])
        .bind()
        .await
        .unwrap();
    let id = receiver.id().to_string();
    let address = receiver.addr();
    let server = tokio::spawn(async move {
        let conn = receiver.accept().await.unwrap().await.unwrap();
        let ping = conn.read_datagram().await.unwrap();
        let info = DeviceInfo {
            name: "Phone".into(),
            device_type: "mobile".into(),
        };
        let mut pong = vec![2];
        pong.extend_from_slice(&ping[1..]);
        pong.extend_from_slice(&serde_json::to_vec(&info).unwrap());
        conn.send_datagram(pong.into()).unwrap();
        tokio::time::sleep(Duration::from_millis(100)).await;
        conn.close(0u32.into(), b"test connection loss");
        receiver.close().await;
    });
    let now = Instant::now();
    let peer = Arc::new(PeerProbeState {
        session: session.clone(),
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
    let peers = Arc::new(Mutex::new(HashMap::from([(id.clone(), peer.clone())])));
    let client = tokio::spawn(run_peer_presence(
        observer.clone(),
        address,
        id.clone(),
        peer.clone(),
        peers,
        paired(&id, &session),
        Arc::new(RwLock::new(None)),
    ));
    tokio::time::timeout(Duration::from_secs(3), status.changed())
        .await
        .unwrap()
        .unwrap();
    let sent = status.borrow().proof.as_ref().unwrap().0;
    server.await.unwrap();
    tokio::time::sleep(Duration::from_millis(100)).await;
    assert!(proof_clock::now() < sent + LEASE);
    assert_eq!(
        status.borrow().proof.as_ref().map(|(at, _)| *at),
        Some(sent),
        "connection loss must not erase the still-valid proof"
    );
    peer.stopped.store(true, Ordering::Relaxed);
    peer.wake.notify_one();
    client.await.unwrap();
    observer.close().await;
}

#[tokio::test]
async fn check_replaces_expired_peer_before_old_runner_removes_it() {
    let session = Arc::new(PeerSession::default());
    use iroh::endpoint::presets;
    let endpoint = Endpoint::builder(presets::N0DisableRelay)
        .bind()
        .await
        .unwrap();
    let remote = Endpoint::builder(presets::N0DisableRelay)
        .bind()
        .await
        .unwrap();
    let id = remote.id().to_string();
    let info = Arc::new(RwLock::new(None));
    let trusted = paired(&id, &session);
    let manager = Arc::new(PresenceManager::new(
        endpoint.clone(),
        trusted.clone(),
        Arc::new(Mutex::new(HashMap::new())),
        info.clone(),
    ));
    let expired = Instant::now() - INACTIVE - Duration::from_secs(1);
    let old = Arc::new(PeerProbeState {
        session: session.clone(),
        trace: NEXT_TRACE.fetch_add(1, Ordering::Relaxed),
        network_epoch: AtomicU64::new(0),
        last_used: StdMutex::new(expired),
        min_sent: StdMutex::new(Barriers::new(
            proof_clock::now() - INACTIVE - Duration::from_secs(1),
        )),
        status: watch::channel(Status::default()).0,
        wake: Notify::new(),
        stopped: AtomicBool::new(false),
        monitored: AtomicBool::new(false),
    });
    let mut peers = manager.probes.lock().await;
    peers.insert(id.clone(), old.clone());
    let check = {
        let manager = manager.clone();
        let id = id.clone();
        tokio::spawn(async move { manager.check(&id, false).await })
    };
    tokio::time::sleep(Duration::from_millis(30)).await;
    let runner = tokio::spawn(run_peer_presence(
        endpoint.clone(),
        remote.addr(),
        id.clone(),
        old.clone(),
        manager.probes.clone(),
        trusted,
        info,
    ));
    tokio::time::sleep(Duration::from_millis(30)).await;
    drop(peers);
    runner.await.unwrap();
    let current = manager
        .probes
        .lock()
        .await
        .get(&id)
        .cloned()
        .expect("new check owns a peer");
    assert!(!Arc::ptr_eq(&old, &current));
    assert!(old.stopped.load(Ordering::Relaxed));
    assert!(!current.stopped.load(Ordering::Relaxed));
    current.stopped.store(true, Ordering::Relaxed);
    current.wake.notify_one();
    check.abort();
    endpoint.close().await;
    remote.close().await;
}

#[tokio::test]
async fn runner_does_not_remove_peer_reactivated_before_cleanup() {
    let session = Arc::new(PeerSession::default());
    use iroh::endpoint::presets;
    let endpoint = Endpoint::builder(presets::N0DisableRelay)
        .bind()
        .await
        .unwrap();
    let remote = Endpoint::builder(presets::N0DisableRelay)
        .alpns(vec![alpn::PRESENCE.to_vec()])
        .bind()
        .await
        .unwrap();
    let id = remote.id().to_string();
    let expired = Instant::now() - INACTIVE - Duration::from_secs(1);
    let peer = Arc::new(PeerProbeState {
        session: session.clone(),
        trace: NEXT_TRACE.fetch_add(1, Ordering::Relaxed),
        network_epoch: AtomicU64::new(0),
        last_used: StdMutex::new(expired),
        min_sent: StdMutex::new(Barriers::new(
            proof_clock::now() - INACTIVE - Duration::from_secs(1),
        )),
        status: watch::channel(Status::default()).0,
        wake: Notify::new(),
        stopped: AtomicBool::new(false),
        monitored: AtomicBool::new(false),
    });
    let peers = Arc::new(Mutex::new(HashMap::from([(id.clone(), peer.clone())])));
    let locked = peers.lock().await;
    let runner = tokio::spawn(run_peer_presence(
        endpoint.clone(),
        remote.addr(),
        id.clone(),
        peer.clone(),
        peers.clone(),
        paired(&id, &session),
        Arc::new(RwLock::new(None)),
    ));
    tokio::time::sleep(Duration::from_millis(30)).await;
    *peer.last_used.lock().unwrap() = Instant::now();
    drop(locked);
    let conn = tokio::time::timeout(Duration::from_secs(3), async {
        remote.accept().await.unwrap().await.unwrap()
    })
    .await
    .expect("reactivated peer must reconnect");
    assert!(peers
        .lock()
        .await
        .get(&id)
        .is_some_and(|current| Arc::ptr_eq(current, &peer)));
    assert!(!peer.stopped.load(Ordering::Relaxed));
    peer.stopped.store(true, Ordering::Relaxed);
    peer.wake.notify_one();
    conn.close(0u32.into(), b"test complete");
    runner.await.unwrap();
    endpoint.close().await;
    remote.close().await;
}

#[tokio::test]
async fn real_session_expires_when_peer_stops_answering() {
    let session = Arc::new(PeerSession::default());
    use iroh::endpoint::presets;
    let receiver = Endpoint::builder(presets::N0DisableRelay)
        .alpns(vec![alpn::PRESENCE.to_vec()])
        .bind()
        .await
        .unwrap();
    let observer = Endpoint::builder(presets::N0DisableRelay)
        .alpns(vec![alpn::PRESENCE.to_vec()])
        .bind()
        .await
        .unwrap();
    let address = receiver.addr();
    let id = receiver.id().to_string();
    let server = tokio::spawn(async move {
        let conn = receiver.accept().await.unwrap().await.unwrap();
        let ping = conn.read_datagram().await.unwrap();
        let info = DeviceInfo {
            name: "Phone".into(),
            device_type: "mobile".into(),
        };
        let mut pong = vec![2];
        pong.extend_from_slice(&ping[1..]);
        pong.extend_from_slice(&serde_json::to_vec(&info).unwrap());
        conn.send_datagram(pong.into()).unwrap();
        tokio::time::sleep(Duration::from_secs(4)).await;
        receiver.close().await;
    });
    let peer = Arc::new(PeerProbeState {
        session: session.clone(),
        trace: NEXT_TRACE.fetch_add(1, Ordering::Relaxed),
        network_epoch: AtomicU64::new(0),
        last_used: StdMutex::new(Instant::now()),
        min_sent: StdMutex::new(Barriers::new(proof_clock::now())),
        status: watch::channel(Status::default()).0,
        wake: Notify::new(),
        stopped: AtomicBool::new(false),
        monitored: AtomicBool::new(false),
    });
    let peers = Arc::new(Mutex::new(HashMap::from([(id.clone(), peer.clone())])));
    let trusted = paired(&id, &session);
    let mut status = peer.status.subscribe();
    let client = tokio::spawn(run_peer_presence(
        observer.clone(),
        address,
        id,
        peer.clone(),
        peers,
        trusted,
        Arc::new(RwLock::new(None)),
    ));
    tokio::time::timeout(Duration::from_secs(8), status.changed())
        .await
        .unwrap()
        .unwrap();
    let (sent, info) = status
        .borrow()
        .proof
        .clone()
        .expect("authenticated response");
    assert_eq!(info.name, "Phone");
    ProofTimer::new()
        .wait_until(sent + LEASE + Duration::from_millis(30))
        .await;
    let current = status.borrow().clone();
    assert!(current
        .proof
        .is_none_or(|(at, _)| proof_clock::now() >= at + LEASE));
    peer.stopped.store(true, Ordering::Relaxed);
    peer.wake.notify_one();
    client.await.unwrap();
    server.await.unwrap();
    observer.close().await;
}

#[tokio::test]
async fn expired_session_reconnects_and_gets_new_proof() {
    let session = Arc::new(PeerSession::default());
    use iroh::endpoint::presets;
    let receiver = Endpoint::builder(presets::N0DisableRelay)
        .alpns(vec![alpn::PRESENCE.to_vec()])
        .bind()
        .await
        .unwrap();
    let observer = Endpoint::builder(presets::N0DisableRelay)
        .alpns(vec![alpn::PRESENCE.to_vec()])
        .bind()
        .await
        .unwrap();
    let address = receiver.addr();
    let id = receiver.id().to_string();
    let server = tokio::spawn(async move {
        for _ in 0..2 {
            let conn = receiver.accept().await.unwrap().await.unwrap();
            let ping = conn.read_datagram().await.unwrap();
            let info = DeviceInfo {
                name: "Phone".into(),
                device_type: "mobile".into(),
            };
            let mut pong = vec![2];
            pong.extend_from_slice(&ping[1..]);
            pong.extend_from_slice(&serde_json::to_vec(&info).unwrap());
            conn.send_datagram(pong.into()).unwrap();
            let _ = conn.closed().await;
        }
        receiver.close().await;
    });
    let peer = Arc::new(PeerProbeState {
        session: session.clone(),
        trace: NEXT_TRACE.fetch_add(1, Ordering::Relaxed),
        network_epoch: AtomicU64::new(0),
        last_used: StdMutex::new(Instant::now()),
        min_sent: StdMutex::new(Barriers::new(proof_clock::now())),
        status: watch::channel(Status::default()).0,
        wake: Notify::new(),
        stopped: AtomicBool::new(false),
        monitored: AtomicBool::new(false),
    });
    let peers = Arc::new(Mutex::new(HashMap::from([(id.clone(), peer.clone())])));
    let trusted = paired(&id, &session);
    let mut status = peer.status.subscribe();
    let client = tokio::spawn(run_peer_presence(
        observer.clone(),
        address,
        id,
        peer.clone(),
        peers,
        trusted,
        Arc::new(RwLock::new(None)),
    ));
    tokio::time::timeout(Duration::from_secs(8), status.changed())
        .await
        .unwrap()
        .unwrap();
    let first = status.borrow().proof.as_ref().expect("first proof").0;
    let deadline = tokio::time::Instant::now() + Duration::from_secs(8);
    loop {
        *peer.last_used.lock().unwrap() = Instant::now();
        if status
            .borrow()
            .proof
            .as_ref()
            .is_some_and(|(sent, _)| *sent > first)
        {
            break;
        }
        assert!(
            tokio::time::Instant::now() < deadline,
            "presence did not reconnect"
        );
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    peer.stopped.store(true, Ordering::Relaxed);
    peer.wake.notify_one();
    client.await.unwrap();
    server.await.unwrap();
    observer.close().await;
    let events: Vec<_> = crate::diagnostics::events()
        .into_iter()
        .filter(|event| event.trace == peer.trace)
        .collect();
    assert!(
        events
            .iter()
            .filter(|event| event.kind == "dial_start")
            .count()
            >= 2
    );
    assert!(
        events
            .iter()
            .filter(|event| event.kind == "first_pong")
            .count()
            >= 2,
        "each reconnected session must record its own first response"
    );
    assert!(events.iter().any(|event| event.kind == "session_expired"));
}

#[tokio::test]
async fn consecutive_fast_dial_failures_are_all_recorded() {
    let session = Arc::new(PeerSession::default());
    use iroh::endpoint::presets;
    let endpoint = Endpoint::builder(presets::N0DisableRelay)
        .bind()
        .await
        .unwrap();
    let id = endpoint.id().to_string();
    let now = Instant::now();
    let peer = Arc::new(PeerProbeState {
        session: session.clone(),
        trace: NEXT_TRACE.fetch_add(1, Ordering::Relaxed),
        network_epoch: AtomicU64::new(0),
        last_used: StdMutex::new(now),
        min_sent: StdMutex::new(Barriers::new(proof_clock::now())),
        status: watch::channel(Status::default()).0,
        wake: Notify::new(),
        stopped: AtomicBool::new(false),
        monitored: AtomicBool::new(false),
    });
    let trusted = paired(&id, &session);
    let info = Arc::new(RwLock::new(None));
    for attempt in 1..=3 {
        assert!(connect_candidate(
            endpoint.clone(),
            endpoint.addr(),
            id.clone(),
            peer.clone(),
            trusted.clone(),
            info.clone(),
            attempt,
            0,
            Arc::new(AtomicBool::new(false)),
            Arc::new(Notify::new())
        )
        .await
        .is_none());
    }
    let events: Vec<_> = crate::diagnostics::events()
        .into_iter()
        .filter(|event| event.trace == peer.trace && event.kind == "dial_failed")
        .collect();
    endpoint.close().await;
    assert_eq!(events.len(), 3, "each failed dial must be recorded");
    for (index, event) in events.iter().enumerate() {
        assert_eq!(event.attempt, (index + 1) as u64);
        let details: serde_json::Value = serde_json::from_str(&event.details).unwrap();
        assert!(
            details["error"]
                .as_str()
                .is_some_and(|message| message.contains("Connecting to ourself")),
            "each failure should retain its actual reason"
        );
    }
}

#[test]
fn delayed_response_does_not_extend_expiry() {
    let start = proof_clock::now();
    let current = accept_response(None, start, start + Duration::from_secs(2));
    assert_eq!(current, Some(start));
    assert_eq!(
        accept_response(current, start, start + Duration::from_secs(3)),
        current
    );
    let newer = start + Duration::from_secs(1);
    assert_eq!(
        accept_response(Some(newer), start, start + Duration::from_secs(2)),
        Some(newer)
    );
}

#[test]
fn backup_proof_must_still_be_current_at_handoff() {
    let sent = proof_clock::now();
    assert!(candidate_is_current(
        sent,
        sent,
        sent + LEASE - Duration::from_millis(1)
    ));
    assert!(!candidate_is_current(sent, sent, sent + LEASE));
    assert!(!candidate_is_current(
        sent,
        sent + Duration::from_millis(1),
        sent + Duration::from_millis(1)
    ));
}

#[test]
fn valid_response_updates_proof_while_diagnostics_are_disabled() {
    const CHILD: &str = "VELA_DISABLED_PRESENCE_STATS_TEST_CHILD";
    if std::env::var_os(CHILD).is_none() {
        let result = std::process::Command::new(std::env::current_exe().unwrap())
            .args([
                "--exact",
                "presence::tests::valid_response_updates_proof_while_diagnostics_are_disabled",
            ])
            .env(CHILD, "1")
            .output()
            .unwrap();
        assert!(
            result.status.success(),
            "isolated presence test failed: {}{}",
            String::from_utf8_lossy(&result.stdout),
            String::from_utf8_lossy(&result.stderr)
        );
        return;
    }
    crate::diagnostics::set_enabled(false);
    let sent = proof_clock::now();
    let peer = PeerProbeState {
        session: Arc::new(PeerSession::default()),
        trace: NEXT_TRACE.fetch_add(1, Ordering::Relaxed),
        network_epoch: AtomicU64::new(0),
        last_used: StdMutex::new(Instant::now()),
        min_sent: StdMutex::new(Barriers::new(sent)),
        status: watch::channel(Status::default()).0,
        wake: Notify::new(),
        stopped: AtomicBool::new(false),
        monitored: AtomicBool::new(false),
    };
    let info = DeviceInfo {
        name: "Phone".into(),
        device_type: "mobile".into(),
    };
    let pong = [vec![2; 9], serde_json::to_vec(&info).unwrap()].concat();
    let mut stats = ProbeStats::new(peer.trace, 1, "test");
    let result = peer.accept_response(sent, &pong);
    stats.record_response(&result);
    assert_eq!(result, Ok(()));
    let published = peer.status.borrow().proof.clone().unwrap();
    assert_eq!(published.0, sent);
    assert_eq!(published.1.name, "Phone");
    assert_eq!(stats.pong_valid, 0);
}

#[test]
fn healthy_probe_summaries_are_rate_limited() {
    let mut stats = ProbeStats::new(1, 1, "test");
    let previous = Instant::now() - Duration::from_secs(59);
    stats.last_report = previous;
    stats.tick(tokio::time::Instant::now() - Duration::from_millis(30));
    assert_eq!(stats.last_report, previous);
    assert!(stats.max_tick_lag_ms >= 30);
    stats.last_report = Instant::now() - Duration::from_secs(61);
    stats.tick(tokio::time::Instant::now());
    assert!(stats.last_report.elapsed() < Duration::from_secs(1));
}

#[test]
fn probe_stats_reset_across_recording_generations() {
    let mut stats = ProbeStats::new(1, 1, "test");
    assert!(stats.recording_for(true, 100));
    stats.ping_attempts = 3;
    stats.pong_valid = 2;
    stats.max_rtt_ms = 700;
    assert!(!stats.recording_for(false, 101));
    assert_eq!(
        (stats.ping_attempts, stats.pong_valid, stats.max_rtt_ms),
        (0, 0, 0)
    );
    if stats.recording_for(false, 101) {
        stats.ping_attempts += 1;
    }
    assert!(stats.recording_for(true, 102));
    assert_eq!(
        (stats.ping_attempts, stats.pong_valid, stats.max_rtt_ms),
        (0, 0, 0)
    );
}

#[test]
fn first_probe_is_recorded_once_per_enabled_window_across_handoff() {
    let mut candidate = ProbeStats::new(7, 3, "backup");
    assert!(candidate.probe_for(true, true, 10));
    let mut active = candidate;
    active.role = "active";
    assert!(
        !active.probe_for(false, true, 10),
        "handoff must not duplicate the first probe"
    );
    assert_eq!((active.ping_attempts, active.ping_queued), (2, 1));
    assert!(!active.probe_for(false, false, 11));
    assert_eq!((active.ping_attempts, active.ping_queued), (0, 0));
    assert!(
        active.probe_for(true, true, 12),
        "the new diagnostics window needs its own first probe"
    );
    assert_eq!((active.ping_attempts, active.ping_queued), (1, 1));
}
