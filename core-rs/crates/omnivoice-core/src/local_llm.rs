use std::collections::HashMap;
use std::net::TcpListener;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::Mutex;
use std::time::Duration;

use serde_json::Value;
use thiserror::Error;

use crate::cleanup::ChatMessage;
use crate::llm::complete_chat;
use crate::models::ModelManager;

const DEFAULT_OLLAMA_BASE_URL: &str = "http://127.0.0.1:11434";

#[derive(Debug, Error)]
pub enum LocalLlmError {
    #[error("{0}")]
    Unavailable(String),
    #[error("local LLM runtime error: {0}")]
    Runtime(String),
}

struct ManagedLlamaServer {
    child: Child,
    port: u16,
    model_path: PathBuf,
}

impl Drop for ManagedLlamaServer {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

pub struct LocalLlmRuntime {
    llama_server_bin: Option<PathBuf>,
    ollama_base_url: String,
    llama_server: Mutex<Option<ManagedLlamaServer>>,
}

impl Default for LocalLlmRuntime {
    fn default() -> Self {
        Self::new()
    }
}

impl LocalLlmRuntime {
    pub fn new() -> Self {
        let ollama_base = std::env::var("OMNIVOICE_OLLAMA_BASE_URL")
            .ok()
            .filter(|v| !v.trim().is_empty())
            .unwrap_or_else(|| DEFAULT_OLLAMA_BASE_URL.to_string());
        Self::with_config(Self::resolve_llama_server_bin(), ollama_base)
    }

    pub fn with_config(llama_server_bin: Option<PathBuf>, ollama_base_url: impl Into<String>) -> Self {
        let base = ollama_base_url.into();
        let trimmed = base.trim().trim_end_matches('/').to_string();
        Self {
            llama_server_bin,
            ollama_base_url: if trimmed.is_empty() {
                DEFAULT_OLLAMA_BASE_URL.to_string()
            } else {
                trimmed
            },
            llama_server: Mutex::new(None),
        }
    }

    pub fn resolve_llama_server_bin() -> Option<PathBuf> {
        if let Some(env_bin) = std::env::var_os("OMNIVOICE_LLAMA_SERVER_BIN") {
            let path = PathBuf::from(env_bin);
            if path.is_file() {
                return Some(path);
            }
        }
        if let Ok(exe) = std::env::current_exe() {
            if let Some(dir) = exe.parent() {
                let sibling = dir.join("llama-server");
                if sibling.is_file() {
                    return Some(sibling);
                }
            }
        }
        if let Some(path_var) = std::env::var_os("PATH") {
            for dir in std::env::split_paths(&path_var) {
                let candidate = dir.join("llama-server");
                if candidate.is_file() {
                    return Some(candidate);
                }
            }
        }
        None
    }

    pub async fn status_summary(
        &self,
        client: &reqwest::Client,
        models: &ModelManager,
        provider_id: &str,
    ) -> (bool, Option<String>) {
        if self.llama_server_bin.is_some() && models.find_gguf_file(provider_id).is_some() {
            return (true, None);
        }
        if let Ok(ollama_models) = self.probe_ollama_models(client).await {
            if !ollama_models.is_empty() {
                return (true, Some("Using local Ollama runtime".to_string()));
            }
        }
        (
            false,
            Some("Download Qwen3 GGUF (with llama-server) or run Ollama locally".to_string()),
        )
    }

    pub async fn complete_cleanup(
        &self,
        client: &reqwest::Client,
        models: &ModelManager,
        model_id: &str,
        messages: &[ChatMessage],
        timeout_seconds: f64,
    ) -> Result<String, LocalLlmError> {
        if let (Some(ref bin), Some(gguf_path)) =
            (&self.llama_server_bin, models.find_gguf_file(model_id))
        {
            let port = self.ensure_llama_server(client, bin, &gguf_path).await?;
            let base_url = format!("http://127.0.0.1:{port}/v1");
            return complete_chat(
                client,
                "openai_compatible",
                &base_url,
                "",
                "",
                &HashMap::new(),
                model_id,
                messages,
                timeout_seconds,
            )
            .await
            .map_err(|e| LocalLlmError::Runtime(e.to_string()));
        }

        if let Ok(ollama_models) = self.probe_ollama_models(client).await {
            if let Some(chosen) = choose_preferred_ollama_model(&ollama_models) {
                let base_url = format!("{}/v1", self.ollama_base_url);
                return complete_chat(
                    client,
                    "openai_compatible",
                    &base_url,
                    "",
                    "",
                    &HashMap::new(),
                    &chosen,
                    messages,
                    timeout_seconds,
                )
                .await
                .map_err(|e| LocalLlmError::Runtime(e.to_string()));
            }
        }

        Err(LocalLlmError::Unavailable(
            "No local LLM runtime available (download Qwen3 GGUF with llama-server or start Ollama)"
                .to_string(),
        ))
    }

    async fn ensure_llama_server(
        &self,
        client: &reqwest::Client,
        bin: &Path,
        model_path: &Path,
    ) -> Result<u16, LocalLlmError> {
        let port = {
            let mut guard = self
                .llama_server
                .lock()
                .expect("llama_server mutex poisoned");
            if let Some(ref mut running) = *guard {
                let still_alive = matches!(running.child.try_wait(), Ok(None));
                if still_alive && running.model_path == model_path {
                    Some(running.port)
                } else {
                    *guard = None;
                    None
                }
            } else {
                None
            }
        };

        if let Some(existing_port) = port {
            return Ok(existing_port);
        }

        let listener = TcpListener::bind("127.0.0.1:0")
            .map_err(|e| LocalLlmError::Runtime(format!("failed allocating loopback port: {e}")))?;
        let chosen_port = listener
            .local_addr()
            .map_err(|e| LocalLlmError::Runtime(e.to_string()))?
            .port();
        drop(listener);

        let child = Command::new(bin)
            .arg("--model")
            .arg(model_path)
            .arg("--host")
            .arg("127.0.0.1")
            .arg("--port")
            .arg(chosen_port.to_string())
            .arg("--ctx-size")
            .arg("2048")
            .arg("--n-gpu-layers")
            .arg("99")
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|e| LocalLlmError::Runtime(format!("failed starting llama-server: {e}")))?;

