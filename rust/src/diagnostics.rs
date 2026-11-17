use crate::api::node::DiagnosticEvent;
use std::{
    collections::VecDeque,
    sync::{Mutex, OnceLock},
    time::{Instant, SystemTime, UNIX_EPOCH},
};

const CAPACITY: usize = 2000;
struct Collector {
    enabled: bool,
    generation: u64,
    events: VecDeque<DiagnosticEvent>,
}
static EVENTS: OnceLock<Mutex<Collector>> = OnceLock::new();
static ENABLED_WATCH: OnceLock<tokio::sync::watch::Sender<bool>> = OnceLock::new();
static SECRETS: OnceLock<Mutex<Vec<String>>> = OnceLock::new();
static STARTED: OnceLock<Instant> = OnceLock::new();

fn buffer() -> &'static Mutex<Collector> {
    EVENTS.get_or_init(|| {
        Mutex::new(Collector {
            enabled: cfg!(test),
            generation: 0,
            events: VecDeque::with_capacity(CAPACITY),
        })
    })
}

fn enabled_watch() -> &'static tokio::sync::watch::Sender<bool> {
    ENABLED_WATCH.get_or_init(|| tokio::sync::watch::channel(buffer().lock().unwrap().enabled).0)
}

pub(crate) fn state() -> (bool, u64) {
    let value = buffer().lock().unwrap();
    (value.enabled, value.generation)
}
pub(crate) fn enabled_changes() -> tokio::sync::watch::Receiver<bool> {
    enabled_watch().subscribe()
}
pub(crate) fn with_enabled(generation: u64, f: impl FnOnce()) {
    let value = buffer().lock().unwrap();
    if value.enabled && value.generation == generation {
        f();
    }
}

pub(crate) fn register_secret(secret: &str) {
    if secret.is_empty() {
        return;
    }
    let mut secrets = SECRETS
        .get_or_init(|| Mutex::new(Vec::new()))
        .lock()
        .unwrap();
    if !secrets.iter().any(|value| value == secret) {
        secrets.push(secret.to_owned());
    }
}

pub(crate) fn safe_error(message: &str) -> (Option<String>, bool) {
    let explicit_fields = crate::diagnostic_redact::sanitize(message);
    let filtered = explicit_fields != message;
    (Some(explicit_fields), filtered)
}

pub(crate) fn is_secret_value(value: &str) -> bool {
    SECRETS
        .get_or_init(|| Mutex::new(Vec::new()))
        .lock()
        .unwrap()
        .iter()
        .any(|secret| secret == value)
}

pub(crate) fn set_enabled(enabled: bool) {
    let changes = enabled_watch();
    let mut value = buffer().lock().unwrap();
    if value.enabled != enabled {
        value.enabled = enabled;
        value.generation += 1;
        changes.send_replace(enabled);
    }
}

fn append(events: &mut VecDeque<DiagnosticEvent>, event: DiagnosticEvent) {
    if events.len() == CAPACITY {
        events.pop_front();
    }
    events.push_back(event);
}

fn accepts(value: &Collector, generation: Option<u64>) -> bool {
    value.enabled && generation.is_none_or(|expected| expected == value.generation)
}

fn push_for_generation(event: DiagnosticEvent, generation: Option<u64>) {
    let mut value = buffer().lock().unwrap();
    if !accepts(&value, generation) {
        return;
    }
    log::warn!("vela_diag ts_ms={} mono_ms={} kind={} trace={} attempt={} elapsed_ms={} rtt_ms={} ping_failures={} relays_before={} relays_after={} details={}", event.timestamp_ms, event.monotonic_ms, event.kind, event.trace, event.attempt, event.elapsed_ms, event.rtt_ms, event.ping_failures, event.relays_before, event.relays_after, event.details);
    append(&mut value.events, event);
}

fn push(event: DiagnosticEvent) {
    push_for_generation(event, None);
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}
pub(crate) fn monotonic_ms() -> u64 {
    STARTED.get_or_init(Instant::now).elapsed().as_millis() as u64
}

pub(crate) fn network_changed() {
    push(DiagnosticEvent {
        details: String::new(),
        timestamp_ms: now_ms(),
        monotonic_ms: monotonic_ms(),
        kind: "network_changed".into(),
        trace: 0,
        attempt: 0,
        elapsed_ms: 0,
        rtt_ms: 0,
        ping_failures: 0,
        relays_before: 0,
        relays_after: 0,
    });
}

