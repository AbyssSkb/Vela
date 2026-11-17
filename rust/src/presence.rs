use std::{
    collections::HashMap,
    future::Future,
    pin::Pin,
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Arc, Mutex as StdMutex,
    },
    time::{Duration, Instant},
};

use crate::api::node::{
    valid_device_name, valid_device_type, DeviceInfo, PeerPresenceSnapshot, PresenceSnapshot,
};
use crate::proof_clock::{self, ProofInstant, ProofTimer};
use crate::trust::{PeerSession, SharedTrust, TrustStatus};
use anyhow::{anyhow, Result};
use iroh::{endpoint::Connection, Endpoint, EndpointAddr, Watcher};
use tokio::sync::{watch, Mutex, Notify, RwLock};

use crate::protocol::{
    alpn,
    presence::{self as presence_wire, MessageKind, Nonce, Packet},
};
const LEASE: Duration = Duration::from_millis(2500);
const RECOVERY_GRACE: Duration = Duration::from_secs(5);
const CANDIDATE_RETRY: Duration = Duration::from_secs(1);
const CANDIDATE_STAGGER: Duration = Duration::from_millis(1500);
const CANDIDATE_ROTATE: Duration = Duration::from_millis(2500);
const INTERVAL: Duration = Duration::from_millis(500);
const INACTIVE: Duration = Duration::from_secs(4);
const CONNECT_TIMEOUT: Duration = Duration::from_secs(15);
const STATS_REPORT_INTERVAL: Duration = Duration::from_secs(60);
static NEXT_TRACE: AtomicU64 = AtomicU64::new(1);
static NEXT_SESSION: AtomicU64 = AtomicU64::new(1);

struct ProbeStats {
    id: u64,
    trace: u64,
    attempt: u64,
    role: &'static str,
    generation: u64,
    started: ProofInstant,
    last_report: Instant,
    ping_attempts: u64,
    ping_queued: u64,
    ping_received: u64,
    pong_queued: u64,
    pong_valid: u64,
    pong_unmatched: u64,
    pong_rejected: u64,
    reject_stopped: u64,
    reject_epoch_fresh: u64,
    reject_epoch_expired: u64,
    reject_expired: u64,
    reject_invalid: u64,
    reject_owner: u64,
    max_rtt_ms: u64,
    max_tick_lag_ms: u64,
    first_ping_reported: bool,
    first_pong_reported: bool,
}

impl ProbeStats {
    fn new(trace: u64, attempt: u64, role: &'static str) -> Self {
        Self {
            id: NEXT_SESSION.fetch_add(1, Ordering::Relaxed),
            trace,
            attempt,
            role,
            generation: crate::diagnostics::state().1,
            started: proof_clock::now(),
            last_report: Instant::now(),
            ping_attempts: 0,
            ping_queued: 0,
            ping_received: 0,
            pong_queued: 0,
            pong_valid: 0,
            pong_unmatched: 0,
            pong_rejected: 0,
            reject_stopped: 0,
            reject_epoch_fresh: 0,
            reject_epoch_expired: 0,
            reject_expired: 0,
            reject_invalid: 0,
            reject_owner: 0,
            max_rtt_ms: 0,
            max_tick_lag_ms: 0,
            first_ping_reported: false,
            first_pong_reported: false,
        }
    }

    fn recording_for(&mut self, enabled: bool, generation: u64) -> bool {
        if self.generation != generation {
            self.generation = generation;
            self.started = proof_clock::now();
            self.last_report = Instant::now();
            self.ping_attempts = 0;
            self.ping_queued = 0;
            self.ping_received = 0;
            self.pong_queued = 0;
            self.pong_valid = 0;
            self.pong_unmatched = 0;
            self.pong_rejected = 0;
            self.reject_stopped = 0;
            self.reject_epoch_fresh = 0;
            self.reject_epoch_expired = 0;
            self.reject_expired = 0;
            self.reject_invalid = 0;
            self.reject_owner = 0;
            self.max_rtt_ms = 0;
            self.max_tick_lag_ms = 0;
            self.first_ping_reported = false;
            self.first_pong_reported = false;
        }
        enabled
    }

    fn recording(&mut self) -> bool {
        let (enabled, generation) = crate::diagnostics::state();
        self.recording_for(enabled, generation)
    }

    fn record(&mut self, update: impl FnOnce(&mut Self)) {
        if self.recording() {
            update(self);
        }
    }

    fn probe_for(&mut self, queued: bool, enabled: bool, generation: u64) -> bool {
        if !self.recording_for(enabled, generation) {
            return false;
        }
        self.ping_attempts += 1;
        if queued {
            self.ping_queued += 1;
        }
        if !self.first_ping_reported {
            self.first_ping_reported = true;
            return true;
        }
        false
    }

    fn probe(&mut self, queued: bool) {
        let (enabled, generation) = crate::diagnostics::state();
        if self.probe_for(queued, enabled, generation) {
            crate::diagnostics::first_ping_for_generation(
                self.trace,
                self.attempt,
                queued,
                self.started.elapsed().as_millis() as u64,
                generation,
            );
        }
    }

    fn first_pong(&mut self, sent: ProofInstant) {
        if !self.recording() || self.first_pong_reported || sent < self.started {
            return;
        }
        self.first_pong_reported = true;
        crate::diagnostics::first_pong_for_generation(
            self.trace,
            self.attempt,
            self.started.elapsed().as_millis() as u64,
            sent.elapsed().as_millis() as u64,
            self.generation,
        );
    }

    fn session_end(&mut self, outcome: crate::diagnostics::SessionOutcome) {
        if !self.recording() {
            return;
        }
        crate::diagnostics::session_end_for_generation(
            outcome,
            self.trace,
            self.attempt,
            self.started.elapsed().as_millis() as u64,
            self.ping_attempts - self.ping_queued,
            self.generation,
        );
    }

    fn proof_expired(&mut self, had_proof: bool) {
        if !self.recording() {
            return;
        }
        crate::diagnostics::session_proof_expired_for_generation(
            self.trace,
            self.attempt,
            self.started.elapsed().as_millis() as u64,
            had_proof,
            self.generation,
        );
    }

    fn candidate_end(&mut self, outcome: crate::diagnostics::BackupOutcome) {
        if !self.recording() {
            return;
        }
        crate::diagnostics::backup_end_for_generation(
            outcome,
            self.trace,
            self.attempt,
            self.started.elapsed().as_millis() as u64,
            self.generation,
        );
    }

    fn tick(&mut self, scheduled: tokio::time::Instant) {
        if !self.recording() {
            return;
        }
        self.max_tick_lag_ms = self.max_tick_lag_ms.max(
            tokio::time::Instant::now()
                .saturating_duration_since(scheduled)
                .as_millis() as u64,
        );
        if self.last_report.elapsed() >= STATS_REPORT_INTERVAL {
            self.report("periodic");
        }
    }

    fn record_response(&mut self, response: &std::result::Result<(), PongRejection>) {
        if !self.recording() {
            return;
        }
        match response {
            Ok(()) => {
                self.pong_valid += 1;
            }
            Err(reason) => {
                self.pong_rejected += 1;
                match reason {
                    PongRejection::Stopped => self.reject_stopped += 1,
                    PongRejection::EpochFresh => self.reject_epoch_fresh += 1,
                    PongRejection::EpochExpired => self.reject_epoch_expired += 1,
                    PongRejection::Expired => self.reject_expired += 1,
                    PongRejection::Invalid => self.reject_invalid += 1,
                }
            }
        }
    }

