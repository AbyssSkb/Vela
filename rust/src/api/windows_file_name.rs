pub(super) fn valid_component(name: &str) -> bool {
    if name.is_empty()
        || name.ends_with(['.', ' '])
        || name.contains(['<', '>', ':', '"', '/', '\\', '|', '?', '*'])
        || name.chars().any(char::is_control)
    {
        return false;
    }
    let stem = name.split('.').next().unwrap().trim_end().to_uppercase();
    !matches!(
        stem.as_str(),
        "CON" | "PRN" | "AUX" | "NUL" | "CONIN$" | "CONOUT$"
    ) && !["COM", "LPT"].iter().any(|prefix| {
        stem.strip_prefix(prefix).is_some_and(|suffix| {
            matches!(
                suffix,
                "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" | "¹" | "²" | "³"
            )
        })
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_device_aliases_streams_and_normalized_names() {
        for name in [
            "CON",
            "con.txt",
            "NUL .txt",
            "COM1.log",
            "LPT²",
            "CONIN$",
            "a:stream",
            "file.",
            "file ",
            "bad?name",
            "bad\0name",
            "..",
            ".",
        ] {
            assert!(!valid_component(name), "accepted {name:?}");
        }
    }

    #[test]
    fn accepts_ordinary_and_unicode_names() {
        for name in [
            "file.txt",
            "报告.pdf",
            ".hidden",
            "COM10",
            "console",
            "a b",
            "😀.png",
        ] {
            assert!(valid_component(name), "rejected {name:?}");
        }
    }
}
