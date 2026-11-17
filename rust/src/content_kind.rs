#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum ContentKind {
    File,
    Text,
    TypedText,
    Image,
    ClipboardFile,
    Batch,
}

impl ContentKind {
    pub(crate) fn parse(value: &str) -> Option<Self> {
        Some(match value {
            "file" => Self::File,
            "text" => Self::Text,
            "typed_text" => Self::TypedText,
            "image" => Self::Image,
            "clipboard_file" => Self::ClipboardFile,
            "batch" => Self::Batch,
            _ => return None,
        })
    }

    pub(crate) fn wire_name(self) -> &'static str {
        match self {
            Self::File => "file",
            Self::Text => "text",
            Self::TypedText => "typed_text",
            Self::Image => "image",
            Self::ClipboardFile => "clipboard_file",
            Self::Batch => "batch",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::ContentKind;

    #[test]
    fn wire_names_round_trip_without_accepting_history_or_pairing_types() {
        for value in [
            "file",
            "text",
            "typed_text",
            "image",
            "clipboard_file",
            "batch",
        ] {
            assert_eq!(ContentKind::parse(value).unwrap().wire_name(), value);
        }
        assert_eq!(ContentKind::parse("folder_archive"), None);
        assert_eq!(ContentKind::parse("pair_mobile"), None);
        assert_eq!(ContentKind::parse(""), None);
    }
}