    fn report(&mut self, phase: &str) {
        if !self.recording() {
            return;
        }
        crate::diagnostics::with_enabled(self.generation, || {
            log::warn!("vela_presence_stats phase={} scope=cumulative rtt_scope=matched_pending unmatched_scope=unknown_late_or_duplicate tick_scope=interval_callback epoch_rejection_payload=unvalidated mono_ms={} session={} trace={} attempt={} role={} elapsed_ms={} ping_attempts={} ping_queued={} ping_received={} pong_queued={} pong_valid={} pong_unmatched={} pong_rejected={} reject_stopped={} reject_epoch_fresh={} reject_epoch_expired={} reject_expired={} reject_invalid={} reject_owner={} max_app_rtt_ms={} max_tick_lag_ms={}", phase, crate::diagnostics::monotonic_ms(), self.id, self.trace, self.attempt, self.role, self.started.elapsed().as_millis(), self.ping_attempts, self.ping_queued, self.ping_received, self.pong_queued, self.pong_valid, self.pong_unmatched, self.pong_rejected, self.reject_stopped, self.reject_epoch_fresh, self.reject_epoch_expired, self.reject_expired, self.reject_invalid, self.reject_owner, self.max_rtt_ms, self.max_tick_lag_ms)
        });
        self.last_report = Instant::now();
    }
}

impl Drop for ProbeStats {
    fn drop(&mut self) {
        self.report("end");
    }
}

#[derive(Clone, Default)]
struct Status {
    proof: Option<(ProofInstant, DeviceInfo)>,
    unpaired: Option<ProofInstant>,
    latest: Option<ProofInstant>,
}
struct Barriers {
    network: ProofInstant,
    resume: ProofInstant,
    clock_fault: bool,
}
impl Barriers {
    fn new(at: ProofInstant) -> Self {
        let valid = proof_clock::is_valid(at);
        let at = if valid { at } else { proof_clock::minimum() };
        Self {
            network: at,
            resume: at,
            clock_fault: !valid,
        }
    }
    fn observe_clock(&mut self, now: ProofInstant) -> bool {
        if !proof_clock::is_valid(now) {
            self.clock_fault = true;
            return false;
        }
        if self.clock_fault {
            self.network = self.network.max(now);
            self.resume = self.resume.max(now);
            self.clock_fault = false;
            return false;
        }
        true
    }
}
struct PeerProbeState {
    session: Arc<PeerSession>,
    trace: u64,
    network_epoch: AtomicU64,
    last_used: StdMutex<Instant>,
    min_sent: StdMutex<Barriers>,
    status: watch::Sender<Status>,
    wake: Notify,
    stopped: AtomicBool,
    monitored: AtomicBool,
}
impl PeerProbeState {
    fn inactive(&self) -> bool {
        !self.monitored.load(Ordering::Relaxed)
            && self.last_used.lock().unwrap().elapsed() >= INACTIVE
    }
}
struct SnapshotWatcher {
    peer: Arc<PeerProbeState>,
    task: tokio::task::JoinHandle<()>,
}
type SnapshotSignature = Vec<(String, bool, Option<(String, String)>)>;
pub(crate) struct PresenceManager {
    endpoint: Endpoint,
    trust: SharedTrust,
    info: Arc<RwLock<Option<DeviceInfo>>>,
    // On-demand probes need no snapshot watcher; session changes invalidate every old runtime.
    probes: Arc<Mutex<HashMap<String, Arc<PeerProbeState>>>>,
    inbound_connections: Arc<Mutex<HashMap<String, Vec<Connection>>>>,
    monitoring: AtomicBool,
    closed: AtomicBool,
    reconcile_lock: Mutex<()>,
    snapshot_watchers: Arc<Mutex<HashMap<String, SnapshotWatcher>>>,
    reconciled_sessions: Mutex<HashMap<String, Arc<PeerSession>>>,
    snapshot_cache: Arc<Mutex<Option<SnapshotSignature>>>,
    revisions: watch::Sender<u64>,
}

impl PresenceManager {
    pub(crate) fn new(
        endpoint: Endpoint,
        trust: SharedTrust,
        inbound_connections: Arc<Mutex<HashMap<String, Vec<Connection>>>>,
        info: Arc<RwLock<Option<DeviceInfo>>>,
    ) -> Self {
        Self {
            endpoint,
            trust,
            info,
            probes: Arc::new(Mutex::new(HashMap::new())),
            inbound_connections,
            monitoring: AtomicBool::new(false),
            closed: AtomicBool::new(false),
            reconcile_lock: Mutex::new(()),
            snapshot_watchers: Arc::new(Mutex::new(HashMap::new())),
            reconciled_sessions: Mutex::new(HashMap::new()),
            snapshot_cache: Arc::new(Mutex::new(None)),
            revisions: watch::channel(1).0,
        }
    }

    fn changed(&self) {
        self.revisions
            .send_modify(|r| *r = r.wrapping_add(1).max(1));
    }

    pub(crate) async fn set_monitoring(&self, enabled: bool) -> Result<()> {
        if self.closed.load(Ordering::Relaxed) {
            return Err(anyhow!("presence stopped"));
        }
        self.monitoring.store(enabled, Ordering::Relaxed);
        self.reconcile_trusted_peers().await;
        Ok(())
    }

    pub(crate) async fn reconcile_trusted_peers(&self) {
        let _serial = self.reconcile_lock.lock().await;
        if self.closed.load(Ordering::Relaxed) {
            return;
        }
        let trust = self.trust.read().await;
        let desired: HashMap<_, _> = trust
            .sessions
            .iter()
            .filter(|(id, session)| trust.is_current(id, session))
            .map(|(id, session)| (id.clone(), session.clone()))
            .collect();
        let enabled = self.monitoring.load(Ordering::Relaxed);
        let mut reconciled_sessions = self.reconciled_sessions.lock().await;
        let changed_ids: Vec<_> = reconciled_sessions
            .keys()
            .chain(desired.keys())
            .filter(
                |id| match (reconciled_sessions.get(*id), desired.get(*id)) {
                    (Some(a), Some(b)) => !Arc::ptr_eq(a, b),
                    (None, None) => false,
                    _ => true,
                },
            )
            .cloned()
            .collect();
        let mut snapshot_watchers = self.snapshot_watchers.lock().await;
        let mut probes = self.probes.lock().await;
        let mut inbound_connections = self.inbound_connections.lock().await;
        for id in &changed_ids {
            if let Some(watcher) = snapshot_watchers.remove(id) {
                watcher.task.abort();
            }
            if let Some(peer) = probes.remove(id) {
                peer.stopped.store(true, Ordering::Relaxed);
                peer.wake.notify_one();
            }
            if let Some(connections) = inbound_connections.remove(id) {
                for conn in connections {
                    conn.close(0u32.into(), b"pairing changed");
                }
            }
        }
        for id in probes
            .keys()
            .filter(|id| !desired.contains_key(*id))
            .cloned()
            .collect::<Vec<_>>()
        {
            if let Some(peer) = probes.remove(&id) {
                peer.stopped.store(true, Ordering::Relaxed);
                peer.wake.notify_one();
            }
        }
        for id in inbound_connections
            .keys()
            .filter(|id| !desired.contains_key(*id))
            .cloned()
            .collect::<Vec<_>>()
        {
            if let Some(connections) = inbound_connections.remove(&id) {
                for conn in connections {
                    conn.close(0u32.into(), b"unpaired");
                }
            }
        }
        *reconciled_sessions = desired.clone();
        let mut mutated = !changed_ids.is_empty();
        if !enabled {
            for (id, watcher) in snapshot_watchers.drain() {
                watcher.task.abort();
                watcher.peer.stopped.store(true, Ordering::Relaxed);
                watcher.peer.wake.notify_one();
                if probes
                    .get(&id)
                    .is_some_and(|peer| Arc::ptr_eq(peer, &watcher.peer))
                {
                    probes.remove(&id);
                }
                mutated = true;
            }
        } else {
            for (id, session) in &desired {
                if snapshot_watchers.contains_key(id) {
                    continue;
                }
                let peer = if let Some(peer) = probes.get(id).filter(|peer| {
                    Arc::ptr_eq(&peer.session, session)
                        && !peer.stopped.load(Ordering::Relaxed)
                        && !peer.inactive()
                }) {
                    peer.clone()
                } else {
                    let Ok(peer) =
                        self.start_peer(&mut probes, id, session.clone(), proof_clock::now(), true)
                    else {
                        continue;
                    };
                    peer
                };
                peer.monitored.store(true, Ordering::Relaxed);
                let task = tokio::spawn(watch_peer(
                    id.clone(),
                    peer.clone(),
                    self.revisions.clone(),
                    self.snapshot_cache.clone(),
                ));
                snapshot_watchers.insert(id.clone(), SnapshotWatcher { peer, task });
                mutated = true;
            }
        }
        drop(inbound_connections);
        drop(probes);
        drop(snapshot_watchers);
        drop(reconciled_sessions);
        drop(trust);
        if mutated {
            let _cache = self.snapshot_cache.lock().await;
            self.changed();
        }
    }

