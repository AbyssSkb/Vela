const HIDDEN: &[u8] = b"[REDACTED]";

fn hex(byte: u8) -> Option<u8> {
    match byte {
        b'0'..=b'9' => Some(byte - b'0'),
        b'a'..=b'f' => Some(byte - b'a' + 10),
        b'A'..=b'F' => Some(byte - b'A' + 10),
        _ => None,
    }
}

fn decoded_byte(input: &[u8], at: usize) -> (u8, usize) {
    if input[at] == b'%' && at + 2 < input.len() {
        if let (Some(high), Some(low)) = (hex(input[at + 1]), hex(input[at + 2])) {
            return ((high << 4) | low, 3);
        }
    }
    (input[at], 1)
}

fn redact_userinfo(input: &[u8]) -> Vec<u8> {
    let mut result = Vec::with_capacity(input.len());
    let mut at = 0;
    while at < input.len() {
        if input[at..].starts_with(b"://") {
            result.extend_from_slice(b"://");
            at += 3;
            let end = (at..input.len())
                .find(|&i| {
                    input[i].is_ascii_whitespace()
                        || matches!(
                            input[i],
                            b'/' | b'?' | b'#' | b'\'' | b'"' | b'<' | b'>' | b')' | b','
                        )
                })
                .unwrap_or(input.len());
            if let Some(offset) = input[at..end].iter().rposition(|&b| b == b'@') {
                result.extend_from_slice(HIDDEN);
                result.push(b'@');
                result.extend_from_slice(&input[at + offset + 1..end]);
            } else {
                result.extend_from_slice(&input[at..end]);
            }
            at = end;
        } else {
            result.push(input[at]);
            at += 1;
        }
    }
    result
}

fn sensitive_name(input: &[u8]) -> bool {
    let mut decoded = input.to_vec();
    for _ in 0..3 {
        let mut next = Vec::with_capacity(decoded.len());
        let mut at = 0;
        while at < decoded.len() {
            let (byte, consumed) = decoded_byte(&decoded, at);
            next.push(byte);
            at += consumed;
        }
        decoded = next;
    }
    decoded.make_ascii_lowercase();
    matches!(
        decoded.as_slice(),
        b"token"
            | b"access_token"
            | b"access-token"
            | b"id_token"
            | b"refresh_token"
            | b"api_key"
            | b"api-key"
            | b"apikey"
            | b"client_secret"
            | b"client-secret"
            | b"secret"
            | b"password"
            | b"passwd"
            | b"pwd"
            | b"authorization"
            | b"auth"
            | b"key"
    )
}

fn redact_query(input: &[u8]) -> Vec<u8> {
    let mut result = Vec::with_capacity(input.len());
    let mut at = 0;
    while at < input.len() {
        if matches!(input[at], b'?' | b'&' | b';') {
            let start = at + 1;
            let end = (start..input.len())
                .find(|&i| {
                    input[i] == b'='
                        || input[i].is_ascii_whitespace()
                        || matches!(input[i], b'&' | b';' | b'#' | b'\'' | b'"' | b')' | b',')
                })
                .unwrap_or(input.len());
            if end < input.len() && input[end] == b'=' && sensitive_name(&input[start..end]) {
                result.extend_from_slice(&input[at..=end]);
                result.extend_from_slice(HIDDEN);
                at = (end + 1..input.len())
                    .find(|&i| {
                        input[i].is_ascii_whitespace()
                            || matches!(input[i], b'&' | b';' | b'#' | b'\'' | b'"' | b')' | b',')
                    })
                    .unwrap_or(input.len());
                continue;
            }
        }
        result.push(input[at]);
        at += 1;
    }
    result
}

fn redact_authorization(input: &[u8]) -> Vec<u8> {
    let mut result = Vec::with_capacity(input.len());
    let mut at = 0;
    while at < input.len() {
        let mut header_len = 0;
        for name in [
            b"proxy-authorization".as_slice(),
            b"authorization".as_slice(),
        ] {
            if input[at..]
                .get(..name.len())
                .is_some_and(|candidate| candidate.eq_ignore_ascii_case(name))
            {
                let mut end = at + name.len();
                while end < input.len() && matches!(input[end], b' ' | b'\t' | b'"' | b'\'') {
                    end += 1;
                }
                if end < input.len() && matches!(input[end], b':' | b'=') {
                    header_len = end + 1 - at;
                    break;
                }
            }
        }
        if header_len == 0 {
            result.push(input[at]);
            at += 1;
            continue;
        }
        result.extend_from_slice(&input[at..at + header_len]);
        at += header_len;
        while at < input.len() && matches!(input[at], b' ' | b'\t') {
            result.push(input[at]);
            at += 1;
        }
        if at == input.len() {
            break;
        }
        let quote = if matches!(input[at], b'"' | b'\'') {
            let value = input[at];
            result.push(value);
            at += 1;
            Some(value)
        } else {
            None
        };
        result.extend_from_slice(HIDDEN);
        while at < input.len() {
            if quote.is_some_and(|q| input[at] == q)
                || (quote.is_none()
                    && matches!(input[at], b'\r' | b'\n' | b',' | b';' | b']' | b'}'))
            {
                break;
            }
            at += 1;
        }
        if quote.is_some() && at < input.len() {
            result.push(input[at]);
            at += 1;
        }
    }
    result
}

pub(crate) fn sanitize(message: &str) -> String {
    let result = redact_authorization(&redact_query(&redact_userinfo(message.as_bytes())));
    String::from_utf8(result).expect("redaction preserves UTF-8")
}

#[cfg(test)]
#[path = "diagnostic_redact_tests.rs"]
mod tests;
