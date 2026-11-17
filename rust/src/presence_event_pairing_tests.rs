use super::*;
use crate::api::node::PresenceSnapshot;
use crate::trust::{PeerSession, TrustState};
use iroh::{address_lookup::memory::MemoryLookup, endpoint::presets};

async fn snapshot_until(
    manager: &PresenceManager,
    predicate: impl Fn(&PresenceSnapshot) -> bool,
) -> PresenceSnapshot {
    tokio::time::timeout(Duration::from_secs(6), async {
        let mut revision = 0;
        loop {
            let snapshot = manager
                .wait_snapshot(revision)
                .await
                .expect("snapshot stream closed");
            if predicate(&snapshot) {
                return snapshot;
            }
            revision = snapshot.revision;
        }
    })
    .await
    .expect("snapshot did not reach the expected pairing state")
}

async fn connection(receiver: &Endpoint) -> Connection {
    tokio::time::timeout(Duration::from_secs(6), async {
        loop {
            let incoming = receiver.accept().await.expect("receiver closed");
            if let Ok(connection) = incoming.await {
                return connection;
            }
        }
    })
    .await
    .expect("expected a fresh presence connection")
}

async fn ping(conn: &Connection) -> Vec<u8> {
    tokio::time::timeout(Duration::from_secs(3), async {
        loop {
            let data = conn
                .read_datagram()
                .await
                .expect("presence connection closed");
            if data.len() == 9 && data[0] == 1 {
                return data.to_vec();
            }
        }
    })
    .await
    .expect("presence connection sent no ping")
}

fn pong(conn: &Connection, ping: &[u8], name: &str) {
    let info = DeviceInfo {
        name: name.into(),
        device_type: "mobile".into(),
    };
    let mut packet = vec![2];
    packet.extend_from_slice(&ping[1..]);
    packet.extend_from_slice(&serde_json::to_vec(&info).unwrap());
    // A revoked session can be closed before the late datagram is queued.
    let _ = conn.send_datagram(packet.into());
}

#[tokio::test]
async fn repairing_an_existing_endpoint_never_reuses_its_old_presence_proof() {
    for remove_first in [false, true] {
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
            trust.clone(),
            Arc::new(Mutex::new(HashMap::new())),
            Arc::new(RwLock::new(None)),
        ));
        manager.set_monitoring(true).await.unwrap();
        let old = connection(&receiver).await;
        pong(&old, &ping(&old).await, "Old device");
        snapshot_until(&manager, |snapshot| {
            snapshot.peers.iter().any(|peer| {
                peer.peer_id == id
                    && peer
                        .info
                        .as_ref()
                        .is_some_and(|info| info.name == "Old device")
            })
        })
        .await;
        let late_ping = ping(&old).await;

        // Also register an already-established incoming session, as Node does.
        let remote_incoming = {
            let receiver = receiver.clone();
            let address = observer.addr();
            tokio::spawn(async move { receiver.connect(address, alpn::PRESENCE).await.unwrap() })
        };
        let incoming = connection(&observer).await;
        let remote_incoming = remote_incoming.await.unwrap();
        let registered = {
            let state = trust.read().await;
            let session = state.sessions.get(&id).unwrap().clone();
            assert!(session.register(&incoming));
            Some(session)
        };
        let responding = {
            let manager = manager.clone();
            let id = id.clone();
            tokio::spawn(async move {
                let info = RwLock::new(None);
                manager.respond(&incoming, &id, &info, registered).await;
            })
        };
        let late_incoming_ping = ping(&remote_incoming).await;

        {
            let mut state = trust.write().await;
            if let Some(old) = state.sessions.remove(&id) {
                old.revoke();
            }
        }
        if remove_first {
            manager.reconcile_trusted_peers().await;
            snapshot_until(&manager, |snapshot| {
                !snapshot.peers.iter().any(|peer| peer.peer_id == id)
            })
            .await;
        }
        trust
            .write()
            .await
            .sessions
            .insert(id.clone(), Arc::new(PeerSession::default()));
        manager.reconcile_trusted_peers().await;
        snapshot_until(&manager, |snapshot| {
            snapshot
                .peers
                .iter()
                .any(|peer| peer.peer_id == id && peer.info.is_none())
        })
        .await;

        pong(&old, &late_ping, "Stale device");
        let mut stale_unpaired = vec![4];
        stale_unpaired.extend_from_slice(&late_ping[1..]);
        let _ = old.send_datagram(stale_unpaired.into());
        pong(
            &remote_incoming,
            &late_incoming_ping,
            "Stale incoming device",
        );
        tokio::time::sleep(Duration::from_millis(350)).await;
        let current = manager.wait_snapshot(0).await.unwrap();
        assert!(
            current.peers.iter().any(|peer| peer.peer_id == id
                && peer.info.is_none() && !peer.unpaired),
            "old PONG or unpaired response must not affect the replacement pairing (remove_first={remove_first})"
        );
        tokio::time::timeout(Duration::from_secs(3), old.closed())
            .await
            .expect("the old outgoing connection must close on pairing change");
        tokio::time::timeout(Duration::from_secs(3), remote_incoming.closed())
            .await
            .expect("the old registered incoming connection must close on pairing change");
        tokio::time::timeout(Duration::from_secs(3), responding)
            .await
            .unwrap()
            .unwrap();

        // Old in-flight handshakes may already be queued; accept all of them
        // until a candidate owned by the new pairing has proved reachability.
        let responder = {
            let receiver = receiver.clone();
            tokio::spawn(async move {
                let mut sessions = tokio::task::JoinSet::new();
                while let Some(incoming) = receiver.accept().await {
                    sessions.spawn(async move {
                        let Ok(conn) = incoming.await else { return };
                        while let Ok(data) = conn.read_datagram().await {
                            if data.len() == 9 && data[0] == 1 {
                                pong(&conn, &data, "New device");
                            }
                        }
                    });
                }
            })
        };
        snapshot_until(&manager, |snapshot| {
            snapshot.peers.iter().any(|peer| {
                peer.peer_id == id
                    && peer
                        .info
                        .as_ref()
                        .is_some_and(|info| info.name == "New device")
            })
        })
        .await;
        manager.set_monitoring(false).await.unwrap();
        responder.abort();
        observer.close().await;
        receiver.close().await;
    }
}