    fn start_peer(
        &self,
        probes: &mut HashMap<String, Arc<PeerProbeState>>,
        id: &str,
        session: Arc<PeerSession>,
        started: ProofInstant,
        monitored: bool,
    ) -> Result<Arc<PeerProbeState>> {
        let address = EndpointAddr::new(id.parse()?);
        let peer = Arc::new(PeerProbeState {
            session,
            trace: NEXT_TRACE.fetch_add(1, Ordering::Relaxed),
            network_epoch: AtomicU64::new(0),
            last_used: StdMutex::new(Instant::now()),
            min_sent: StdMutex::new(Barriers::new(started)),
            status: watch::channel(Status::default()).0,
            wake: Notify::new(),
            stopped: AtomicBool::new(false),
            monitored: AtomicBool::new(monitored),
        });
        probes.insert(id.to_owned(), peer.clone());
        tokio::spawn(run_peer_presence(
            self.endpoint.clone(),
            address,
            id.to_owned(),
            peer.clone(),
            self.probes.clone(),
            self.trust.clone(),
            self.info.clone(),
        ));
        Ok(peer)
    }

    pub(crate) async fn wait_snapshot(&self, after_revision: u64) -> Result<PresenceSnapshot> {
        let mut revision = self.revisions.subscribe();
        loop {
            if self.closed.load(Ordering::Relaxed) {
                return Err(anyhow!("node closed"));
            }
            let observed = *revision.borrow_and_update();
            if observed != after_revision {
                let mut cache = self.snapshot_cache.lock().await;
                let current = *self.revisions.borrow();
                let trust = self.trust.read().await;
                let snapshot_watchers = self.snapshot_watchers.lock().await;
                let now = proof_clock::now();
                let mut peers = Vec::new();
                for (id, watcher) in snapshot_watchers.iter() {
                    if !trust.is_current(id, &watcher.peer.session)
                        || watcher.peer.stopped.load(Ordering::Relaxed)
                    {
                        continue;
                    }
                    let status = watcher.peer.status.borrow().clone();
                    let proof = status
                        .proof
                        .filter(|(sent, _)| proof_clock::is_fresh(*sent, now, LEASE));
                    let unpaired = status
                        .unpaired
                        .is_some_and(|sent| proof_clock::is_fresh(sent, now, LEASE));
                    peers.push(PeerPresenceSnapshot {
                        peer_id: id.clone(),
                        info: proof.as_ref().map(|(_, info)| info.clone()),
                        proof_valid_until_ns: proof
                            .map(|(sent, _)| proof_clock::as_nanos(sent + LEASE)),
                        unpaired,
                    });
                }
                peers.sort_by(|a, b| a.peer_id.cmp(&b.peer_id));
                drop(snapshot_watchers);
                drop(trust);
                if *self.revisions.borrow() != current {
                    continue;
                }
                let signature = peers
                    .iter()
                    .map(|peer| {
                        (
                            peer.peer_id.clone(),
                            peer.unpaired,
                            peer.info
                                .as_ref()
                                .map(|info| (info.name.clone(), info.device_type.clone())),
                        )
                    })
                    .collect();
                if cache.as_ref() != Some(&signature) {
                    *cache = Some(signature);
                    self.changed();
                }
                let current = *self.revisions.borrow();
                if self.closed.load(Ordering::Relaxed) {
                    return Err(anyhow!("node closed"));
                }
                return Ok(PresenceSnapshot {
                    revision: current,
                    peers,
                });
            }
            tokio::select! {
                changed = revision.changed() => if changed.is_err() { return Err(anyhow!("presence stopped")); },
                _ = self.endpoint.closed() => return Err(anyhow!("node closed")),
            }
        }
    }

    pub(crate) async fn revoke_if_unpaired(&self, id: &str) -> bool {
        {
            let mut trust = self.trust.write().await;
            let snapshot_watchers = self.snapshot_watchers.lock().await;
            let Some(watcher) = snapshot_watchers.get(id) else {
                return false;
            };
            {
                let barrier = watcher.peer.min_sent.lock().unwrap();
                if !trust.is_current(id, &watcher.peer.session)
                    || watcher.peer.stopped.load(Ordering::Relaxed)
                    || !watcher.peer.status.borrow().unpaired.is_some_and(|sent| {
                        sent >= barrier.network
                            && sent >= barrier.resume
                            && proof_clock::is_fresh(sent, proof_clock::now(), LEASE)
                    })
                {
                    return false;
                }
            }
            let session = trust.sessions.remove(id).unwrap();
            session.revoke();
        }
        self.reconcile_trusted_peers().await;
        true
    }

    pub(crate) async fn shutdown(&self) {
        let _serial = self.reconcile_lock.lock().await;
        if self.closed.swap(true, Ordering::Relaxed) {
            return;
        }
        self.monitoring.store(false, Ordering::Relaxed);
        for (_, watcher) in self.snapshot_watchers.lock().await.drain() {
            watcher.task.abort();
        }
        for (_, peer) in self.probes.lock().await.drain() {
            peer.stopped.store(true, Ordering::Relaxed);
            peer.wake.notify_one();
        }
        for (_, connections) in self.inbound_connections.lock().await.drain() {
            for conn in connections {
                conn.close(0u32.into(), b"node closed");
            }
        }
        let _cache = self.snapshot_cache.lock().await;
        self.changed();
    }

