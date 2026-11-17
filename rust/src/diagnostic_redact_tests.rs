use super::*;

#[test]
fn retains_diagnostic_address_but_hides_authentication() {
    let message = "proxy http://alice:p%40ss@192.0.2.12:8080 failed; Authorization: Bearer key-123\nrelay https://relay.example:443/?token=abc&mode=fast";
    let output = sanitize(message);
    assert!(output.contains("192.0.2.12:8080"));
    assert!(output.contains("https://relay.example:443/?token=[REDACTED]&mode=fast"));
    for secret in ["alice", "p%40ss", "key-123", "abc"] {
        assert!(!output.contains(secret));
    }
}

#[test]
fn retains_plain_error_addresses_and_numbers_exactly() {
    let message = "HTTP 401 at https://relay.example:8443 from 192.0.2.1:443; device 1";
    assert_eq!(sanitize(message), message);
}

#[test]
fn handles_case_variants_quoted_headers_and_encoded_query_names() {
    let output = sanitize("{\"Proxy-Authorization\": \"Basic dXNlcjpwYXNz\"} https://h.example/?access%255Ftoken=secret&state=ok");
    assert!(!output.contains("dXNlcjpwYXNz"));
    assert!(!output.contains("secret"));
    assert!(output.contains("https://h.example/?access%255Ftoken=[REDACTED]&state=ok"));
}