#[tokio::test]
async fn registered_old_connection_cannot_adopt_replacement_session() {
    let receiver = Endpoint::builder(presets::Minimal)
        .alpns(vec![alpn::PRESENCE.to_vec()])
        .bind()
        .await
        .unwrap();
    let sender = Endpoint::builder(presets::Minimal).bind().await.unwrap();
    let id = sender.id().to_string();
    let old = Arc::new(PeerSession::default());
    let mut state = TrustState {
        initialized: true,
        ..Default::default()
    };
    state.sessions.insert(id.clone(), old.clone());
    let trust = Arc::new(RwLock::new(state));
    let info = Arc::new(RwLock::new(Some(DeviceInfo {
        name: "New device".into(),
        device_type: "desktop".into(),
    })));
    let manager = Arc::new(PresenceManager::new(
        receiver.clone(),
        trust.clone(),
        Arc::new(Mutex::new(HashMap::new())),
        info.clone(),
    ));
    let (outgoing, incoming) = tokio::time::timeout(Duration::from_secs(5), async {
        tokio::join!(
            sender.connect(receiver.addr(), alpn::PRESENCE),
            connection(&receiver)
        )
    })
    .await
    .expect("presence connection timed out");
    let outgoing = outgoing.unwrap();
    assert!(old.register(&incoming));
    let mut probe = vec![1];
    probe.extend_from_slice(&[7; 8]);
    outgoing.send_datagram(probe.into()).unwrap();

    let replacement = Arc::new(PeerSession::default());
    {
        let mut state = trust.write().await;
        old.revoke();
        state.sessions.insert(id.clone(), replacement.clone());
    }
    let responder =
        tokio::spawn(async move { manager.respond(&incoming, &id, &info, Some(old)).await });
    let answer = tokio::time::timeout(Duration::from_secs(2), outgoing.read_datagram()).await;
    assert!(
        !matches!(answer, Ok(Ok(_))),
        "old connection must not receive new pairing data"
    );
    assert!(Arc::ptr_eq(
        trust
            .read()
            .await
            .sessions
            .get(&sender.id().to_string())
            .unwrap(),
        &replacement
    ));
    assert!(!replacement.is_revoked());
    tokio::time::timeout(Duration::from_secs(2), responder)
        .await
        .unwrap()
        .unwrap();
    sender.close().await;
    receiver.close().await;
}