pub(crate) fn system_wake() {
    push(DiagnosticEvent {
        details: String::new(),
        timestamp_ms: now_ms(),
        monotonic_ms: monotonic_ms(),
        kind: "system_wake".into(),
        trace: 0,
        attempt: 0,
        elapsed_ms: 0,
        rtt_ms: 0,
        ping_failures: 0,
        relays_before: 0,
        relays_after: 0,
    });
}

pub(crate) enum DialOutcome {
    Connected,
    Failed,
    NetworkChanged,
    Timeout,
    Inactive,
}
pub(crate) enum SessionOutcome {
    Expired,
    Inactive,
    Closed,
    Revoked,
    Replaced,
}
pub(crate) enum BackupOutcome {
    Expired,
    Closed,
    Inactive,
    Revoked,
    Superseded,
    Stale,
}
#[derive(Clone, Copy, PartialEq, Eq)]
pub(crate) enum PathKind {
    Ip,
    Relay,
    Unknown,
}

pub(crate) fn clock() -> (u64, u64) {
    (now_ms(), monotonic_ms())
}

pub(crate) fn dial_start_with_peer(
    trace: u64,
    attempt: u64,
    relays: u32,
    timestamp: (u64, u64),
    peer: &str,
    generation: u64,
) {
    let details = serde_json::json!({ "peer_id": peer }).to_string();
    push_for_generation(
        DiagnosticEvent {
            details,
            timestamp_ms: timestamp.0,
            monotonic_ms: timestamp.1,
            kind: "dial_start".into(),
            trace,
            attempt,
            elapsed_ms: 0,
            rtt_ms: 0,
            ping_failures: 0,
            relays_before: relays,
            relays_after: relays,
        },
        Some(generation),
    );
}

pub(crate) fn dial_setup_done_for_generation(
    trace: u64,
    attempt: u64,
    elapsed_ms: u64,
    timestamp: (u64, u64),
    generation: u64,
) {
    push_for_generation(
        DiagnosticEvent {
            details: String::new(),
            timestamp_ms: timestamp.0,
            monotonic_ms: timestamp.1,
            kind: "dial_setup_done".into(),
            trace,
            attempt,
            elapsed_ms,
            rtt_ms: 0,
            ping_failures: 0,
            relays_before: 0,
            relays_after: 0,
        },
        Some(generation),
    );
}

pub(crate) fn dial_for_generation(
    outcome: DialOutcome,
    trace: u64,
    attempt: u64,
    elapsed_ms: u64,
    before: u32,
    after: u32,
    details: String,
    generation: u64,
) {
    let kind = match outcome {
        DialOutcome::Connected => "dial_connected",
        DialOutcome::Failed => "dial_failed",
        DialOutcome::NetworkChanged => "dial_network_changed",
        DialOutcome::Timeout => "dial_timeout",
        DialOutcome::Inactive => "dial_inactive",
    };
    push_for_generation(
        DiagnosticEvent {
            details,
            timestamp_ms: now_ms(),
            monotonic_ms: monotonic_ms(),
            kind: kind.into(),
            trace,
            attempt,
            elapsed_ms,
            rtt_ms: 0,
            ping_failures: 0,
            relays_before: before,
            relays_after: after,
        },
        Some(generation),
    );
}

pub(crate) fn first_pong_for_generation(
    trace: u64,
    attempt: u64,
    elapsed_ms: u64,
    rtt_ms: u64,
    generation: u64,
) {
    push_for_generation(
        DiagnosticEvent {
            details: String::new(),
            timestamp_ms: now_ms(),
            monotonic_ms: monotonic_ms(),
            kind: if attempt == 0 {
                "first_pong_inbound"
            } else {
                "first_pong"
            }
            .into(),
            trace,
            attempt,
            elapsed_ms,
            rtt_ms,
            ping_failures: 0,
            relays_before: 0,
            relays_after: 0,
        },
        Some(generation),
    );
}

fn ping_kind(attempt: u64, queued: bool) -> &'static str {
    match (attempt == 0, queued) {
        (true, true) => "first_ping_inbound_queued",
        (true, false) => "first_ping_inbound_failed",
        (false, true) => "first_ping_queued",
        (false, false) => "first_ping_failed",
    }
}