    pub(crate) async fn check(&self, id: &str, fresh: bool) -> Result<DeviceInfo> {
        if self.closed.load(Ordering::Relaxed) {
            return Err(anyhow!("presence stopped"));
        }
        let trust = self.trust.read().await;
        let session = trust
            .sessions
            .get(id)
            .filter(|session| trust.is_current(id, session))
            .cloned()
            .ok_or_else(|| anyhow!("untrusted device"))?;
        let started = proof_clock::now();
        if !proof_clock::is_valid(started) {
            return Err(anyhow!("presence clock unavailable"));
        }
        let peer = {
            let mut probes = self.probes.lock().await;
            if self.closed.load(Ordering::Relaxed) {
                return Err(anyhow!("presence stopped"));
            }
            let existing = probes.get(id).and_then(|peer| {
                if peer.stopped.load(Ordering::Relaxed) || !Arc::ptr_eq(&peer.session, &session) {
                    return None;
                }
                let mut last_used = peer.last_used.lock().unwrap();
                if !peer.monitored.load(Ordering::Relaxed) && last_used.elapsed() >= INACTIVE {
                    return None;
                }
                *last_used = Instant::now();
                Some(peer.clone())
            });
            if let Some(peer) = existing {
                peer
            } else {
                if let Some(old) = probes.remove(id) {
                    old.stopped.store(true, Ordering::Relaxed);
                    old.wake.notify_one();
                }
                self.start_peer(&mut probes, id, session.clone(), started, false)?
            }
        };
        drop(trust);
        if fresh {
            peer.wake.notify_one();
        }
        let mut status = peer.status.subscribe();
        let mut timer = ProofTimer::new();
        loop {
            let current = status.borrow_and_update().clone();
            if let Some((sent, info)) = &current.proof {
                if proof_clock::is_fresh(*sent, proof_clock::now(), LEASE)
                    && (!fresh || *sent >= started)
                {
                    return Ok(info.clone());
                }
            }
            if !fresh {
                return Err(anyhow!("device unavailable"));
            }
            let deadline = current
                .proof
                .as_ref()
                .filter(|(sent, _)| *sent + LEASE > started)
                .map_or(started + LEASE, |(sent, _)| {
                    (started + LEASE).min(*sent + LEASE)
                });
            tokio::select! {
                changed = status.changed() => if changed.is_err() { return Err(anyhow!("presence stopped")); },
                _ = timer.wait_until(deadline) => if proof_clock::now() >= deadline { return Err(anyhow!("status check timed out")); },
            }
        }
    }

    pub(crate) async fn respond(
        &self,
        conn: &Connection,
        sender: &str,
        info: &RwLock<Option<DeviceInfo>>,
        registered: Option<Arc<PeerSession>>,
    ) {
        let mut interval = tokio::time::interval(INTERVAL);
        interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
        let mut pending: HashMap<Nonce, (ProofInstant, std::sync::Weak<PeerProbeState>)> =
            HashMap::new();
        let mut path = None;
        let mut stats = ProbeStats::new(0, 0, "incoming");
        let mut last_received = tokio::time::Instant::now();
        loop {
            tokio::select! {
                scheduled = interval.tick() => {
                    stats.tick(scheduled);
                    let trust = self.trust.read().await;
                    let active = registered.as_ref().is_some_and(|session| trust.is_current(sender, session));
                    if !active { pending.clear(); continue; }
                    let peer = self.probes.lock().await.get(sender).cloned();
                    if let Some(peer) = peer.filter(|p| registered.as_ref().is_some_and(|session| Arc::ptr_eq(&p.session, session)) && !p.stopped.load(Ordering::Relaxed) && !p.inactive()) {
                        if stats.trace != peer.trace { stats.trace = peer.trace; stats.first_ping_reported = false; stats.first_pong_reported = false; path = None; }
                        if observe_path(conn, peer.trace, 0, &mut path) { stats.report("path_changed"); }
                        let now = proof_clock::now();
                        pending.retain(|_, (sent, _)| now.duration_since(*sent) < LEASE);
                        let probe = send_probe(conn);
                        stats.probe(probe.is_some());
                        if let Some((nonce, sent)) = probe { pending.insert(nonce, (sent, Arc::downgrade(&peer))); }
                    } else { pending.clear(); }
                },
                _ = tokio::time::sleep_until(last_received + Duration::from_secs(15)) => break,
                data = conn.read_datagram() => {
                    let Ok(data) = data else { break };
                    last_received = tokio::time::Instant::now();
                    let trust = self.trust.read().await;
                    let Some(packet) = Packet::decode(&data) else { continue };
                    match packet.kind {
                        MessageKind::Probe => {
                            let status = trust.status(sender);
                            let paired_on_this_connection = registered.as_ref().is_some_and(|session| trust.is_current(sender, session));
                            if status == TrustStatus::Paired && !paired_on_this_connection { break; }
                            stats.record(|s| s.ping_received += 1);
                            if reply_ping(conn, &packet.nonce, info, status).await { stats.record(|s| s.pong_queued += 1); }
                        }
                        MessageKind::Paired | MessageKind::Pending | MessageKind::Unpaired => {
                            let Some((sent, owner)) = pending.remove(&packet.nonce) else { stats.record(|s| s.pong_unmatched += 1); continue };
                            stats.record(|s| { if sent >= s.started { s.max_rtt_ms = s.max_rtt_ms.max(sent.elapsed().as_millis() as u64); } });
                            let Some(peer) = owner.upgrade() else { stats.record(|s| { s.pong_rejected += 1; s.reject_owner += 1; }); continue };
                            let probes = self.probes.lock().await;
                            if !trust.is_current(sender, &peer.session) || !probes.get(sender).is_some_and(|p| Arc::ptr_eq(p, &peer)) || peer.stopped.load(Ordering::Relaxed) { stats.record(|s| { s.pong_rejected += 1; s.reject_owner += 1; }); continue; }
                            let response = peer.accept_response(sent, &data);
                            stats.record_response(&response);
                            if response.is_ok() { stats.first_pong(sent); }
                        }
                    }
                }
            }
        }
        conn.close(0u32.into(), b"presence ended");
    }

    pub(crate) async fn on_network_changed(&self) {
        for peer in self.probes.lock().await.values() {
            let mut min_sent = peer.min_sent.lock().unwrap();
            let now = proof_clock::now();
            if !min_sent.observe_clock(now) {
                peer.status.send_replace(Status::default());
                peer.network_epoch.fetch_add(1, Ordering::Relaxed);
                peer.wake.notify_one();
                continue;
            }
            min_sent.network = min_sent.network.max(now);
            peer.network_epoch.fetch_add(1, Ordering::Relaxed);
            peer.status.send_modify(|state| state.unpaired = None);
            drop(min_sent);
            peer.wake.notify_one();
        }
    }

    pub(crate) async fn request_probe(&self) {
        for peer in self.probes.lock().await.values() {
            peer.wake.notify_one();
        }
    }

    pub(crate) async fn invalidate_for_resume(&self) {
        for peer in self.probes.lock().await.values() {
            let mut min_sent = peer.min_sent.lock().unwrap();
            let now = proof_clock::now();
            if !min_sent.observe_clock(now) {
                peer.status.send_replace(Status::default());
                peer.network_epoch.fetch_add(1, Ordering::Relaxed);
                peer.wake.notify_one();
                continue;
            }
            let now = now + Duration::from_nanos(1);
            min_sent.network = min_sent.network.max(now);
            min_sent.resume = min_sent.resume.max(now);
            peer.network_epoch.fetch_add(1, Ordering::Relaxed);
            peer.status.send_replace(Status::default());
        }
    }
}

async fn watch_peer(
    id: String,
    peer: Arc<PeerProbeState>,
    revisions: watch::Sender<u64>,
    cache: Arc<Mutex<Option<SnapshotSignature>>>,
) {
    let mut status = peer.status.subscribe();
    let mut timer = ProofTimer::new();
    loop {
        let current_status = status.borrow_and_update().clone();
        let now = proof_clock::now();
        let valid = current_status
            .proof
            .as_ref()
            .filter(|(sent, _)| proof_clock::is_fresh(*sent, now, LEASE));
        let unpaired = current_status
            .unpaired
            .filter(|sent| proof_clock::is_fresh(*sent, now, LEASE));
        let current = (
            unpaired.is_some(),
            valid.map(|(_, info)| (info.name.clone(), info.device_type.clone())),
        );
        {
            let cache = cache.lock().await;
            let published = cache
                .as_ref()
                .and_then(|snapshot| snapshot.iter().find(|(peer_id, _, _)| peer_id == &id))
                .map(|(_, value, info)| (*value, info.clone()));
            if published != Some(current) && !peer.stopped.load(Ordering::Relaxed) {
                revisions.send_modify(|r| *r = r.wrapping_add(1).max(1));
            }
        }
        let deadline = valid
            .map(|(sent, _)| *sent + LEASE)
            .or(unpaired.map(|sent| sent + LEASE));
        tokio::select! {
            changed = status.changed() => if changed.is_err() { break; },
            _ = async { match deadline { Some(deadline) => timer.wait_until(deadline).await, None => std::future::pending().await } } => {},
        }
    }
}

