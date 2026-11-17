use super::{DeviceInfo, Request, TransferOffer};
use crate::content_kind::ContentKind;
use crate::protocol::RequestHeader;
use anyhow::{bail, Result};

pub(super) fn valid_file_name(name: &str) -> bool {
    let valid =
        !name.is_empty() && name != "." && name != ".." && !name.contains(['/', '\\', '\0']);
    #[cfg(windows)]
    let valid = valid && crate::api::windows_file_name::valid_component(name);
    valid
}

pub(crate) fn valid_device_name(name: &str) -> bool {
    !name.trim().is_empty() && name.len() <= 256 && !name.chars().any(char::is_control)
}

pub(crate) fn valid_device_type(value: &str) -> bool {
    ["mobile", "tablet", "desktop", "other"].contains(&value)
}
impl Request {
    pub(super) fn from_header(header: RequestHeader, pairing: bool) -> Result<Self> {
        if pairing {
            let device_type = header
                .kind
                .strip_prefix("pair_")
                .filter(|value| valid_device_type(value))
                .ok_or_else(|| anyhow::anyhow!("invalid pairing information"))?;
            if !valid_device_name(&header.name) || header.size != 0 {
                bail!("invalid pairing information")
            }
            return Ok(Self::Pairing(DeviceInfo {
                name: header.name,
                device_type: device_type.to_owned(),
            }));
        }
        let kind = ContentKind::parse(&header.kind)
            .ok_or_else(|| anyhow::anyhow!("invalid transfer information"))?;
        if kind == ContentKind::Batch {
            if header.files.len() < 2
                || header.files.len() > 100
                || header.files.iter().any(|file| !valid_file_name(&file.name))
                || header
                    .files
                    .iter()
                    .try_fold(0u64, |sum, file| sum.checked_add(file.size))
                    != Some(header.size)
            {
                bail!("invalid batch transfer")
            }
        } else if !valid_file_name(&header.name)
            || (kind == ContentKind::TypedText && header.size > 1024 * 1024)
        {
            bail!("invalid transfer information")
        }
        Ok(Self::Transfer(TransferOffer {
            name: header.name,
            size: header.size,
            kind,
            files: header.files,
        }))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::TransferFileHeader;

    fn header(kind: &str) -> RequestHeader {
        RequestHeader {
            name: "Phone".into(),
            size: 0,
            kind: kind.into(),
            files: Vec::new(),
        }
    }

    #[test]
    fn pairing_is_decoded_once_and_cannot_enter_the_transfer_protocol() {
        let request = Request::from_header(header("pair_mobile"), true).unwrap();
        assert!(
            matches!(request, Request::Pairing(info) if info.name == "Phone" && info.device_type == "mobile")
        );
        assert!(Request::from_header(header("pair_mobile"), false).is_err());
        assert!(Request::from_header(header("file"), true).is_err());
    }

    #[test]
    fn transfer_decode_keeps_content_type_and_size_validation() {
        let request = Request::from_header(header("typed_text"), false).unwrap();
        assert!(
            matches!(request, Request::Transfer(offer) if offer.kind == ContentKind::TypedText)
        );
        let mut large = header("typed_text");
        large.size = 1024 * 1024 + 1;
        assert!(Request::from_header(large, false).is_err());
    }

    #[test]
    fn batch_decode_rejects_overflowing_file_sizes() {
        let mut batch = header("batch");
        batch.files = vec![
            TransferFileHeader {
                name: "one".into(),
                size: u64::MAX,
            },
            TransferFileHeader {
                name: "two".into(),
                size: 1,
            },
        ];
        assert!(Request::from_header(batch, false).is_err());
    }

    #[cfg(windows)]
    #[test]
    fn rejects_windows_device_names_and_alternate_data_streams() {
        for name in ["CON.txt", "nul", "LPT1", "file:stream", "file.", "file "] {
            let mut offer = header("file");
            offer.name = name.into();
            assert!(
                Request::from_header(offer, false).is_err(),
                "accepted {name:?}"
            );
        }
    }

    #[cfg(not(windows))]
    #[test]
    fn preserves_names_which_are_ordinary_on_unix() {
        for name in ["CON.txt", "file:stream", "file.", "file "] {
            let mut offer = header("file");
            offer.name = name.into();
            assert!(
                Request::from_header(offer, false).is_ok(),
                "rejected {name:?}"
            );
        }
    }
}
