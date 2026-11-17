use super::*;

#[test]
fn buffer_keeps_latest_events_in_order_and_is_bounded() {
    let mut events = VecDeque::new();
    for trace in 0..(CAPACITY as u64 + 2) {
        append(
            &mut events,
            DiagnosticEvent {
                details: String::new(),
                timestamp_ms: 1,
                monotonic_ms: 1,
                kind: "first_pong".into(),
                trace,
                attempt: 0,
                elapsed_ms: 2,
                rtt_ms: 1,
                ping_failures: 0,
                relays_before: 0,
                relays_after: 0,
            },
        );
    }
    assert_eq!(events.len(), CAPACITY);
    assert_eq!(events.front().unwrap().trace, 2);
    assert_eq!(events.back().unwrap().trace, CAPACITY as u64 + 1);
}

#[test]
fn ping_event_distinguishes_direction_and_queue_failure() {
    assert_eq!(ping_kind(0, true), "first_ping_inbound_queued");
    assert_eq!(ping_kind(0, false), "first_ping_inbound_failed");
    assert_eq!(ping_kind(1, true), "first_ping_queued");
    assert_eq!(ping_kind(1, false), "first_ping_failed");
}

#[test]
fn replacement_is_distinct_from_a_closed_session() {
    assert_eq!(session_kind(SessionOutcome::Replaced), "session_replaced");
}

#[test]
fn error_protection_keeps_actual_errors_even_if_token_is_short() {
    register_secret("1");
    let (message, filtered) = safe_error("proxy http://user:pass@192.0.2.10:8080 refused");
    let message = message.unwrap();
    assert!(filtered && message.contains("192.0.2.10:8080"));
    assert!(!message.contains("user") && !message.contains("pass"));
    for original in ["HTTP 401", "could not reach 192.0.2.10:8080"] {
        let (message, filtered) = safe_error(original);
        assert!(!filtered);
        assert_eq!(message.as_deref(), Some(original));
    }
}

#[test]
fn disabled_or_old_generation_events_are_not_recorded() {
    let mut value = Collector {
        enabled: true,
        generation: 3,
        events: VecDeque::new(),
    };
    assert!(accepts(&value, Some(3)));
    assert!(!accepts(&value, Some(2)));
    value.enabled = false;
    assert!(!accepts(&value, Some(3)));
    value.enabled = true;
    value.generation = 5;
    assert!(!accepts(&value, Some(3)));
    assert!(accepts(&value, Some(5)));
}

#[test]
fn diagnostic_switch_stops_recording_and_keeps_previous_events() {
    const CHILD: &str = "VELA_DIAGNOSTIC_SWITCH_TEST_CHILD";
    if std::env::var_os(CHILD).is_none() {
        let result = std::process::Command::new(std::env::current_exe().unwrap())
            .args([
                "--exact",
                "diagnostics::tests::diagnostic_switch_stops_recording_and_keeps_previous_events",
            ])
            .env(CHILD, "1")
            .output()
            .unwrap();
        assert!(
            result.status.success(),
            "isolated diagnostic switch test failed: {}",
            String::from_utf8_lossy(&result.stderr)
        );
        return;
    }
    clear();
    set_enabled(true);
    network_changed();
    assert_eq!(events().len(), 1);
    let old_generation = state().1;
    set_enabled(false);
    network_changed();
    assert_eq!(
        events().len(),
        1,
        "disabling must retain old events and reject new ones"
    );
    set_enabled(true);
    push_for_generation(
        DiagnosticEvent {
            details: String::new(),
            timestamp_ms: 0,
            monotonic_ms: 0,
            kind: "stale".into(),
            trace: 0,
            attempt: 0,
            elapsed_ms: 0,
            rtt_ms: 0,
            ping_failures: 0,
            relays_before: 0,
            relays_after: 0,
        },
        Some(old_generation),
    );
    assert_eq!(
        events().len(),
        1,
        "a previous recording window cannot leak into a new one"
    );
    network_changed();
    assert_eq!(events().len(), 2);
}