fn candidate_is_current(sent: ProofInstant, min_sent: ProofInstant, now: ProofInstant) -> bool {
    sent >= min_sent && proof_clock::is_fresh(sent, now, LEASE)
}

#[derive(Clone, PartialEq, Eq)]
struct ObservedPath {
    kind: crate::diagnostics::PathKind,
    local: Option<String>,
    remote: Option<String>,
}

fn diagnostic_local_addr(addr: &iroh::endpoint::LocalTransportAddr) -> Option<String> {
    use iroh::endpoint::LocalTransportAddr;
    match addr {
        LocalTransportAddr::Ip(address) => address.map(|address| address.to_string()),
        LocalTransportAddr::Relay(url) => {
            Some(crate::diagnostic_redact::sanitize(&url.to_string()))
        }
        _ => None,
    }
}

fn diagnostic_remote_addr(addr: &iroh::TransportAddr) -> Option<String> {
    match addr {
        iroh::TransportAddr::Ip(_) => Some(addr.to_string()),
        iroh::TransportAddr::Relay(_) => {
            Some(crate::diagnostic_redact::sanitize(&addr.to_string()))
        }
        _ => None,
    }
}

fn observe_path(
    conn: &Connection,
    trace: u64,
    attempt: u64,
    previous: &mut Option<(u64, ObservedPath)>,
) -> bool {
    use crate::diagnostics::PathKind;
    let (enabled, generation) = crate::diagnostics::state();
    if !enabled {
        *previous = None;
        return false;
    }
    let paths = conn.paths();
    let selected = paths.iter().find(|path| path.is_selected());
    let kind = match &selected {
        Some(path) if path.is_ip() => PathKind::Ip,
        Some(path) if path.is_relay() => PathKind::Relay,
        _ => PathKind::Unknown,
    };
    let local = selected
        .as_ref()
        .and_then(|path| diagnostic_local_addr(&path.local_addr()));
    let remote = selected
        .as_ref()
        .and_then(|path| diagnostic_remote_addr(&path.remote_addr()));
    let observed = ObservedPath {
        kind,
        local,
        remote,
    };
    let prior = previous
        .as_ref()
        .filter(|(epoch, _)| *epoch == generation)
        .map(|(_, path)| path);
    let changed = prior.is_some() && prior != Some(&observed);
    if prior != Some(&observed) {
        let kind_name = match kind {
            PathKind::Ip => "ip",
            PathKind::Relay => "relay",
            PathKind::Unknown => "unknown",
        };
        let details = serde_json::json!({ "peer_id": conn.remote_id().to_string(), "local_addr": observed.local, "remote_addr": observed.remote, "path_kind": kind_name }).to_string();
        crate::diagnostics::session_path_details(kind, trace, attempt, details, generation);
        *previous = Some((generation, observed));
    }
    changed
}

async fn wait_for_candidate_dial<F: Future>(
    dial: F,
    peer: &PeerProbeState,
    network_epoch: u64,
) -> Result<F::Output, crate::diagnostics::DialOutcome> {
    tokio::pin!(dial);
    let timeout = tokio::time::sleep(CONNECT_TIMEOUT);
    tokio::pin!(timeout);
    let mut interval = tokio::time::interval(INTERVAL);
    let mut change_timer = ProofTimer::new();
    loop {
        let change_deadline = {
            let min_sent = peer.min_sent.lock().unwrap();
            (peer.network_epoch.load(Ordering::Relaxed) != network_epoch)
                .then_some(min_sent.network + INTERVAL)
        };
        tokio::select! {
            result = &mut dial => return Ok(result),
            _ = &mut timeout => return Err(crate::diagnostics::DialOutcome::Timeout),
            _ = interval.tick() => {
                if peer.stopped.load(Ordering::Relaxed) || peer.inactive() { return Err(crate::diagnostics::DialOutcome::Inactive); }
            }
            _ = async { match change_deadline { Some(deadline) => change_timer.wait_until(deadline).await, None => std::future::pending().await } } => {
                if peer.stopped.load(Ordering::Relaxed) || peer.inactive() { return Err(crate::diagnostics::DialOutcome::Inactive); }
                let min_sent = peer.min_sent.lock().unwrap();
                let now = proof_clock::now();
                if proof_clock::is_valid(now) && peer.network_epoch.load(Ordering::Relaxed) != network_epoch && now >= min_sent.network + INTERVAL { return Err(crate::diagnostics::DialOutcome::NetworkChanged); }
            }
        }
    }
}

struct ReadyCandidate {
    connection: Connection,
    proof_sent: ProofInstant,
    attempt: u64,
    stats: ProbeStats,
}

type CandidateFuture<T> = Pin<Box<dyn Future<Output = Option<T>> + Send>>;

struct DialCandidate<T> {
    future: CandidateFuture<T>,
    connected: Arc<AtomicBool>,
    started: Instant,
    retain_until_timeout: bool,
}

async fn race_candidates<T>(
    first: CandidateFuture<T>,
    first_connected: Arc<AtomicBool>,
    progress: Arc<Notify>,
    mut start: impl FnMut(Arc<AtomicBool>) -> Option<CandidateFuture<T>>,
) -> Option<T> {
    let mut last_start = Instant::now();
    let mut next_start = last_start + CANDIDATE_STAGGER;
    let mut candidates = vec![DialCandidate {
        future: first,
        connected: first_connected,
        started: last_start,
        retain_until_timeout: true,
    }];
    loop {
        let now = Instant::now();
        let can_start = candidates.len() < 2
            || (candidates.len() == 2
                && candidates
                    .iter()
                    .any(|c| c.connected.load(Ordering::Acquire)));
        if can_start && now >= next_start.max(last_start + CANDIDATE_RETRY) {
            let connected = Arc::new(AtomicBool::new(false));
            let future = start(connected.clone())?;
            candidates.push(DialCandidate {
                future,
                connected,
                started: now,
                retain_until_timeout: candidates.is_empty(),
            });
            last_start = now;
            next_start = now + CANDIDATE_RETRY;
        }
        let rotate_at = candidates
            .iter()
            .filter(|c| !c.retain_until_timeout && !c.connected.load(Ordering::Acquire))
            .map(|c| c.started + CANDIDATE_ROTATE)
            .min();
        let can_start = candidates.len() < 2
            || (candidates.len() == 2
                && candidates
                    .iter()
                    .any(|c| c.connected.load(Ordering::Acquire)));
        tokio::select! {
            biased;
            (index, result) = std::future::poll_fn(|cx| {
                for (index, candidate) in candidates.iter_mut().enumerate() {
                    if let std::task::Poll::Ready(value) = candidate.future.as_mut().poll(cx) { return std::task::Poll::Ready((index, value)); }
                }
                std::task::Poll::Pending
            }), if !candidates.is_empty() => {
                if result.is_some() { return result; }
                let retained_until_timeout = candidates.remove(index).retain_until_timeout;
                if retained_until_timeout { if let Some(first) = candidates.first_mut() { first.retain_until_timeout = true; } }
                next_start = Instant::now();
            }
            _ = progress.notified() => {},
            _ = async { match rotate_at { Some(deadline) => tokio::time::sleep_until(deadline.into()).await, None => std::future::pending().await } } => {
                let now = Instant::now();
                candidates.retain(|c| c.retain_until_timeout || c.connected.load(Ordering::Acquire) || now < c.started + CANDIDATE_ROTATE);
                next_start = now;
            }
            _ = tokio::time::sleep_until(next_start.max(last_start + CANDIDATE_RETRY).into()), if can_start => {},
        }
    }
}