pub(crate) fn first_ping_for_generation(
    trace: u64,
    attempt: u64,
    queued: bool,
    elapsed_ms: u64,
    generation: u64,
) {
    push_for_generation(
        DiagnosticEvent {
            details: String::new(),
            timestamp_ms: now_ms(),
            monotonic_ms: monotonic_ms(),
            kind: ping_kind(attempt, queued).into(),
            trace,
            attempt,
            elapsed_ms,
            rtt_ms: 0,
            ping_failures: 0,
            relays_before: 0,
            relays_after: 0,
        },
        Some(generation),
    );
}

fn session_kind(outcome: SessionOutcome) -> &'static str {
    match outcome {
        SessionOutcome::Expired => "session_expired",
        SessionOutcome::Inactive => "session_inactive",
        SessionOutcome::Closed => "session_closed",
        SessionOutcome::Revoked => "session_revoked",
        SessionOutcome::Replaced => "session_replaced",
    }
}

pub(crate) fn session_end_for_generation(
    outcome: SessionOutcome,
    trace: u64,
    attempt: u64,
    elapsed_ms: u64,
    ping_failures: u64,
    generation: u64,
) {
    push_for_generation(
        DiagnosticEvent {
            details: String::new(),
            timestamp_ms: now_ms(),
            monotonic_ms: monotonic_ms(),
            kind: session_kind(outcome).into(),
            trace,
            attempt,
            elapsed_ms,
            rtt_ms: 0,
            ping_failures,
            relays_before: 0,
            relays_after: 0,
        },
        Some(generation),
    );
}

pub(crate) fn session_proof_expired_for_generation(
    trace: u64,
    attempt: u64,
    elapsed_ms: u64,
    had_proof: bool,
    generation: u64,
) {
    let kind = if had_proof {
        "session_proof_expired"
    } else {
        "session_unproven"
    };
    push_for_generation(
        DiagnosticEvent {
            details: String::new(),
            timestamp_ms: now_ms(),
            monotonic_ms: monotonic_ms(),
            kind: kind.into(),
            trace,
            attempt,
            elapsed_ms,
            rtt_ms: 0,
            ping_failures: 0,
            relays_before: 0,
            relays_after: 0,
        },
        Some(generation),
    );
}

pub(crate) fn backup_end_for_generation(
    outcome: BackupOutcome,
    trace: u64,
    attempt: u64,
    elapsed_ms: u64,
    generation: u64,
) {
    let kind = match outcome {
        BackupOutcome::Expired => "backup_expired",
        BackupOutcome::Closed => "backup_closed",
        BackupOutcome::Inactive => "backup_inactive",
        BackupOutcome::Revoked => "backup_revoked",
        BackupOutcome::Superseded => "backup_superseded",
        BackupOutcome::Stale => "backup_stale",
    };
    push_for_generation(
        DiagnosticEvent {
            details: String::new(),
            timestamp_ms: now_ms(),
            monotonic_ms: monotonic_ms(),
            kind: kind.into(),
            trace,
            attempt,
            elapsed_ms,
            rtt_ms: 0,
            ping_failures: 0,
            relays_before: 0,
            relays_after: 0,
        },
        Some(generation),
    );
}

pub(crate) fn session_path_details(
    path: PathKind,
    trace: u64,
    attempt: u64,
    details: String,
    generation: u64,
) {
    let kind = match path {
        PathKind::Ip => "path_ip",
        PathKind::Relay => "path_relay",
        PathKind::Unknown => "path_unknown",
    };
    push_for_generation(
        DiagnosticEvent {
            details,
            timestamp_ms: now_ms(),
            monotonic_ms: monotonic_ms(),
            kind: kind.into(),
            trace,
            attempt,
            elapsed_ms: 0,
            rtt_ms: 0,
            ping_failures: 0,
            relays_before: 0,
            relays_after: 0,
        },
        Some(generation),
    );
}

pub(crate) fn home_relay_snapshot(details: String, known: u32, connected: u32, generation: u64) {
    push_for_generation(
        DiagnosticEvent {
            details,
            timestamp_ms: now_ms(),
            monotonic_ms: monotonic_ms(),
            kind: "home_relay_snapshot".into(),
            trace: 0,
            attempt: 0,
            elapsed_ms: 0,
            rtt_ms: 0,
            ping_failures: 0,
            relays_before: known,
            relays_after: connected,
        },
        Some(generation),
    );
}

pub(crate) fn events() -> Vec<DiagnosticEvent> {
    buffer().lock().unwrap().events.iter().cloned().collect()
}
pub(crate) fn clear() {
    buffer().lock().unwrap().events.clear();
}

#[cfg(test)]
#[path = "diagnostics_tests.rs"]
mod tests;
