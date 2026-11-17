use super::*;

pub(super) fn accept_response(
    current: Option<ProofInstant>,
    sent: ProofInstant,
    now: ProofInstant,
) -> Option<ProofInstant> {
    if !proof_clock::is_fresh(sent, now, LEASE) {
        current
    } else {
        Some(current.map_or(sent, |old| old.max(sent)))
    }
}

pub(super) fn publish_response(peer: &PeerProbeState, sent: ProofInstant, json: &[u8]) -> bool {
    let mut data = vec![2; 9];
    data.extend_from_slice(json);
    peer.accept_response(sent, &data).is_ok()
}