        {
            let mut guard = self
                .llama_server
                .lock()
                .expect("llama_server mutex poisoned");
            *guard = Some(ManagedLlamaServer {
                child,
                port: chosen_port,
                model_path: model_path.to_path_buf(),
            });
        }

        let health_url = format!("http://127.0.0.1:{chosen_port}/health");
        for _ in 0..80 {
            if let Ok(resp) = client
                .get(&health_url)
                .timeout(Duration::from_millis(250))
                .send()
                .await
            {
                if resp.status().is_success() {
                    return Ok(chosen_port);
                }
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }

        Err(LocalLlmError::Runtime(
            "llama-server did not become healthy in time".to_string(),
        ))
    }

    async fn probe_ollama_models(&self, client: &reqwest::Client) -> Result<Vec<String>, LocalLlmError> {
        let url = format!("{}/api/tags", self.ollama_base_url);
        let resp = client
            .get(&url)
            .timeout(Duration::from_millis(400))
            .send()
            .await
            .map_err(|e| LocalLlmError::Unavailable(e.to_string()))?;
        if !resp.status().is_success() {
            return Err(LocalLlmError::Unavailable(format!(
                "Ollama returned {}",
                resp.status()
            )));
        }
        let val: Value = resp
            .json()
            .await
            .map_err(|e| LocalLlmError::Unavailable(e.to_string()))?;
        let names = val["models"]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(|m| m["name"].as_str().or_else(|| m["model"].as_str()))
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect();
        Ok(names)
    }
}

fn choose_preferred_ollama_model(models: &[String]) -> Option<String> {
    let non_embed: Vec<&String> = models
        .iter()
        .filter(|name| !name.to_ascii_lowercase().contains("embed"))
        .collect();
    if let Some(qwen3) = non_embed
        .iter()
        .find(|n| n.to_ascii_lowercase().contains("qwen3"))
    {
        return Some((*qwen3).clone());
    }
    if let Some(qwen25) = non_embed
        .iter()
        .find(|n| n.to_ascii_lowercase().contains("qwen2.5"))
    {
        return Some((*qwen25).clone());
    }
    non_embed
        .first()
        .copied()
        .or_else(|| models.first())
        .cloned()
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tokio::net::TcpListener as AsyncTcpListener;

    async fn spawn_mock_ollama() -> String {
        let listener = AsyncTcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        tokio::spawn(async move {
            loop {
                let Ok((mut stream, _)) = listener.accept().await else {
                    break;
                };
                tokio::spawn(async move {
                    let mut buf = [0u8; 8192];
                    let Ok(n) = stream.read(&mut buf).await else {
                        return;
                    };
                    let req = String::from_utf8_lossy(&buf[..n]);
                    let path = req
                        .lines()
                        .next()
                        .unwrap_or("")
                        .split_whitespace()
                        .nth(1)
                        .unwrap_or("/");
                    let (status, body) = if path == "/api/tags" {
                        (
                            "200 OK",
                            r#"{"models":[{"name":"nomic-embed-text:latest"},{"name":"qwen3:1.7b"}]}"#,
                        )
                    } else if path == "/v1/chat/completions" {
                        (
                            "200 OK",
                            r#"{"choices":[{"message":{"content":"I am going to the house."}}]}"#,
                        )
                    } else {
                        ("404 Not Found", r#"{"error":"not found"}"#)
                    };
                    let header = format!(
                        "HTTP/1.1 {status}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                        body.len()
                    );
                    let _ = stream.write_all(header.as_bytes()).await;
                    let _ = stream.write_all(body.as_bytes()).await;
                });
            }
        });
        format!("http://{addr}")
    }

    #[tokio::test]
    async fn completes_cleanup_via_ollama_and_fails_cleanly_when_unavailable() {
        let ollama_url = spawn_mock_ollama().await;
        let temp_root =
            std::env::temp_dir().join(format!("omnivoice-local-llm-{}", uuid::Uuid::new_v4()));
        let models = ModelManager::new(&temp_root);
        let client = reqwest::Client::new();

        let runtime = LocalLlmRuntime::with_config(None, &ollama_url);
        let (available, note) = runtime
            .status_summary(&client, &models, "qwen3-1.7b-gguf-q4")
            .await;
        assert!(available);
        assert!(note.unwrap().contains("Ollama"));

        let messages = vec![ChatMessage {
            role: "user".to_string(),
            content: "I am going to the store, wait, the house.".to_string(),
        }];
        let out = runtime
            .complete_cleanup(&client, &models, "qwen3-1.7b-mlx-4bit", &messages, 5.0)
            .await
            .unwrap();
        assert_eq!(out, "I am going to the house.");

        let offline_runtime = LocalLlmRuntime::with_config(None, "http://127.0.0.1:1");
        let err = offline_runtime
            .complete_cleanup(&client, &models, "qwen3-1.7b-gguf-q4", &messages, 1.0)
            .await
            .unwrap_err();
        assert!(matches!(err, LocalLlmError::Unavailable(_)));

        let _ = std::fs::remove_dir_all(&temp_root);
    }
}
