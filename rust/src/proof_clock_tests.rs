use super::*;

#[tokio::test]
async fn deadline_timer_can_be_cancelled_and_reused() {
    let mut timer = ProofTimer::new();
    let deadline = now() + Duration::from_millis(100);
    assert!(
        tokio::time::timeout(Duration::from_millis(10), timer.wait_until(deadline))
            .await
            .is_err()
    );
    tokio::time::timeout(Duration::from_secs(1), timer.wait_until(deadline))
        .await
        .unwrap();
    assert!(now() >= deadline);
}

#[tokio::test]
async fn deadline_timer_runs_in_a_spawned_task() {
    tokio::spawn(async {
        let mut timer = ProofTimer::new();
        timer.wait_until(now() + Duration::from_millis(5)).await;
    })
    .await
    .unwrap();
}

#[tokio::test]
async fn rearming_a_timer_does_not_report_its_old_expiry() {
    let mut timer = ProofTimer::new();
    let first = now() + Duration::from_millis(30);
    assert!(
        tokio::time::timeout(Duration::from_millis(5), timer.wait_until(first))
            .await
            .is_err()
    );
    tokio::time::sleep(Duration::from_millis(50)).await;
    let second = now() + Duration::from_millis(100);
    assert!(
        tokio::time::timeout(Duration::from_millis(20), timer.wait_until(second))
            .await
            .is_err()
    );
    tokio::time::timeout(Duration::from_secs(1), timer.wait_until(second))
        .await
        .unwrap();
    assert!(now() >= second);
}

#[test]
fn sleep_time_expires_proof_when_uptime_does_not_advance() {
    let sent_boot = now();
    let lease = Duration::from_millis(2500);
    let unchanged_uptime = sent_boot;
    let resumed_boot = sent_boot + Duration::from_secs(30);
    assert!(is_fresh(sent_boot, unchanged_uptime, lease));
    assert!(!is_fresh(sent_boot, resumed_boot, lease));
}

#[test]
fn timestamps_cannot_be_fresh_before_they_were_sent() {
    let current = now();
    assert!(!is_fresh(
        current + Duration::from_secs(1),
        current,
        Duration::from_secs(2)
    ));
}

#[test]
fn serialization_uses_the_same_monotonic_origin() {
    let sent = now();
    let deadline = sent + Duration::from_secs(2);
    assert!(as_nanos(deadline) > now_ns());
}

#[cfg(target_os = "android")]
#[test]
fn failed_clock_and_overflow_never_produce_a_fresh_proof() {
    let invalid = ProofInstant(u64::MAX);
    assert!(!is_valid(invalid - Duration::from_secs(1)));
    assert!(!is_fresh(invalid, ProofInstant(1), Duration::from_secs(1)));
    assert!(!is_fresh(
        ProofInstant(u64::MAX - 1),
        ProofInstant(u64::MAX - 1),
        Duration::from_nanos(2)
    ));
}
