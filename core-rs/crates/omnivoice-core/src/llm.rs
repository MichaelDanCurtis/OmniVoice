use std::collections::HashMap;
use std::time::Duration;

use reqwest::header::{HeaderMap, HeaderName, HeaderValue, AUTHORIZATION, CONTENT_TYPE};
use serde_json::{json, Value};
use thiserror::Error;

use crate::cleanup::{ChatMessage, CleanupLlmConfig};

#[derive(Debug, Error)]
pub enum LlmError {
    #[error("LLM configuration incomplete: {0}")]
    InvalidConfig(String),
    #[error("HTTP request failed: {0}")]
    Http(#[from] reqwest::Error),
    #[error("upstream returned {status}: {body}")]
    Upstream { status: u16, body: String },
    #[error("upstream response did not include completion text")]
    EmptyResponse,
}

pub fn llm_config_is_ready(cfg: &CleanupLlmConfig) -> bool {
    if cfg.model.trim().is_empty() {
        return false;
    }
    match cfg.transport.as_str() {
        "openai_compatible" | "anthropic" => !cfg.base_url.trim().is_empty(),
        "openai_codex_oauth" | "github_copilot_oauth" => !cfg.oauth_access_token.trim().is_empty(),
        _ => false,
    }
}

pub async fn complete_chat(
    client: &reqwest::Client,
    transport: &str,
    base_url: &str,
    api_key: &str,
    oauth_access_token: &str,
    extra_headers: &HashMap<String, String>,
    model: &str,
    messages: &[ChatMessage],
    timeout_seconds: f64,
) -> Result<String, LlmError> {
    let model = model.trim();
    if model.is_empty() {
        return Err(LlmError::InvalidConfig("model is required".to_string()));
    }
    let timeout = Duration::from_secs_f64(timeout_seconds.clamp(0.5, 120.0));

    match transport {
        "openai_compatible" => {
            let base = base_url.trim().trim_end_matches('/');
            if base.is_empty() {
                return Err(LlmError::InvalidConfig("base_url is required".to_string()));
            }
            let endpoint = format!("{base}/chat/completions");
            let mut headers = build_extra_headers(extra_headers);
            headers.insert(CONTENT_TYPE, HeaderValue::from_static("application/json"));
            if !api_key.trim().is_empty() {
                if let Ok(val) = HeaderValue::from_str(&format!("Bearer {}", api_key.trim())) {
                    headers.insert(AUTHORIZATION, val);
                }
            }
            let payload = json!({
                "model": model,
                "messages": messages,
                "temperature": 0.1,
            });
            let resp = client
                .post(endpoint)
                .headers(headers)
                .timeout(timeout)
                .json(&payload)
                .send()
                .await?;
            let status = resp.status().as_u16();
            let body_text = resp.text().await?;
            if !(200..300).contains(&status) {
                return Err(LlmError::Upstream {
                    status,
                    body: body_text,
                });
            }
            extract_openai_text(&body_text).ok_or(LlmError::EmptyResponse)
        }
        "anthropic" => {
            let base = base_url.trim().trim_end_matches('/');
            if base.is_empty() {
                return Err(LlmError::InvalidConfig("base_url is required".to_string()));
            }
            let endpoint = if base.ends_with("/v1") {
                format!("{base}/messages")
            } else {
                format!("{base}/v1/messages")
            };
            let mut headers = build_extra_headers(extra_headers);
            headers.insert(CONTENT_TYPE, HeaderValue::from_static("application/json"));
            headers.insert(
                HeaderName::from_static("anthropic-version"),
                HeaderValue::from_static("2023-06-01"),
            );
            if !api_key.trim().is_empty() {
                if let Ok(val) = HeaderValue::from_str(api_key.trim()) {
                    headers.insert(HeaderName::from_static("x-api-key"), val);
                }
            }
            let system = messages
                .iter()
                .filter(|m| m.role == "system")
                .map(|m| m.content.as_str())
                .collect::<Vec<_>>()
                .join("\n\n");
            let user_messages: Vec<Value> = messages
                .iter()
                .filter(|m| m.role != "system")
                .map(|m| json!({"role": m.role, "content": m.content}))
                .collect();
            let mut payload = json!({
                "model": model,
                "max_tokens": 1024,
                "messages": user_messages,
            });
            if !system.is_empty() {
                payload["system"] = Value::String(system);
            }
            let resp = client
                .post(endpoint)
                .headers(headers)
                .timeout(timeout)
                .json(&payload)
                .send()
                .await?;
            let status = resp.status().as_u16();
            let body_text = resp.text().await?;
            if !(200..300).contains(&status) {
                return Err(LlmError::Upstream {
                    status,
                    body: body_text,
                });
            }
            extract_anthropic_text(&body_text).ok_or(LlmError::EmptyResponse)
        }
        other => {
            if oauth_access_token.trim().is_empty() {
                return Err(LlmError::InvalidConfig(format!(
                    "unsupported or unauthenticated transport: {other}"
                )));
            }
            Err(LlmError::InvalidConfig(format!(
                "transport '{other}' not yet wired in Rust core"
            )))
        }
    }
}

pub async fn list_models(
    client: &reqwest::Client,
    transport: &str,
    base_url: &str,
    api_key: &str,
    oauth_access_token: &str,
    extra_headers: &HashMap<String, String>,
    timeout: Duration,
) -> Result<Vec<String>, LlmError> {
    let base = base_url.trim().trim_end_matches('/');
    match transport {
        "openai_compatible" | "" => {
            if base.is_empty() {
                return Err(LlmError::InvalidConfig(
                    "AI endpoint is required".to_string(),
                ));
            }
            let endpoint = if base.ends_with("/models") {
                base.to_string()
            } else {
                format!("{base}/models")
            };
            let mut headers = build_extra_headers(extra_headers);
            if !api_key.trim().is_empty() {
                if let Ok(val) = HeaderValue::from_str(&format!("Bearer {}", api_key.trim())) {
                    headers.insert(AUTHORIZATION, val);
                }
            }
            let resp = client.get(endpoint).headers(headers).timeout(timeout).send().await?;
            let status = resp.status().as_u16();
            let body_text = resp.text().await?;
            if !(200..300).contains(&status) {
                return Err(LlmError::Upstream {
                    status,
                    body: body_text,
                });
            }
            Ok(parse_model_list(&body_text))
        }
        "anthropic" => {
            if base.is_empty() {
                return Err(LlmError::InvalidConfig(
                    "AI endpoint is required".to_string(),
                ));
            }
            let endpoint = if base.ends_with("/models") {
                base.to_string()
            } else {
                format!("{base}/models")
            };
            let mut headers = build_extra_headers(extra_headers);
            headers.insert(
                HeaderName::from_static("anthropic-version"),
                HeaderValue::from_static("2023-06-01"),
            );
            if !api_key.trim().is_empty() {
                if let Ok(val) = HeaderValue::from_str(api_key.trim()) {
                    headers.insert(HeaderName::from_static("x-api-key"), val);
                }
            }
            let resp = client.get(endpoint).headers(headers).timeout(timeout).send().await?;
            let status = resp.status().as_u16();
            let body_text = resp.text().await?;
            if !(200..300).contains(&status) {
                return Err(LlmError::Upstream {
                    status,
                    body: body_text,
                });
            }
            Ok(parse_model_list(&body_text))
        }
        other => {
            if oauth_access_token.trim().is_empty() {
                return Err(LlmError::InvalidConfig(format!(
                    "unsupported or unauthenticated transport: {other}"
                )));
            }
            Err(LlmError::InvalidConfig(format!(
                "model listing for '{other}' not yet wired in Rust core"
            )))
        }
    }
}

fn build_extra_headers(extra: &HashMap<String, String>) -> HeaderMap {
    let mut map = HeaderMap::new();
    for (k, v) in extra {
        if let (Ok(name), Ok(val)) = (
            HeaderName::from_bytes(k.trim().as_bytes()),
            HeaderValue::from_str(v.trim()),
        ) {
            map.insert(name, val);
        }
    }
    map
}

fn extract_openai_text(body: &str) -> Option<String> {
    let val: Value = serde_json::from_str(body).ok()?;
    let text = val["choices"][0]["message"]["content"].as_str()?.trim();
    if text.is_empty() {
        None
    } else {
        Some(text.to_string())
    }
}

fn extract_anthropic_text(body: &str) -> Option<String> {
    let val: Value = serde_json::from_str(body).ok()?;
    let blocks = val["content"].as_array()?;
    let joined = blocks
        .iter()
        .filter_map(|b| b["text"].as_str())
        .collect::<Vec<_>>()
        .join("")
        .trim()
        .to_string();
    if joined.is_empty() {
        None
    } else {
        Some(joined)
    }
}

fn parse_model_list(body: &str) -> Vec<String> {
    let Ok(val) = serde_json::from_str::<Value>(body) else {
        return Vec::new();
    };
    let mut models = Vec::new();
    if let Some(items) = val["data"].as_array() {
        for item in items {
            if let Some(id) = item["id"].as_str().map(str::trim).filter(|s| !s.is_empty()) {
                models.push(id.to_string());
            }
        }
    } else if let Some(items) = val["models"].as_array() {
        for item in items {
            if let Some(id) = item["id"]
                .as_str()
                .or_else(|| item["name"].as_str())
                .map(str::trim)
                .filter(|s| !s.is_empty())
            {
                models.push(id.to_string());
            }
        }
    }
    models.sort();
    models.dedup();
    models
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extracts_openai_and_anthropic_payloads() {
        let openai = r#"{"choices":[{"message":{"content":"  Clean output.  "}}]}"#;
        assert_eq!(extract_openai_text(openai).as_deref(), Some("Clean output."));

        let anthropic = r#"{"content":[{"type":"text","text":"Hello "},{"type":"text","text":"world."}]}"#;
        assert_eq!(extract_anthropic_text(anthropic).as_deref(), Some("Hello world."));
    }

    #[test]
    fn parses_model_lists_from_openai_and_anthropic_shapes() {
        let payload = r#"{"data":[{"id":"gpt-5.4"},{"id":"gpt-4o"},{"id":"gpt-5.4"}]}"#;
        assert_eq!(
            parse_model_list(payload),
            vec!["gpt-4o".to_string(), "gpt-5.4".to_string()]
        );

        let ollama_like = r#"{"models":[{"name":"qwen3:4b"},{"id":"llama3.2"}]}"#;
        assert_eq!(
            parse_model_list(ollama_like),
            vec!["llama3.2".to_string(), "qwen3:4b".to_string()]
        );
    }
}
