use serde::{Deserialize, Serialize};

pub(crate) mod alpn {
    pub(crate) const TRANSFER: &[u8] = b"vela/file/3";
    pub(crate) const PAIRING: &[u8] = b"vela/pair/2";
    pub(crate) const PRESENCE: &[u8] = b"vela/presence/2";
}
pub(crate) const MAX_HEADER: usize = 16 * 1024;
pub(crate) const PAIRING_COMPLETE: u32 = 86;

#[derive(Serialize, Deserialize)]
pub(crate) struct RequestHeader {
    pub(crate) name: String,
    pub(crate) size: u64,
    pub(crate) kind: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub(crate) files: Vec<TransferFileHeader>,
}

#[derive(Clone, Serialize, Deserialize)]
pub(crate) struct TransferFileHeader {
    pub(crate) name: String,
    pub(crate) size: u64,
}

pub(crate) mod presence {
    pub(crate) const NONCE_LEN: usize = 8;
    const HEADER_LEN: usize = 1 + NONCE_LEN;
    pub(crate) type Nonce = [u8; NONCE_LEN];

    #[derive(Clone, Copy, Debug, PartialEq, Eq)]
    #[repr(u8)]
    pub(crate) enum MessageKind {
        Probe = 1,
        Paired = 2,
        Pending = 3,
        Unpaired = 4,
    }

    pub(crate) struct Packet<'a> {
        pub(crate) kind: MessageKind,
        pub(crate) nonce: Nonce,
        pub(crate) payload: &'a [u8],
    }

    impl<'a> Packet<'a> {
        pub(crate) fn decode(data: &'a [u8]) -> Option<Self> {
            let kind = match *data.first()? {
                1 if data.len() == HEADER_LEN => MessageKind::Probe,
                2 => MessageKind::Paired,
                3 => MessageKind::Pending,
                4 => MessageKind::Unpaired,
                _ => return None,
            };
            Some(Self {
                kind,
                nonce: data.get(1..HEADER_LEN)?.try_into().ok()?,
                payload: &data[HEADER_LEN..],
            })
        }
    }

    pub(crate) fn encode(kind: MessageKind, nonce: &Nonce, payload: &[u8]) -> Vec<u8> {
        let mut packet = Vec::with_capacity(HEADER_LEN + payload.len());
        packet.push(kind as u8);
        packet.extend_from_slice(nonce);
        packet.extend_from_slice(payload);
        packet
    }

    #[cfg(test)]
    mod tests {
        use super::*;

        #[test]
        fn packets_keep_wire_tags_nonce_and_payload() {
            let nonce = [7; NONCE_LEN];
            for (kind, tag, payload) in [
                (MessageKind::Probe, 1, b"".as_slice()),
                (MessageKind::Paired, 2, b"{}".as_slice()),
                (MessageKind::Pending, 3, b"".as_slice()),
                (MessageKind::Unpaired, 4, b"".as_slice()),
            ] {
                let encoded = encode(kind, &nonce, payload);
                assert_eq!(
                    encoded,
                    [vec![tag], nonce.to_vec(), payload.to_vec()].concat()
                );
                let decoded = Packet::decode(&encoded).unwrap();
                assert_eq!(decoded.kind, kind);
                assert_eq!(decoded.nonce, nonce);
                assert_eq!(decoded.payload, payload);
            }
        }

        #[test]
        fn envelope_rejects_short_unknown_and_oversized_probes() {
            assert!(Packet::decode(&[]).is_none());
            assert!(Packet::decode(&[2; HEADER_LEN - 1]).is_none());
            assert!(Packet::decode(&[5; HEADER_LEN]).is_none());
            assert!(Packet::decode(&[1; HEADER_LEN + 1]).is_none());
            // Payload validation belongs to the response handler after nonce matching.
            assert!(Packet::decode(&[3; HEADER_LEN + 1]).is_some());
            assert!(Packet::decode(&[4; HEADER_LEN + 1]).is_some());
        }
    }
}
