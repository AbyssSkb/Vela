use std::{
    collections::{HashMap, HashSet},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
};

use iroh::endpoint::{Connection, WeakConnectionHandle};
use tokio::sync::RwLock;

pub(crate) type SharedTrust = Arc<RwLock<TrustState>>;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum TrustStatus {
    Pending,
    Paired,
    Unpaired,
}

#[derive(Default)]
pub(crate) struct TrustState {
    pub(crate) initialized: bool,
    pub(crate) sessions: HashMap<String, Arc<PeerSession>>,
    pub(crate) pairing: HashSet<String>,
    pub(crate) incoming_pairings: HashMap<String, usize>,
    pub(crate) outgoing_pairings: HashMap<String, std::sync::Weak<OutgoingAttempt>>,
}

impl TrustState {
    pub(crate) fn replace_trusted_peers(&mut self, desired: HashSet<String>) {
        self.initialized = true;
        self.sessions.retain(|id, session| {
            if desired.contains(id) {
                true
            } else {
                session.revoke();
                false
            }
        });
        for id in desired {
            self.sessions
                .entry(id)
                .or_insert_with(|| Arc::new(PeerSession::default()));
        }
    }

    fn is_pairing(&self, peer: &str) -> bool {
        self.pairing.contains(peer) || self.incoming_pairings.get(peer).copied().unwrap_or(0) > 0
    }

    fn invalidate_session_for_pairing(&mut self, peer: &str) {
        if !self.is_pairing(peer) {
            if let Some(session) = self.sessions.get_mut(peer) {
                session.revoke();
                *session = Arc::new(PeerSession::default());
            }
        }
    }

    pub(crate) fn begin_pairing(&mut self, peer: String) {
        self.invalidate_session_for_pairing(&peer);
        self.pairing.insert(peer);
    }

    pub(crate) fn end_pairing(&mut self, peer: &str) {
        self.pairing.remove(peer);
        if let Some(attempt) = self
            .outgoing_pairings
            .get(peer)
            .and_then(|weak| weak.upgrade())
        {
            attempt.cancel();
        }
    }

    pub(crate) fn begin_outgoing_pairing(
        &mut self,
        peer: String,
    ) -> anyhow::Result<Arc<OutgoingAttempt>> {
        if !self.pairing.contains(&peer) {
            anyhow::bail!("pairing is not active")
        }
        if self
            .outgoing_pairings
            .get(&peer)
            .and_then(|weak| weak.upgrade())
            .is_some_and(|attempt| !attempt.finished.load(Ordering::Acquire))
        {
            anyhow::bail!("pairing already active")
        }
        let attempt = Arc::new(OutgoingAttempt::default());
        self.outgoing_pairings
            .insert(peer, Arc::downgrade(&attempt));
        Ok(attempt)
    }

    fn begin_incoming_pairing(&mut self, peer: String) {
        self.invalidate_session_for_pairing(&peer);
        *self.incoming_pairings.entry(peer).or_default() += 1;
    }

    fn end_incoming_pairing(&mut self, peer: &str) {
        if let Some(count) = self.incoming_pairings.get_mut(peer) {
            *count -= 1;
            if *count == 0 {
                self.incoming_pairings.remove(peer);
            }
        }
    }

    pub(crate) fn status(&self, peer: &str) -> TrustStatus {
        if !self.initialized || self.is_pairing(peer) {
            TrustStatus::Pending
        } else if self.sessions.contains_key(peer) {
            TrustStatus::Paired
        } else {
            TrustStatus::Unpaired
        }
    }

    pub(crate) fn is_current(&self, peer: &str, session: &Arc<PeerSession>) -> bool {
        self.status(peer) == TrustStatus::Paired
            && !session.is_revoked()
            && self
                .sessions
                .get(peer)
                .is_some_and(|current| Arc::ptr_eq(current, session))
    }
}

#[derive(Default)]
pub(crate) struct PeerSession {
    revoked: AtomicBool,
    connections: Mutex<Vec<WeakConnectionHandle>>,
}

impl PeerSession {
    pub(crate) fn is_revoked(&self) -> bool {
        self.revoked.load(Ordering::Acquire)
    }

    pub(crate) fn register(&self, conn: &Connection) -> bool {
        let mut connections = self.connections.lock().unwrap();
        if self.is_revoked() {
            conn.close(0u32.into(), b"pairing changed");
            return false;
        }
        connections.retain(|weak| {
            weak.upgrade()
                .is_some_and(|connection| connection.close_reason().is_none())
        });
        if !connections.iter().any(|weak| {
            weak.upgrade()
                .is_some_and(|connection| connection.stable_id() == conn.stable_id())
        }) {
            connections.push(conn.weak_handle());
        }
        true
    }