struct CandidateGuard {
    peer: Arc<PeerProbeState>,
    attempt: u64,
    started: Instant,
    completed: bool,
    diagnostic_generation: Option<u64>,
    connection: Option<Connection>,
    handed_off: bool,
}

impl Drop for CandidateGuard {
    fn drop(&mut self) {
        if !self.handed_off {
            if let Some(conn) = &self.connection {
                conn.close(0u32.into(), b"presence candidate ended");
            }
        }
        if !self.completed {
            let Some(generation) = self.diagnostic_generation else {
                return;
            };
            let outcome = if self.peer.stopped.load(Ordering::Relaxed) || self.peer.inactive() {
                crate::diagnostics::BackupOutcome::Inactive
            } else {
                crate::diagnostics::BackupOutcome::Superseded
            };
            crate::diagnostics::backup_end_for_generation(
                outcome,
                self.peer.trace,
                self.attempt,
                self.started.elapsed().as_millis() as u64,
                generation,
            );
        }
    }
}

async fn connect_candidate(
    endpoint: Endpoint,
    address: EndpointAddr,
    id: String,
    peer: Arc<PeerProbeState>,
    trust: SharedTrust,
    info: Arc<RwLock<Option<DeviceInfo>>>,
    attempt: u64,
    network_epoch: u64,
    connected: Arc<AtomicBool>,
    progress: Arc<Notify>,
) -> Option<ReadyCandidate> {
    let started = Instant::now();
    let (enabled, generation) = crate::diagnostics::state();
    let before = if enabled {
        endpoint
            .home_relay_status()
            .get()
            .iter()
            .filter(|relay| relay.is_connected())
            .count() as u32
    } else {
        0
    };
    let start_clock = if enabled {
        crate::diagnostics::clock()
    } else {
        (0, 0)
    };
    let diagnostic_generation = enabled.then_some(generation);
    let mut guard = CandidateGuard {
        peer: peer.clone(),
        attempt,
        started,
        completed: false,
        diagnostic_generation,
        connection: None,
        handed_off: false,
    };
    if enabled {
        crate::diagnostics::dial_start_with_peer(
            peer.trace,
            attempt,
            before,
            start_clock,
            &id,
            generation,
        );
    }
    let dial = async {
        let connecting = endpoint
            .connect_with_opts(address, alpn::PRESENCE, Default::default())
            .await
            .map_err(|error| {
                (
                    "setup",
                    if crate::diagnostics::state() == (true, generation) {
                        Some(format!("{error:#}"))
                    } else {
                        None
                    },
                )
            })?;
        if crate::diagnostics::state() == (true, generation) {
            let ready = (
                started.elapsed().as_millis() as u64,
                crate::diagnostics::clock(),
            );
            crate::diagnostics::dial_setup_done_for_generation(
                peer.trace, attempt, ready.0, ready.1, generation,
            );
        }
        connecting.await.map_err(|error| {
            (
                "handshake",
                if crate::diagnostics::state() == (true, generation) {
                    Some(format!("{error:#}"))
                } else {
                    None
                },
            )
        })
    };
    let result = wait_for_candidate_dial(dial, &peer, network_epoch).await;
    let after = if crate::diagnostics::state() == (true, generation) {
        endpoint
            .home_relay_status()
            .get()
            .iter()
            .filter(|relay| relay.is_connected())
            .count() as u32
    } else {
        0
    };
    let (conn, outcome, error) = match result {
        Ok(Ok(conn)) => (Some(conn), crate::diagnostics::DialOutcome::Connected, None),
        Ok(Err(error)) => (None, crate::diagnostics::DialOutcome::Failed, Some(error)),
        Err(outcome) => (None, outcome, None),
    };
    let elapsed = started.elapsed();
    if enabled {
        let (stage, raw_error) = error.map_or((None, None), |(stage, error)| (Some(stage), error));
        let (error, error_filtered) = raw_error
            .as_deref()
            .map_or((None, false), crate::diagnostics::safe_error);
        let details = serde_json::json!({ "peer_id": id, "stage": stage, "error": error, "error_filtered": error_filtered }).to_string();
        crate::diagnostics::dial_for_generation(
            outcome,
            peer.trace,
            attempt,
            elapsed.as_millis() as u64,
            before,
            after,
            details,
            generation,
        );
    }
    let Some(conn) = conn else {
        guard.completed = true;
        return None;
    };
    guard.connection = Some(conn.clone());
    {
        let trust = trust.read().await;
        if !trust.is_current(&id, &peer.session) || !peer.session.register(&conn) {
            guard.completed = true;
            return None;
        }
    }
    connected.store(true, Ordering::Release);
    progress.notify_one();
    let mut interval = tokio::time::interval(INTERVAL);
    interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    let mut deadline = ProofTimer::new();
    let now = proof_clock::now();
    if !proof_clock::is_valid(now) {
        guard.completed = true;
        return None;
    }
    let mut proof_until = now + LEASE;
    let mut pending = HashMap::new();
    let mut path = None;
    let mut stats = ProbeStats::new(peer.trace, attempt, "candidate");
    loop {
        tokio::select! {
            _ = deadline.wait_until(proof_until) => {
                let now = proof_clock::now();
                if !proof_clock::is_valid(now) || now >= proof_until { stats.candidate_end(crate::diagnostics::BackupOutcome::Expired); guard.completed = true; return None; }
            },
            scheduled = interval.tick() => {
                stats.tick(scheduled);
                if peer.stopped.load(Ordering::Relaxed) || peer.inactive() {
                    stats.candidate_end(crate::diagnostics::BackupOutcome::Inactive); guard.completed = true; return None;
                }
                if observe_path(&conn, peer.trace, attempt, &mut path) { stats.report("path_changed"); }
                let now = proof_clock::now();
                pending.retain(|_, sent| now.duration_since(*sent) < LEASE);
                let probe = send_probe(&conn);
                stats.probe(probe.is_some());
                if let Some((nonce, sent)) = probe { pending.insert(nonce, sent); }
            }
            data = conn.read_datagram() => {
                let Ok(data) = data else { stats.candidate_end(crate::diagnostics::BackupOutcome::Closed); guard.completed = true; return None; };
                let allowed = trust.read().await;
                if !allowed.is_current(&id, &peer.session) { stats.candidate_end(crate::diagnostics::BackupOutcome::Revoked); guard.completed = true; return None; }
                let Some(packet) = Packet::decode(&data) else { continue };
                if packet.kind == MessageKind::Probe { stats.record(|s| s.ping_received += 1); if reply_ping(&conn, &packet.nonce, &info, TrustStatus::Paired).await { stats.record(|s| s.pong_queued += 1); } continue; }
                let Some(sent) = pending.remove(&packet.nonce) else { stats.record(|s| s.pong_unmatched += 1); continue };
                stats.record(|s| { if sent >= s.started { s.max_rtt_ms = s.max_rtt_ms.max(sent.elapsed().as_millis() as u64); } });
                let response = peer.accept_response(sent, &data);
                stats.record_response(&response);
                if response.is_ok() {
                    if packet.kind == MessageKind::Unpaired { guard.completed = true; return None; }
                    if packet.kind != MessageKind::Paired { continue; }
                    stats.first_pong(sent);
                    let min_sent = peer.min_sent.lock().unwrap();
                    if !peer.stopped.load(Ordering::Relaxed) && candidate_is_current(sent, min_sent.network, proof_clock::now()) {
                        guard.completed = true;
                        guard.handed_off = true;
                        return Some(ReadyCandidate { connection: conn, proof_sent: sent, attempt, stats });
                    }
                    let valid_until = sent + LEASE;
                    if !peer.stopped.load(Ordering::Relaxed) && sent >= min_sent.resume && valid_until > proof_until {
                        proof_until = valid_until;
                    }
                }
            }
        }
    }
}

