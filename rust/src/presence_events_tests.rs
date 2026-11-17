use super::*;
use crate::api::node::{PeerPresenceSnapshot, PresenceSnapshot};
use crate::trust::{PeerSession, TrustState};
use iroh::{address_lookup::memory::MemoryLookup, endpoint::presets};
use std::sync::atomic::{AtomicBool, Ordering};
use tokio::sync::Notify;

struct Fixture {
    receiver: Endpoint,
    observer: Endpoint,
    manager: Arc<PresenceManager>,
    id: String,
    responding: Arc<AtomicBool>,
    withheld: Arc<StdMutex<Option<(Connection, Vec<u8>, Instant)>>>,
    withheld_notify: Arc<Notify>,
    server: tokio::task::JoinHandle<()>,
}

fn reply(conn: &Connection, ping: &[u8]) {
    let info = DeviceInfo {
        name: "Phone".into(),
        device_type: "mobile".into(),
    };
    let mut pong = vec![2];
    pong.extend_from_slice(&ping[1..]);
    pong.extend_from_slice(&serde_json::to_vec(&info).unwrap());
    let _ = conn.send_datagram(pong.into());
}

impl Fixture {
    async fn new() -> Self {
        let receiver = Endpoint::builder(presets::Minimal)
            .alpns(vec![alpn::PRESENCE.to_vec()])
            .bind()
            .await
            .unwrap();
        let lookup = MemoryLookup::new();
        lookup.add_endpoint_info(receiver.addr());
        let observer = Endpoint::builder(presets::Minimal)
            .address_lookup(lookup)
            .alpns(vec![alpn::PRESENCE.to_vec()])
            .bind()
            .await
            .unwrap();
        let id = receiver.id().to_string();
        let mut state = TrustState {
            initialized: true,
            ..Default::default()
        };
        state
            .sessions
            .insert(id.clone(), Arc::new(PeerSession::default()));
        let trust = Arc::new(RwLock::new(state));
        let manager = Arc::new(PresenceManager::new(
            observer.clone(),
            trust,
            Arc::new(Mutex::new(HashMap::new())),
            Arc::new(RwLock::new(None)),
        ));
        let responding = Arc::new(AtomicBool::new(true));
        let withheld = Arc::new(StdMutex::new(None));
        let withheld_notify = Arc::new(Notify::new());
        let server = {
            let receiver = receiver.clone();
            let responding = responding.clone();
            let withheld = withheld.clone();
            let notify = withheld_notify.clone();
            tokio::spawn(async move {
                while let Some(incoming) = receiver.accept().await {
                    let responding = responding.clone();
                    let withheld = withheld.clone();
                    let notify = notify.clone();
                    tokio::spawn(async move {
                        let Ok(conn) = incoming.await else { return };
                        while let Ok(ping) = conn.read_datagram().await {
                            if ping.len() != 9 || ping[0] != 1 {
                                continue;
                            }
                            if responding.load(Ordering::Acquire) {
                                reply(&conn, &ping);
                            } else {
                                let mut slot = withheld.lock().unwrap();
                                if slot.is_none() {
                                    *slot = Some((conn.clone(), ping.to_vec(), Instant::now()));
                                    notify.notify_one();
                                }
                            }
                        }
                    });
                }
            })
        };
        Self {
            receiver,
            observer,
            manager,
            id,
            responding,
            withheld,
            withheld_notify,
            server,
        }
    }

    async fn stop(self) {
        let _ = self.manager.set_monitoring(false).await;
        self.observer.close().await;
        self.receiver.close().await;
        self.server.abort();
    }
}

fn item<'a>(snapshot: &'a PresenceSnapshot, id: &str) -> &'a PeerPresenceSnapshot {
    snapshot
        .peers
        .iter()
        .find(|peer| peer.peer_id == id)
        .expect("monitored peer missing from snapshot")
}

async fn current(manager: &PresenceManager) -> PresenceSnapshot {
    tokio::time::timeout(Duration::from_secs(3), manager.wait_snapshot(0))
        .await
        .expect("snapshot timed out")
        .expect("snapshot failed")
}

async fn wait_online(
    manager: &PresenceManager,
    id: &str,
    mut revision: u64,
    online: bool,
) -> PresenceSnapshot {
    tokio::time::timeout(Duration::from_secs(6), async {
        loop {
            let snapshot = manager
                .wait_snapshot(revision)
                .await
                .expect("snapshot failed");
            revision = snapshot.revision;
            if item(&snapshot, id).info.is_some() == online {
                return snapshot;
            }
        }
    })
    .await
    .expect("expected status transition did not arrive")
}

