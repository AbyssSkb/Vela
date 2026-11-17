use std::fmt::Display;

#[derive(Clone, Copy)]
pub(crate) enum FailureCode {
    Cancelled,
    Declined,
    SaveFailed,
    PairingDeclined,
}

impl FailureCode {
    pub(crate) fn error(self, description: impl Display) -> anyhow::Error {
        let code = match self {
            Self::Cancelled => "cancelled",
            Self::Declined => "declined",
            Self::SaveFailed => "save_failed",
            Self::PairingDeclined => "pairing_declined",
        };
        // The bridge transports anyhow text; only this prefix is a caller contract.
        anyhow::anyhow!("[vela:{code}] {description}")
    }
}

#[cfg(test)]
mod tests {
    use super::FailureCode;

    #[test]
    fn machine_codes_do_not_depend_on_the_description() {
        for (kind, code) in [
            (FailureCode::Cancelled, "cancelled"),
            (FailureCode::Declined, "declined"),
            (FailureCode::SaveFailed, "save_failed"),
            (FailureCode::PairingDeclined, "pairing_declined"),
        ] {
            assert_eq!(
                kind.error("changed wording").to_string(),
                format!("[vela:{code}] changed wording")
            );
        }
    }
}
