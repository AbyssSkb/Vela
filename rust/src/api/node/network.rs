use iroh::{Endpoint, Watcher};
use std::future::Future;
use tokio::sync::watch;

pub(super) fn spawn_home_relay_diagnostics(
    endpoint: &Endpoint,
) -> tokio::task::JoinHandle<Option<()>> {
    let mut watcher = endpoint.home_relay_status();
    let closed = endpoint.closed();
    let local_id = endpoint.id().to_string();
    let mut enabled_changes = crate::diagnostics::enabled_changes();
    tokio::spawn(closed.run_until(async move {
        let mut previous: Option<(u64, String)> = None;
        loop {
            let (enabled, generation) = crate::diagnostics::state();
            if enabled {
                let statuses = watcher.get();
                let connected = statuses
                    .iter()
                    .filter(|status| status.is_connected())
                    .count() as u32;
                let relays: Vec<_> = statuses
                    .iter()
                    .map(|status| {
                        let reason = status.auth_denied_reason();
                        let error = status.last_error();
                        let reason_is_secret =
                            reason.is_some_and(crate::diagnostics::is_secret_value);
                        let (last_error, error_filtered) = if reason_is_secret {
                            (None, true)
                        } else {
                            error.map_or((None, false), |error| {
                                crate::diagnostics::safe_error(&format!("{error:#}"))
                            })
                        };
                        let error_category = if reason_is_secret {
                            error.map(|_| "relay connection error".to_owned())
                        } else {
                            error
                                .and_then(|error| {
                                    crate::diagnostics::safe_error(&format!("{error}")).0
                                })
                                .or_else(|| error.map(|_| "relay connection error".to_owned()))
                        };
                        let (auth_reason, auth_reason_filtered) = if reason_is_secret {
                            (None, true)
                        } else {
                            reason.map_or((None, false), crate::diagnostics::safe_error)
                        };
                        serde_json::json!({
                            "url": status.url().to_string(),
                            "connected": status.is_connected(),
                            "last_error": last_error,
                            "error_category": error_category,
                            "error_filtered": error_filtered,
                            "auth_denied": reason.is_some(),
                            "auth_denied_reason": auth_reason,
                            "auth_reason_filtered": auth_reason_filtered,
                        })
                    })
                    .collect();
                let details =
                    serde_json::json!({ "local_endpoint_id": local_id, "home_relays": relays })
                        .to_string();
                if previous
                    .as_ref()
                    .is_none_or(|(last_generation, last_details)| {
                        *last_generation != generation || *last_details != details
                    })
                {
                    crate::diagnostics::home_relay_snapshot(
                        details.clone(),
                        statuses.len() as u32,
                        connected,
                        generation,
                    );
                    previous = Some((generation, details));
                }
            } else {
                previous = None;
            }
            tokio::select! {
                changed = enabled_changes.changed() => if changed.is_err() { break; },
                changed = watcher.updated(), if enabled => if changed.is_err() { break; },
            }
        }
    }))
}

pub(super) async fn run_network_change_worker<F, Fut, Closed>(
    mut changes: watch::Receiver<u64>,
    closed: Closed,
    mut notify: F,
) where
    F: FnMut() -> Fut,
    Fut: Future<Output = ()>,
    Closed: Future<Output = ()>,
{
    tokio::pin!(closed);
    loop {
        tokio::select! {
            _ = &mut closed => break,
            changed = changes.changed() => if changed.is_err() { break; },
        }
        loop {
            tokio::select! {
                _ = &mut closed => return,
                result = tokio::time::timeout(std::time::Duration::from_secs(1), notify()) => {
                    if result.is_ok() { break; }
                    // The next attempt covers every network change seen so far.
                    changes.borrow_and_update();
                },
            }
        }
    }
}