    pub(crate) fn revoke(&self) {
        let mut connections = self.connections.lock().unwrap();
        self.revoked.store(true, Ordering::Release);
        for weak in connections.drain(..) {
            if let Some(connection) = weak.upgrade() {
                connection.close(0u32.into(), b"pairing changed");
            }
        }
    }
}

pub(crate) struct IncomingPairGuard {
    trust: SharedTrust,
    peer: String,
    released: AtomicBool,
    presence: std::sync::Weak<crate::presence::PresenceManager>,
}

impl IncomingPairGuard {
    pub(crate) async fn release(&self) {
        if self.released.swap(true, Ordering::AcqRel) {
            return;
        }
        {
            let mut trust = self.trust.write().await;
            trust.end_incoming_pairing(&self.peer);
        }
        if let Some(presence) = self.presence.upgrade() {
            presence.reconcile_trusted_peers().await;
        }
    }
}

pub(crate) async fn begin_incoming_pair(
    trust: SharedTrust,
    peer: String,
    connection: Connection,
    presence: std::sync::Weak<crate::presence::PresenceManager>,
) -> Arc<IncomingPairGuard> {
    {
        let mut state = trust.write().await;
        state.begin_incoming_pairing(peer.clone());
    }
    let guard = Arc::new(IncomingPairGuard {
        trust,
        peer,
        released: AtomicBool::new(false),
        presence,
    });
    let cleanup = guard.clone();
    let weak_connection = connection.weak_handle();
    tokio::spawn(async move {
        tokio::select! {
            _ = weak_connection.closed() => {},
            _ = tokio::time::sleep(std::time::Duration::from_secs(95)) => {
                if let Some(connection) = weak_connection.upgrade() {
                    connection.close(0u32.into(), b"pairing timed out");
                }
            }
        }
        cleanup.release().await;
    });
    guard
}

/// The lifetime of one local outgoing pairing operation.
pub(crate) struct OutgoingAttempt {
    pub(crate) cancel: tokio::sync::watch::Sender<bool>,
    pub(crate) started: AtomicBool,
    pub(crate) finished: AtomicBool,
}

impl Default for OutgoingAttempt {
    fn default() -> Self {
        Self {
            cancel: tokio::sync::watch::channel(false).0,
            started: AtomicBool::new(false),
            finished: AtomicBool::new(false),
        }
    }
}

impl OutgoingAttempt {
    pub(crate) fn cancel(&self) {
        self.cancel.send_replace(true);
        if !self.started.swap(true, Ordering::AcqRel) {
            self.finished.store(true, Ordering::Release);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pairing_rotates_a_session_once_until_both_directions_finish() {
        let mut state = TrustState::default();
        state.replace_trusted_peers(HashSet::from(["peer".into()]));
        let old = state.sessions["peer"].clone();
        state.begin_pairing("peer".into());
        let current = state.sessions["peer"].clone();
        assert!(old.is_revoked());
        assert!(!Arc::ptr_eq(&old, &current));

        state.begin_incoming_pairing("peer".into());
        state.begin_pairing("peer".into());
        assert!(Arc::ptr_eq(&current, &state.sessions["peer"]));
        assert!(!current.is_revoked());
        state.end_pairing("peer");
        assert_eq!(state.status("peer"), TrustStatus::Pending);
        state.end_incoming_pairing("peer");
        assert!(state.is_current("peer", &current));
        assert!(!state.is_current("peer", &old));

        state.begin_pairing("peer".into());
        assert!(current.is_revoked());
    }

    #[test]
    fn ending_pairing_cancels_an_attempt_without_replacing_it_while_running() {
        let mut state = TrustState::default();
        state.begin_pairing("peer".into());
        let old = state.begin_outgoing_pairing("peer".into()).unwrap();
        old.started.store(true, Ordering::Release);
        state.end_pairing("peer");
        assert!(*old.cancel.borrow());
        assert!(!old.finished.load(Ordering::Acquire));

        state.begin_pairing("peer".into());
        assert!(state.begin_outgoing_pairing("peer".into()).is_err());
        old.finished.store(true, Ordering::Release);
        let current = state.begin_outgoing_pairing("peer".into()).unwrap();
        old.cancel();
        assert!(!*current.cancel.borrow());
    }

    #[test]
    fn replacing_trust_revokes_only_removed_sessions() {
        let mut state = TrustState::default();
        state.replace_trusted_peers(HashSet::from(["kept".into(), "removed".into()]));
        let kept = state.sessions["kept"].clone();
        let removed = state.sessions["removed"].clone();
        state.replace_trusted_peers(HashSet::from(["kept".into(), "added".into()]));
        assert!(state.is_current("kept", &kept));
        assert!(removed.is_revoked());
        assert_eq!(state.status("removed"), TrustStatus::Unpaired);
        assert_eq!(state.status("added"), TrustStatus::Paired);
    }
}
