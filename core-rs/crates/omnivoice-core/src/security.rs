use url::Url;

pub const ENGINE_AUTH_HEADER: &str = "X-OmniSpeak-Engine-Token";
pub const ENGINE_AUTH_COOKIE: &str = "omnispeak_engine_token";
const ALLOWED_LOCAL_HOSTS: [&str; 4] = ["127.0.0.1", "localhost", "::1", "testserver"];

pub fn extract_hostname(host_header: Option<&str>) -> String {
    let raw = host_header.unwrap_or("").trim().to_ascii_lowercase();
    if raw.is_empty() {
        return String::new();
    }
    if raw.starts_with('[') {
        if let Some(closing) = raw.find(']') {
            return raw[1..closing].to_string();
        }
        return raw;
    }
    if raw.matches(':').count() == 1 {
        return raw.split(':').next().unwrap_or("").to_string();
    }
    raw
}

pub fn is_allowed_host(host_header: Option<&str>) -> bool {
    let hostname = extract_hostname(host_header);
    hostname.is_empty() || ALLOWED_LOCAL_HOSTS.contains(&hostname.as_str())
}

pub fn is_allowed_origin(origin_header: Option<&str>) -> bool {
    let raw = origin_header.unwrap_or("").trim();
    if raw.is_empty() {
        return true;
    }
    let Ok(parsed) = Url::parse(raw) else {
        return false;
    };
    let Some(host) = parsed.host_str() else {
        return false;
    };
    let normalized = host.trim_matches(['[', ']']).to_ascii_lowercase();
    ALLOWED_LOCAL_HOSTS.contains(&normalized.as_str())
}

/// Constant-time comparison of an incoming engine token against the expected secret.
pub fn token_matches(provided: Option<&str>, expected: &str) -> bool {
    let candidate = provided.unwrap_or("").trim().as_bytes();
    let expected_bytes = expected.trim().as_bytes();
    if candidate.is_empty() || expected_bytes.is_empty() || candidate.len() != expected_bytes.len() {
        return false;
    }
    let mut diff: u8 = 0;
    for (a, b) in candidate.iter().zip(expected_bytes.iter()) {
        diff |= a ^ b;
    }
    diff == 0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_local_hosts_and_rejects_foreign_hosts() {
        assert!(is_allowed_host(None));
        assert!(is_allowed_host(Some("127.0.0.1:8765")));
        assert!(is_allowed_host(Some("localhost:8765")));
        assert!(is_allowed_host(Some("[::1]:8765")));
        assert!(!is_allowed_host(Some("evil.example:8765")));
    }

    #[test]
    fn validates_local_origins_and_rejects_foreign_origins() {
        assert!(is_allowed_origin(None));
        assert!(is_allowed_origin(Some("http://127.0.0.1:8765")));
        assert!(is_allowed_origin(Some("http://localhost:3000")));
        assert!(!is_allowed_origin(Some("https://evil.example")));
        assert!(!is_allowed_origin(Some("not-a-url")));
    }

    #[test]
    fn constant_time_token_matching() {
        assert!(token_matches(Some("secret-token"), "secret-token"));
        assert!(token_matches(Some("  secret-token  "), "secret-token"));
        assert!(!token_matches(Some("secret-tokeb"), "secret-token"));
        assert!(!token_matches(Some(""), "secret-token"));
        assert!(!token_matches(None, "secret-token"));
    }
}