#[tokio::test]
async fn monitored_peer_events_survive_without_polling_and_follow_proof_deadline() {
    let f = Fixture::new().await;
    f.manager.set_monitoring(true).await.unwrap();
    let initial = current(&f.manager).await;
    assert!(!item(&initial, &f.id).unpaired);
    let online = if item(&initial, &f.id).info.is_some() {
        initial
    } else {
        wait_online(&f.manager, &f.id, initial.revision, true).await
    };
    assert!(
        item(&online, &f.id).proof_valid_until_ns.is_some(),
        "online snapshot needs a proof deadline"
    );

    // No PresenceManager.check calls: heartbeats keep the subscription alive without emitting duplicate states.
    assert!(
        tokio::time::timeout(
            INACTIVE + Duration::from_millis(750),
            f.manager.wait_snapshot(online.revision)
        )
        .await
        .is_err(),
        "continuous proof renewals must not emit a spurious status transition"
    );
    let held = current(&f.manager).await;
    assert!(
        item(&held, &f.id).info.is_some(),
        "monitoring stopped without polling"
    );

    f.responding.store(false, Ordering::Release);
    tokio::time::timeout(Duration::from_secs(2), async {
        loop {
            let notified = f.withheld_notify.notified();
            if f.withheld.lock().unwrap().is_some() {
                break;
            }
            notified.await;
        }
    })
    .await
    .expect("no PING was withheld");
    let (conn, stale_ping, captured_at) = f.withheld.lock().unwrap().clone().unwrap();
    let peer = f
        .manager
        .probes
        .lock()
        .await
        .get(&f.id)
        .cloned()
        .expect("peer still monitored");
    let last_sent = peer
        .status
        .borrow()
        .proof
        .as_ref()
        .map(|(sent, _)| *sent)
        .expect("last accepted proof missing");
    let offline = wait_online(&f.manager, &f.id, held.revision, false).await;
    let notified_at = proof_clock::now();
    assert!(
        notified_at >= last_sent + LEASE,
        "offline must not precede the last proof deadline"
    );
    assert!(
        notified_at <= last_sent + LEASE + Duration::from_millis(500),
        "offline event must follow the proof deadline promptly"
    );
    tokio::time::sleep_until((captured_at + LEASE + Duration::from_millis(50)).into()).await;
    reply(&conn, &stale_ping);
    assert!(
        tokio::time::timeout(
            Duration::from_millis(400),
            f.manager.wait_snapshot(offline.revision)
        )
        .await
        .is_err(),
        "expired PONG must not emit a new state"
    );
    assert!(
        item(&current(&f.manager).await, &f.id).info.is_none(),
        "expired PONG must not restore online status"
    );

    f.responding.store(true, Ordering::Release);
    let recovered = wait_online(&f.manager, &f.id, offline.revision, true).await;
    assert!(item(&recovered, &f.id).proof_valid_until_ns.is_some());
    f.manager.set_monitoring(false).await.unwrap();
    let disabled = current(&f.manager).await;
    assert!(
        disabled.peers.is_empty(),
        "disabled monitoring must not publish stale state"
    );
    tokio::time::timeout(Duration::from_secs(2), async {
        while !f.manager.probes.lock().await.is_empty() {
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .expect("stopped monitoring must release peer tasks");
    f.stop().await;
}

#[tokio::test]
async fn closing_endpoint_wakes_waiting_snapshot_consumer() {
    let f = Fixture::new().await;
    let snapshot = current(&f.manager).await;
    let mut waiter = {
        let manager = f.manager.clone();
        tokio::spawn(async move { manager.wait_snapshot(snapshot.revision).await })
    };
    assert!(
        tokio::time::timeout(Duration::from_millis(150), &mut waiter)
            .await
            .is_err(),
        "unchanged snapshot should wait"
    );
    f.observer.close().await;
    let result = tokio::time::timeout(Duration::from_secs(2), waiter)
        .await
        .expect("closing endpoint must wake snapshot waiter")
        .unwrap();
    assert!(
        result.is_err(),
        "closed endpoint must not produce a live snapshot"
    );
    f.receiver.close().await;
    f.server.abort();
}

#[tokio::test]
async fn slow_snapshot_consumer_gets_latest_state_not_queued_old_offline() {
    let f = Fixture::new().await;
    f.manager.set_monitoring(true).await.unwrap();
    let initial = current(&f.manager).await;
    let online = if item(&initial, &f.id).info.is_some() {
        initial
    } else {
        wait_online(&f.manager, &f.id, initial.revision, true).await
    };
    let peer = f
        .manager
        .probes
        .lock()
        .await
        .get(&f.id)
        .cloned()
        .expect("peer is monitored");

    // Consumer intentionally stops reading while proof expires and later returns.
    f.responding.store(false, Ordering::Release);
    tokio::time::sleep(LEASE + INTERVAL + Duration::from_millis(200)).await;
    let old_proof = peer.status.borrow().proof.as_ref().map(|(sent, _)| *sent);
    assert!(
        old_proof.is_none_or(|sent| sent.elapsed() >= LEASE),
        "proof must have expired before recovery"
    );
    f.responding.store(true, Ordering::Release);
    tokio::time::timeout(Duration::from_secs(4), async {
        loop {
            let is_new = peer
                .status
                .borrow()
                .proof
                .as_ref()
                .is_some_and(|(sent, _)| {
                    old_proof.is_none_or(|old| *sent > old) && sent.elapsed() < LEASE
                });
            if is_new {
                break;
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    })
    .await
    .expect("new responding PONG did not restore proof");
    let latest = tokio::time::timeout(
        Duration::from_secs(2),
        f.manager.wait_snapshot(online.revision),
    )
    .await
    .expect("consumer must be notified of the latest state")
    .unwrap();
    assert!(latest.revision > online.revision);
    assert!(
        item(&latest, &f.id).info.is_some(),
        "consumer must get current online, not stale queued offline"
    );
    f.stop().await;
}

#[tokio::test]
async fn direct_snapshots_advance_revision_when_deadline_watcher_is_delayed() {
    let f = Fixture::new().await;
    f.manager.set_monitoring(true).await.unwrap();
    let initial = current(&f.manager).await;
    let online = if item(&initial, &f.id).info.is_some() {
        initial
    } else {
        wait_online(&f.manager, &f.id, initial.revision, true).await
    };
    let peer = f
        .manager
        .probes
        .lock()
        .await
        .get(&f.id)
        .cloned()
        .expect("peer is monitored");
    // Model a delayed timer watcher while snapshots still read the authoritative proof.
    f.manager
        .snapshot_watchers
        .lock()
        .await
        .get(&f.id)
        .expect("monitor is registered")
        .task
        .abort();
    f.responding.store(false, Ordering::Release);
    let expired_proof = tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let sent = peer.status.borrow().proof.as_ref().map(|(sent, _)| *sent);
            if sent.is_none_or(|sent| sent.elapsed() >= LEASE) {
                break sent;
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    })
    .await
    .expect("proof did not expire");
    let offline = current(&f.manager).await;
    assert!(
        item(&offline, &f.id).info.is_none(),
        "direct snapshot must revalidate expired proof"
    );
    assert!(
        offline.revision > online.revision,
        "directly observed offline must advance revision"
    );

    f.responding.store(true, Ordering::Release);
    tokio::time::timeout(Duration::from_secs(4), async {
        loop {
            let fresh = peer
                .status
                .borrow()
                .proof
                .as_ref()
                .is_some_and(|(sent, _)| {
                    expired_proof.is_none_or(|old| *sent > old)
                        && proof_clock::is_fresh(*sent, proof_clock::now(), LEASE)
                });
            if fresh {
                break;
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    })
    .await
    .expect("new proof was not received");
    let recovered = current(&f.manager).await;
    assert!(
        item(&recovered, &f.id).info.is_some(),
        "direct snapshot must include recovered proof"
    );
    assert!(
        recovered.revision > offline.revision,
        "recovered online snapshot must be newer than offline"
    );
    f.stop().await;
}

#[tokio::test]
async fn only_matching_unpaired_response_changes_snapshot() {
    let f = Fixture::new().await;
    f.responding.store(false, Ordering::Release);
    f.manager.set_monitoring(true).await.unwrap();
    let initial = current(&f.manager).await;

    async fn next_withheld(f: &Fixture) -> (Connection, Vec<u8>) {
        tokio::time::timeout(Duration::from_secs(3), async {
            loop {
                let notified = f.withheld_notify.notified();
                if let Some((conn, ping, _)) = f.withheld.lock().unwrap().take() {
                    return (conn, ping);
                }
                notified.await;
            }
        })
        .await
        .expect("missing presence query")
    }

    let (conn, ping) = next_withheld(&f).await;
    let mut invalid = vec![4];
    invalid.extend_from_slice(&[0u8; 8]);
    if invalid[1..] == ping[1..] {
        invalid[1] ^= 1;
    }
    conn.send_datagram(invalid.into()).unwrap();
    let mut pending = vec![3];
    pending.extend_from_slice(&ping[1..]);
    conn.send_datagram(pending.into()).unwrap();
    tokio::time::sleep(Duration::from_millis(150)).await;
    assert!(
        !item(&current(&f.manager).await, &f.id).unpaired,
        "an unmatched response or pairing-in-progress must not delete the peer"
    );

    let (conn, ping) = next_withheld(&f).await;
    let mut unpaired = vec![4];
    unpaired.extend_from_slice(&ping[1..]);
    conn.send_datagram(unpaired.into()).unwrap();
    tokio::time::timeout(Duration::from_secs(3), async {
        let mut revision = initial.revision;
        loop {
            let snapshot = f.manager.wait_snapshot(revision).await.unwrap();
            if item(&snapshot, &f.id).unpaired {
                break;
            }
            revision = snapshot.revision;
        }
    })
    .await
    .expect("authenticated matching unpaired response must publish a snapshot");
    assert!(
        f.manager.revoke_if_unpaired(&f.id).await,
        "authenticated rejection must remove the current session"
    );
    assert!(!f.manager.trust.read().await.sessions.contains_key(&f.id));
    assert!(!f.manager.snapshot_watchers.lock().await.contains_key(&f.id));
    assert!(
        !f.manager.revoke_if_unpaired(&f.id).await,
        "consuming the same rejection twice must be harmless"
    );
    f.stop().await;
}

#[tokio::test]
async fn presence_queries_hide_device_info_until_explicitly_trusted() {
    let receiver = Endpoint::builder(presets::Minimal)
        .alpns(vec![alpn::PRESENCE.to_vec()])
        .bind()
        .await
        .unwrap();
    let sender = Endpoint::builder(presets::Minimal).bind().await.unwrap();
    let sender_id = sender.id().to_string();
    let trust = Arc::new(RwLock::new(TrustState::default()));
    let info = Arc::new(RwLock::new(Some(DeviceInfo {
        name: "Private name".into(),
        device_type: "desktop".into(),
    })));
    let manager = Arc::new(PresenceManager::new(
        receiver.clone(),
        trust.clone(),
        Arc::new(Mutex::new(HashMap::new())),
        info.clone(),
    ));

    async fn query(
        sender: &Endpoint,
        receiver: &Endpoint,
        manager: &Arc<PresenceManager>,
        info: &Arc<RwLock<Option<DeviceInfo>>>,
        sender_id: &str,
    ) -> Vec<u8> {
        let (outgoing, incoming) = tokio::time::timeout(Duration::from_secs(5), async {
            tokio::join!(sender.connect(receiver.addr(), alpn::PRESENCE), async {
                receiver.accept().await.unwrap().await.unwrap()
            },)
        })
        .await
        .expect("presence connection timed out");
        let outgoing = outgoing.unwrap();
        let registered = {
            let state = manager.trust.read().await;
            state
                .sessions
                .get(sender_id)
                .filter(|session| {
                    state.is_current(sender_id, session) && session.register(&incoming)
                })
                .cloned()
        };
        let manager = manager.clone();
        let info = info.clone();
        let id = sender_id.to_owned();
        let responder =
            tokio::spawn(async move { manager.respond(&incoming, &id, &info, registered).await });
        let mut ping = vec![1];
        ping.extend_from_slice(&[8u8; 8]);
        outgoing.send_datagram(ping.into()).unwrap();
        let response = tokio::time::timeout(Duration::from_secs(3), outgoing.read_datagram())
            .await
            .unwrap()
            .unwrap()
            .to_vec();
        outgoing.close(0u32.into(), b"done");
        responder.abort();
        response
    }

    let pending = query(&sender, &receiver, &manager, &info, &sender_id).await;
    assert_eq!(
        pending,
        [vec![3], vec![8; 8]].concat(),
        "uninitialized trust is pending"
    );
    trust.write().await.initialized = true;
    let unpaired = query(&sender, &receiver, &manager, &info, &sender_id).await;
    assert_eq!(
        unpaired,
        [vec![4], vec![8; 8]].concat(),
        "unpaired response must not disclose metadata"
    );
    trust.write().await.pairing.insert(sender_id.clone());
    let pending = query(&sender, &receiver, &manager, &info, &sender_id).await;
    assert_eq!(
        pending,
        [vec![3], vec![8; 8]].concat(),
        "an in-progress pairing is pending"
    );
    {
        let mut state = trust.write().await;
        state.pairing.remove(&sender_id);
        state
            .sessions
            .insert(sender_id.clone(), Arc::new(PeerSession::default()));
    }
    let paired = query(&sender, &receiver, &manager, &info, &sender_id).await;
    assert_eq!(paired.first(), Some(&2));
    assert_eq!(&paired[1..9], &[8u8; 8]);
    let data: DeviceInfo = serde_json::from_slice(&paired[9..]).unwrap();
    assert_eq!(data.name, "Private name");
    sender.close().await;
    receiver.close().await;
}

#[tokio::test]
async fn stale_unpaired_cannot_remove_pending_or_replaced_session() {
    let f = Fixture::new().await;
    f.responding.store(false, Ordering::Release);
    f.manager.set_monitoring(true).await.unwrap();
    let peer = f.manager.probes.lock().await.get(&f.id).cloned().unwrap();
    let sent = proof_clock::now();
    peer.status.send_replace(Status {
        proof: None,
        unpaired: Some(sent),
        latest: Some(sent),
    });

    f.manager.trust.write().await.pairing.insert(f.id.clone());
    assert!(
        !f.manager.revoke_if_unpaired(&f.id).await,
        "a pending pairing must not be removed"
    );
    {
        let mut trust = f.manager.trust.write().await;
        trust.pairing.remove(&f.id);
        trust.initialized = false;
    }
    assert!(
        !f.manager.revoke_if_unpaired(&f.id).await,
        "uninitialized trust must not be removed"
    );
    {
        let mut trust = f.manager.trust.write().await;
        trust.initialized = true;
        let replacement = Arc::new(PeerSession::default());
        trust.sessions.insert(f.id.clone(), replacement);
        peer.session.revoke();
    }
    assert!(
        !f.manager.revoke_if_unpaired(&f.id).await,
        "an old session must not remove a new pairing"
    );
    assert!(f.manager.trust.read().await.sessions.contains_key(&f.id));
    f.stop().await;
}

#[test]
fn old_or_equal_unpaired_proof_cannot_override_a_paired_proof() {
    let now = proof_clock::now();
    let earlier = now - Duration::from_millis(10);
    let peer = PeerProbeState {
        session: Arc::new(PeerSession::default()),
        trace: 1,
        network_epoch: AtomicU64::new(0),
        last_used: StdMutex::new(Instant::now()),
        min_sent: StdMutex::new(Barriers::new(now - Duration::from_secs(1))),
        status: watch::channel(Status::default()).0,
        wake: Notify::new(),
        stopped: AtomicBool::new(false),
        monitored: AtomicBool::new(false),
    };
    let info = DeviceInfo {
        name: "Peer".into(),
        device_type: "desktop".into(),
    };
    let paired = [vec![2; 9], serde_json::to_vec(&info).unwrap()].concat();
    let unpaired = vec![4; 9];
    assert_eq!(peer.accept_response(now, &paired), Ok(()));
    assert!(peer.accept_response(earlier, &unpaired).is_err());
    assert!(peer.accept_response(now, &unpaired).is_err());
    assert!(peer.status.borrow().proof.is_some());
    assert!(peer.status.borrow().unpaired.is_none());

    let other = PeerProbeState {
        session: Arc::new(PeerSession::default()),
        trace: 2,
        network_epoch: AtomicU64::new(0),
        last_used: StdMutex::new(Instant::now()),
        min_sent: StdMutex::new(Barriers::new(now)),
        status: watch::channel(Status::default()).0,
        wake: Notify::new(),
        stopped: AtomicBool::new(false),
        monitored: AtomicBool::new(false),
    };
    assert_eq!(
        other.accept_response(earlier, &unpaired),
        Err(PongRejection::EpochFresh)
    );
    assert!(other.status.borrow().unpaired.is_none());
}
