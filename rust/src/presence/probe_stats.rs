use std::{
    sync::atomic::{AtomicU64, Ordering},
    time::{Duration, Instant},
};

use crate::proof_clock::{self, ProofInstant};

use super::PongRejection;

const STATS_REPORT_INTERVAL: Duration = Duration::from_secs(60);
static NEXT_SESSION: AtomicU64 = AtomicU64::new(1);

pub(super) struct ProbeStats {
    id: u64,
    trace: u64,
    attempt: u64,
    pub(super) role: &'static str,
    generation: u64,
    started: ProofInstant,
    pub(super) last_report: Instant,
    pub(super) ping_attempts: u64,
    pub(super) ping_queued: u64,
    ping_received: u64,
    pong_queued: u64,
    pub(super) pong_valid: u64,
    pub(super) pong_unmatched: u64,
    pub(super) pong_rejected: u64,
    pub(super) reject_stopped: u64,
    pub(super) reject_epoch_fresh: u64,
    pub(super) reject_epoch_expired: u64,
    pub(super) reject_expired: u64,
    pub(super) reject_invalid: u64,
    pub(super) reject_owner: u64,
    pub(super) max_rtt_ms: u64,
    pub(super) max_tick_lag_ms: u64,
    first_ping_reported: bool,
    first_pong_reported: bool,
}

impl ProbeStats {
    pub(super) fn set_trace(&mut self, trace: u64) -> bool {
        if self.trace == trace {
            return false;
        }
        self.trace = trace;
        self.first_ping_reported = false;
        self.first_pong_reported = false;
        true
    }

    pub(super) fn mark_active(&mut self) {
        self.role = "active";
    }

    pub(super) fn received_probe(&mut self) {
        self.record(|stats| stats.ping_received += 1);
    }

    pub(super) fn queued_response(&mut self) {
        self.record(|stats| stats.pong_queued += 1);
    }

    pub(super) fn unmatched_response(&mut self) {
        self.record(|stats| stats.pong_unmatched += 1);
    }

    pub(super) fn rejected_owner(&mut self) {
        self.record(|stats| {
            stats.pong_rejected += 1;
            stats.reject_owner += 1;
        });
    }

    pub(super) fn matched_response(&mut self, sent: ProofInstant) {
        self.record(|stats| {
            if sent >= stats.started {
                stats.max_rtt_ms = stats.max_rtt_ms.max(sent.elapsed().as_millis() as u64);
            }
        });
    }

    pub(super) fn new(trace: u64, attempt: u64, role: &'static str) -> Self {
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

    pub(super) fn recording_for(&mut self, enabled: bool, generation: u64) -> bool {
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

    pub(super) fn probe_for(&mut self, queued: bool, enabled: bool, generation: u64) -> bool {
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

    pub(super) fn probe(&mut self, queued: bool) {
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

    pub(super) fn first_pong(&mut self, sent: ProofInstant) {
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

    pub(super) fn session_end(&mut self, outcome: crate::diagnostics::SessionOutcome) {
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

    pub(super) fn proof_expired(&mut self) {
        if !self.recording() {
            return;
        }
        crate::diagnostics::session_proof_expired_for_generation(
            self.trace,
            self.attempt,
            self.started.elapsed().as_millis() as u64,
            true,
            self.generation,
        );
    }

    pub(super) fn candidate_end(&mut self, outcome: crate::diagnostics::BackupOutcome) {
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

    pub(super) fn tick(&mut self, scheduled: tokio::time::Instant) {
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

    pub(super) fn record_response(&mut self, response: &std::result::Result<(), PongRejection>) {
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

    pub(super) fn report(&mut self, phase: &str) {
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