struct Dialer {
    endpoint: Endpoint,
    address: EndpointAddr,
    id: String,
    peer: Arc<PeerProbeState>,
    trust: SharedTrust,
    info: Arc<RwLock<Option<DeviceInfo>>>,
    attempts: AtomicU64,
}

impl Dialer {
    fn start(
        self: &Arc<Self>,
        connected: Arc<AtomicBool>,
        progress: Arc<Notify>,
    ) -> Option<CandidateFuture<ReadyCandidate>> {
        if self.peer.stopped.load(Ordering::Relaxed) || self.peer.inactive() {
            return None;
        }
        let attempt = self.attempts.fetch_add(1, Ordering::Relaxed) + 1;
        let epoch = self.peer.network_epoch.load(Ordering::Relaxed);
        let address = self.address.clone();
        Some(Box::pin(connect_candidate(
            self.endpoint.clone(),
            address,
            self.id.clone(),
            self.peer.clone(),
            self.trust.clone(),
            self.info.clone(),
            attempt,
            epoch,
            connected,
            progress,
        )))
    }

    fn race(self: &Arc<Self>) -> CandidateFuture<ReadyCandidate> {
        let dialer = self.clone();
        Box::pin(async move {
            let connected = Arc::new(AtomicBool::new(false));
            let progress = Arc::new(Notify::new());
            let first = dialer.start(connected.clone(), progress.clone())?;
            race_candidates(first, connected, progress.clone(), |connected| {
                dialer.start(connected, progress.clone())
            })
            .await
        })
    }
}

async fn run_peer_presence(
    endpoint: Endpoint,
    address: EndpointAddr,
    id: String,
    peer: Arc<PeerProbeState>,
    probes: Arc<Mutex<HashMap<String, Arc<PeerProbeState>>>>,
    trust: SharedTrust,
    info: Arc<RwLock<Option<DeviceInfo>>>,
) {
    let dialer = Arc::new(Dialer {
        endpoint,
        address,
        id: id.clone(),
        peer: peer.clone(),
        trust: trust.clone(),
        info: info.clone(),
        attempts: AtomicU64::new(0),
    });
    loop {
        while !peer.stopped.load(Ordering::Relaxed) && !peer.inactive() {
            if !trust.read().await.is_current(&id, &peer.session) {
                break;
            }
            if let Some(ReadyCandidate {
                connection: mut conn,
                proof_sent: initial_sent,
                attempt: initial_attempt,
                mut stats,
            }) = dialer.race().await
            {
                let initial_epoch = {
                    let allowed = trust.read().await;
                    let min_sent = peer.min_sent.lock().unwrap();
                    if !allowed.is_current(&id, &peer.session)
                        || peer.stopped.load(Ordering::Relaxed)
                    {
                        stats.candidate_end(crate::diagnostics::BackupOutcome::Inactive);
                        continue;
                    }
                    if !candidate_is_current(initial_sent, min_sent.network, proof_clock::now()) {
                        stats.candidate_end(crate::diagnostics::BackupOutcome::Stale);
                        continue;
                    }
                    peer.network_epoch.load(Ordering::Relaxed)
                };
                let mut interval = tokio::time::interval(INTERVAL);
                interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
                let mut pending: HashMap<Nonce, ProofInstant> = HashMap::new();
                let mut last_response: Option<ProofInstant> = Some(initial_sent);
                let mut recovery_deadline: Option<ProofInstant> = None;
                let mut proof_timer = ProofTimer::new();
                let mut path = None;
                let mut session_epoch = initial_epoch;
                let mut session_attempt = initial_attempt;
                stats.role = "active";
                let mut candidate_race: Option<CandidateFuture<ReadyCandidate>> = None;
                'sessions: loop {
                    let reason = loop {
                        let proof_deadline = last_response.unwrap_or(initial_sent) + LEASE;
                        let deadline = recovery_deadline.unwrap_or(proof_deadline);
                        let now = proof_clock::now();
                        if !proof_clock::is_valid(now) || now >= deadline {
                            if recovery_deadline.is_none() {
                                stats.proof_expired(last_response.is_some());
                                recovery_deadline = Some(proof_deadline + RECOVERY_GRACE);
                                if candidate_race.is_none() {
                                    candidate_race = Some(dialer.race());
                                }
                                if proof_clock::is_valid(now) && now < recovery_deadline.unwrap() {
                                    continue;
                                }
                            }
                            conn.close(0u32.into(), b"presence expired");
                            break crate::diagnostics::SessionOutcome::Expired;
                        }
                        if peer.stopped.load(Ordering::Relaxed) || peer.inactive() {
                            conn.close(0u32.into(), b"presence inactive");
                            break crate::diagnostics::SessionOutcome::Inactive;
                        }
                        tokio::select! {
                            scheduled = interval.tick() => { stats.tick(scheduled); if observe_path(&conn, peer.trace, session_attempt, &mut path) { stats.report("path_changed"); } send_tracked_probe(&conn, &mut pending, &mut stats); },
                            _ = proof_timer.wait_until(deadline) => {},
                            _ = peer.wake.notified() => {
                                let epoch = peer.network_epoch.load(Ordering::Relaxed);
                                if epoch != session_epoch {
                                    session_epoch = epoch;
                                    if candidate_race.is_none() {
                                        candidate_race = Some(dialer.race());
                                    }
                                }
                                send_tracked_probe(&conn, &mut pending, &mut stats);
                            }
                            result = async { match &mut candidate_race { Some(future) => future.await, None => std::future::pending().await } } => {
                                candidate_race = None;
                                if let Some(ReadyCandidate { connection: replacement, proof_sent: sent, attempt: replacement_attempt, stats: mut replacement_stats }) = result {
                                    let allowed = trust.read().await;
                                    let min_sent = peer.min_sent.lock().unwrap();
                                    if !allowed.is_current(&id, &peer.session) || peer.stopped.load(Ordering::Relaxed) { replacement_stats.candidate_end(crate::diagnostics::BackupOutcome::Inactive); continue; }
                                    if !candidate_is_current(sent, min_sent.network, proof_clock::now()) {
                                        replacement_stats.candidate_end(crate::diagnostics::BackupOutcome::Stale);
                                        candidate_race = Some(dialer.race());
                                        continue;
                                    }
                                    stats.session_end(crate::diagnostics::SessionOutcome::Replaced);
                                    conn.close(0u32.into(), b"presence replaced");
                                    conn = replacement;
                                    path = None;
                                    last_response = Some(sent);
                                    recovery_deadline = None;
                                    session_attempt = replacement_attempt;
                                    replacement_stats.role = "active";
                                    stats = replacement_stats;
                                    session_epoch = peer.network_epoch.load(Ordering::Relaxed);
                                    pending.clear();
                                }
                            }
                            data = conn.read_datagram() => {
                                let Ok(data) = data else { break crate::diagnostics::SessionOutcome::Closed };
                                let allowed = trust.read().await;
                                if !allowed.is_current(&id, &peer.session) { break crate::diagnostics::SessionOutcome::Revoked; }
                                let Some(packet) = Packet::decode(&data) else { continue };
                                if packet.kind == MessageKind::Probe {
                                    stats.record(|s| s.ping_received += 1); if reply_ping(&conn, &packet.nonce, &info, TrustStatus::Paired).await { stats.record(|s| s.pong_queued += 1); }
                                    continue;
                                }
                                let Some(sent) = pending.remove(&packet.nonce) else { stats.record(|s| s.pong_unmatched += 1); continue };
                                stats.record(|s| { if sent >= s.started { s.max_rtt_ms = s.max_rtt_ms.max(sent.elapsed().as_millis() as u64); } });
                                let response = peer.accept_response(sent, &data);
                                stats.record_response(&response);
                                if response.is_ok() {
                                    if packet.kind == MessageKind::Unpaired { conn.close(0u32.into(), b"unpaired"); break crate::diagnostics::SessionOutcome::Revoked; }
                                    if packet.kind != MessageKind::Paired { continue; }
                                    let min_sent = peer.min_sent.lock().unwrap();
                                    if !peer.stopped.load(Ordering::Relaxed) && sent >= min_sent.resume {
                                        if sent >= min_sent.network { candidate_race = None; }
                                        stats.first_pong(sent);
                                        last_response = Some(last_response.map_or(sent, |previous| previous.max(sent)));
                                        recovery_deadline = None;
                                    }
                                }
                            }
                        }
                    };
                    stats.session_end(reason);
                    if let Some(future) = candidate_race.take() {
                        if let Some(ReadyCandidate {
                            connection: replacement,
                            proof_sent: sent,
                            attempt: replacement_attempt,
                            stats: mut replacement_stats,
                        }) = future.await
                        {
                            let allowed = trust.read().await;
                            let min_sent = peer.min_sent.lock().unwrap();
                            if !allowed.is_current(&id, &peer.session)
                                || peer.stopped.load(Ordering::Relaxed)
                            {
                                replacement_stats
                                    .candidate_end(crate::diagnostics::BackupOutcome::Inactive);
                                break 'sessions;
                            }
                            if !candidate_is_current(sent, min_sent.network, proof_clock::now()) {
                                replacement_stats
                                    .candidate_end(crate::diagnostics::BackupOutcome::Stale);
                                break 'sessions;
                            }
                            conn = replacement;
                            path = None;
                            last_response = Some(sent);
                            recovery_deadline = None;
                            session_attempt = replacement_attempt;
                            replacement_stats.role = "active";
                            stats = replacement_stats;
                            session_epoch = peer.network_epoch.load(Ordering::Relaxed);
                            interval.reset();
                            pending.clear();
                            continue 'sessions;
                        }
                    }
                    break 'sessions;
                }
            }
            if peer.stopped.load(Ordering::Relaxed) || peer.inactive() {
                break;
            }
            tokio::select! { _ = tokio::time::sleep(INTERVAL) => {}, _ = peer.wake.notified() => {} }
        }
        let allowed = trust.read().await;
        let mut probes = probes.lock().await;
        if probes
            .get(&id)
            .is_some_and(|current| Arc::ptr_eq(current, &peer))
        {
            if allowed.is_current(&id, &peer.session)
                && !peer.stopped.load(Ordering::Relaxed)
                && !peer.inactive()
            {
                drop(probes);
                continue;
            }
            peer.stopped.store(true, Ordering::Relaxed);
            probes.remove(&id);
        }
        break;
    }
}

async fn reply_ping(
    conn: &Connection,
    nonce: &Nonce,
    info: &RwLock<Option<DeviceInfo>>,
    status: TrustStatus,
) -> bool {
    let kind = match status {
        TrustStatus::Paired => {
            if let Some(info) = info.read().await.clone() {
                let Ok(json) = serde_json::to_vec(&info) else {
                    return false;
                };
                return conn
                    .send_datagram(presence_wire::encode(MessageKind::Paired, nonce, &json).into())
                    .is_ok();
            }
            MessageKind::Pending
        }
        TrustStatus::Pending => MessageKind::Pending,
        TrustStatus::Unpaired => MessageKind::Unpaired,
    };
    conn.send_datagram(presence_wire::encode(kind, nonce, &[]).into())
        .is_ok()
}

#[derive(Debug, PartialEq, Eq)]
enum PongRejection {
    Stopped,
    EpochFresh,
    EpochExpired,
    Expired,
    Invalid,
}

impl PeerProbeState {
    fn accept_response(
        &self,
        sent: ProofInstant,
        data: &[u8],
    ) -> std::result::Result<(), PongRejection> {
        let mut min_sent = self.min_sent.lock().unwrap();
        if self.stopped.load(Ordering::Relaxed) || self.session.is_revoked() {
            return Err(PongRejection::Stopped);
        }
        let now = proof_clock::now();
        if !min_sent.observe_clock(now) {
            self.status.send_replace(Status::default());
            self.network_epoch.fetch_add(1, Ordering::Relaxed);
            self.wake.notify_one();
            return Err(PongRejection::Expired);
        }
        let paired_response = data.first() == Some(&(MessageKind::Paired as u8));
        if sent < min_sent.resume || (!paired_response && sent < min_sent.network) {
            return Err(if proof_clock::is_fresh(sent, now, LEASE) {
                PongRejection::EpochFresh
            } else {
                PongRejection::EpochExpired
            });
        }
        if !proof_clock::is_fresh(sent, now, LEASE) {
            return Err(PongRejection::Expired);
        }
        let mut current = self.status.borrow().clone();
        if current
            .latest
            .is_some_and(|previous| sent < previous || (sent == previous && !paired_response))
        {
            return Err(PongRejection::Expired);
        }
        let packet = Packet::decode(data).ok_or(PongRejection::Invalid)?;
        match packet.kind {
            MessageKind::Paired if !packet.payload.is_empty() => {
                let Ok(info) = serde_json::from_slice::<DeviceInfo>(packet.payload) else {
                    return Err(PongRejection::Invalid);
                };
                if !valid_device_name(&info.name) || !valid_device_type(&info.device_type) {
                    return Err(PongRejection::Invalid);
                }
                current.proof = Some((sent, info));
                current.unpaired = None;
            }
            MessageKind::Pending if packet.payload.is_empty() => {
                current.proof = None;
                current.unpaired = None;
            }
            MessageKind::Unpaired if packet.payload.is_empty() => {
                current.proof = None;
                current.unpaired = Some(sent);
            }
            _ => return Err(PongRejection::Invalid),
        }
        current.latest = Some(sent);
        self.status.send_replace(current);
        Ok(())
    }
}

fn send_probe(conn: &Connection) -> Option<(Nonce, ProofInstant)> {
    let now = proof_clock::now();
    if !proof_clock::is_valid(now) {
        return None;
    }
    let nonce: Nonce = rand::random();
    conn.send_datagram(presence_wire::encode(MessageKind::Probe, &nonce, &[]).into())
        .ok()?;
    Some((nonce, now))
}

fn send_tracked_probe(
    conn: &Connection,
    pending: &mut HashMap<Nonce, ProofInstant>,
    stats: &mut ProbeStats,
) {
    let now = proof_clock::now();
    pending.retain(|_, sent| now.duration_since(*sent) < LEASE);
    let queued = if let Some((nonce, sent)) = send_probe(conn) {
        pending.insert(nonce, sent);
        true
    } else {
        false
    };
    stats.probe(queued);
}

#[cfg(test)]
#[path = "presence_backup_tests.rs"]
mod backup_tests;

#[cfg(test)]
#[path = "presence_events_tests.rs"]
mod event_tests;

#[cfg(test)]
#[path = "presence_event_pairing_tests.rs"]
mod event_pairing_tests;

#[cfg(test)]
#[path = "presence_tests.rs"]
mod tests;

#[cfg(test)]
#[path = "presence_test_support.rs"]
mod test_support;
