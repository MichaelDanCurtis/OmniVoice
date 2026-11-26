use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use reqwest::header::{HeaderMap, HeaderValue, AUTHORIZATION};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use thiserror::Error;

const DEFAULT_HF_BASE_URL: &str = "https://huggingface.co";
const REVISION_MARKER_FILE: &str = ".revision";

#[derive(Debug, Error)]
pub enum ModelError {
    #[error("unknown model provider: {0}")]
    UnknownProvider(String),
    #[error("HTTP request failed: {0}")]
    Http(String),
    #[error("filesystem error: {0}")]
    Io(String),
    #[error("invalid response from Hugging Face: {0}")]
    InvalidResponse(String),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ModelStatus {
    pub provider_id: String,
    pub label: String,
    pub repo_id: String,
    pub local_path: String,
    pub installed: bool,
    pub category: String,
    pub recommendation: Option<String>,
    pub detail: Option<String>,
    pub size: Option<String>,
    pub precision: Option<String>,
    pub requires_hf_auth: bool,
    pub agreement_url: Option<String>,
    pub license: Option<String>,
    pub installed_revision: Option<String>,
    pub remote_revision: Option<String>,
    pub update_available: Option<bool>,
    pub missing_files: Vec<String>,
    pub download_state: String,
    pub download_message: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ModelUpdateInfo {
    pub provider_id: String,
    pub repo_id: String,
    pub installed_revision: Option<String>,
    pub remote_revision: String,
    pub update_available: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ModelDownloadStatus {
    pub provider_id: String,
    pub state: String,
    pub message: Option<String>,
    pub local_path: String,
    pub revision: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HuggingFaceAuthStatus {
    pub connected: bool,
    pub source: String,
    pub username: Option<String>,
    pub provider_id: Option<String>,
    pub repo_id: Option<String>,
    pub access_granted: Option<bool>,
    pub message: String,
}

#[derive(Debug, Clone)]
struct ModelSpec {
    provider_id: &'static str,
    label: &'static str,
    repo_id: &'static str,
    folder_name: &'static str,
    category: &'static str,
    recommendation: &'static str,
    detail: &'static str,
    size: &'static str,
    precision: &'static str,
    license: &'static str,
}

const MODEL_SPECS: &[ModelSpec] = &[
    ModelSpec {
        provider_id: "parakeet-tdt-coreml-ane",
        label: "Parakeet TDT v3 (CoreML ANE)",
        repo_id: "FluidInference/parakeet-tdt-0.6b-v3-coreml",
        folder_name: "parakeet-tdt-0.6b-v3-coreml",
        category: "asr",
        recommendation: "recommended",
        detail: "In-process CoreML Apple Neural Engine ASR via FluidAudio.",
        size: "~600 MB",
        precision: "CoreML FP16 / ANE",
        license: "CC-BY-4.0",
    },
    ModelSpec {
        provider_id: "sortformer-coreml-ane",
        label: "Sortformer Diarizer (CoreML ANE)",
        repo_id: "FluidInference/speaker-diarization-coreml",
        folder_name: "sortformer-coreml-ane",
        category: "diarization",
        recommendation: "recommended",
        detail: "On-device CoreML ANE speaker diarization for Conversation Mode.",
        size: "~85 MB",
        precision: "CoreML ANE",
        license: "MIT",
    },
    ModelSpec {
        provider_id: "qwen3-1.7b-gguf-q4",
        label: "Qwen3 1.7B Cleanup (GGUF Q4)",
        repo_id: "Qwen/Qwen3-1.7B-GGUF",
        folder_name: "qwen3-1.7b-gguf-q4",
        category: "cleanup_llm",
        recommendation: "recommended",
        detail: "Fast local LLM cleanup preset for punctuation and self-correction.",
        size: "~1.1 GB",
        precision: "Q4_K_M",
        license: "Apache-2.0",
    },
    ModelSpec {
        provider_id: "qwen3-4b-instruct-gguf-q4",
        label: "Qwen3 4B Instruct (GGUF Q4)",
        repo_id: "Qwen/Qwen3-4B-Instruct-2507-GGUF",
        folder_name: "qwen3-4b-instruct-gguf-q4",
        category: "cleanup_llm",
        recommendation: "optional",
        detail: "Higher-accuracy local LLM rewrite model for longer dictations.",
        size: "~2.5 GB",
        precision: "Q4_K_M",
        license: "Apache-2.0",
    },
];

pub fn canonical_provider_id(id: &str) -> &str {
    match id.trim() {
        "qwen3-1.7b-mlx-4bit" => "qwen3-1.7b-gguf-q4",
        "qwen3-4b-instruct-mlx-4bit" => "qwen3-4b-instruct-gguf-q4",
        other => other,
    }
}

pub struct ModelManager {
    model_root: PathBuf,
    hf_base_url: String,
    download_states: Mutex<HashMap<String, (String, Option<String>)>>,
}

impl ModelManager {
    pub fn new(model_root: impl Into<PathBuf>) -> Self {
        Self::with_hf_base_url(model_root, DEFAULT_HF_BASE_URL)
    }

    pub fn with_hf_base_url(
        model_root: impl Into<PathBuf>,
        hf_base_url: impl Into<String>,
    ) -> Self {
        let base = hf_base_url.into();
        let trimmed = base.trim().trim_end_matches('/');
        Self {
            model_root: model_root.into(),
            hf_base_url: if trimmed.is_empty() {
                DEFAULT_HF_BASE_URL.to_string()
            } else {
                trimmed.to_string()
            },
            download_states: Mutex::new(HashMap::new()),
        }
    }

    pub fn from_env() -> Self {
        let root = std::env::var_os("OMNIVOICE_MODEL_ROOT")
            .filter(|v| !v.is_empty())
            .map(PathBuf::from)
            .unwrap_or_else(default_model_root);
        let hf_base = std::env::var("OMNIVOICE_HF_BASE_URL")
            .ok()
            .filter(|v| !v.trim().is_empty())
            .unwrap_or_else(|| DEFAULT_HF_BASE_URL.to_string());
        Self::with_hf_base_url(root, hf_base)
    }

    pub fn model_root(&self) -> &Path {
        &self.model_root
    }

    pub fn hf_base_url(&self) -> &str {
        &self.hf_base_url
    }

    pub fn list_statuses(&self) -> Vec<ModelStatus> {
        MODEL_SPECS
            .iter()
            .map(|spec| self.status_for_spec(spec))
            .collect()
    }

    pub fn get_status(&self, provider_id: &str) -> Option<ModelStatus> {
        let canonical = canonical_provider_id(provider_id);
        MODEL_SPECS
            .iter()
            .find(|spec| spec.provider_id == canonical)
            .map(|spec| self.status_for_spec(spec))
    }

    pub fn find_gguf_file(&self, provider_id: &str) -> Option<PathBuf> {
        let spec = find_spec(provider_id)?;
        let dir = self.model_root.join(spec.folder_name);
        let entries = std::fs::read_dir(&dir).ok()?;
        let mut candidates: Vec<PathBuf> = entries
            .flatten()
            .map(|e| e.path())
            .filter(|p| {
                p.is_file()
                    && p.extension()
                        .and_then(|ext| ext.to_str())
                        .is_some_and(|ext| ext.eq_ignore_ascii_case("gguf"))
            })
            .collect();
        candidates.sort();
        if let Some(q4) = candidates.iter().find(|p| {
            p.file_name()
                .and_then(|n| n.to_str())
                .is_some_and(|n| n.to_ascii_lowercase().contains("q4_k_m"))
        }) {
            return Some(q4.clone());
        }
        candidates.into_iter().next()
    }

    pub fn queue_download(&self, provider_id: &str) -> Result<ModelDownloadStatus, ModelError> {
        let spec = find_spec(provider_id)
            .ok_or_else(|| ModelError::UnknownProvider(provider_id.to_string()))?;
        let target_dir = self.model_root.join(spec.folder_name);
        let already_installed = self.is_spec_installed(spec);
        let revision = read_revision_marker(&target_dir);

        if already_installed {
            self.set_download_state(
                spec.provider_id,
                "completed",
                Some("Model already installed locally".to_string()),
            );
            return Ok(ModelDownloadStatus {
                provider_id: spec.provider_id.to_string(),
                state: "completed".to_string(),
                message: Some("Model already installed locally".to_string()),
                local_path: target_dir.to_string_lossy().into_owned(),
                revision,
            });
        }

        let msg = if spec.category == "asr" || spec.category == "diarization" {
            "Checking CoreML Neural Engine model metadata...".to_string()
        } else {
            format!("Starting download for {}...", spec.label)
        };
        self.set_download_state(spec.provider_id, "downloading", Some(msg.clone()));

        Ok(ModelDownloadStatus {
            provider_id: spec.provider_id.to_string(),
            state: "downloading".to_string(),
            message: Some(msg),
            local_path: target_dir.to_string_lossy().into_owned(),
            revision: None,
        })
    }

    pub fn start_download(&self, provider_id: &str) -> Result<ModelDownloadStatus, String> {
        self.queue_download(provider_id).map_err(|e| e.to_string())
    }

    pub async fn run_download(
        &self,
        client: &reqwest::Client,
        provider_id: &str,
        hf_token: Option<&str>,
    ) -> Result<ModelDownloadStatus, ModelError> {
        let spec = find_spec(provider_id)
            .ok_or_else(|| ModelError::UnknownProvider(provider_id.to_string()))?;
        let target_dir = self.model_root.join(spec.folder_name);

        if spec.category == "asr" || spec.category == "diarization" {
            let revision = match self.fetch_repo_metadata(client, spec.repo_id, hf_token).await {
                Ok(meta) => meta.sha,
                Err(_) => None,
            };
            let msg = if self.is_spec_installed(spec) {
                "Model cached on-device".to_string()
            } else if spec.provider_id == "parakeet-tdt-coreml-ane" {
                "Managed automatically on-device by CoreML / FluidAudio on first run".to_string()
            } else {
                "Requires Python Legacy runtime to download & run (switch Engine Runtime on Overview, or use Parakeet TDT CoreML ANE)."
                    .to_string()
            };
            self.set_download_state(spec.provider_id, "completed", Some(msg.clone()));
            return Ok(ModelDownloadStatus {
                provider_id: spec.provider_id.to_string(),
                state: "completed".to_string(),
                message: Some(msg),
                local_path: target_dir.to_string_lossy().into_owned(),
                revision,
            });
        }

        let res = self.download_gguf_model(client, spec, hf_token).await;
        match res {
            Ok(status) => Ok(status),
            Err(err) => {
                self.set_download_state(spec.provider_id, "failed", Some(err.to_string()));
                Err(err)
            }
        }
    }

    async fn download_gguf_model(
        &self,
        client: &reqwest::Client,
        spec: &ModelSpec,
        hf_token: Option<&str>,
    ) -> Result<ModelDownloadStatus, ModelError> {
        let meta = self
            .fetch_repo_metadata(client, spec.repo_id, hf_token)
            .await?;
        let rfilename = select_gguf_filename(&meta.siblings).ok_or_else(|| {
            ModelError::InvalidResponse(format!(
                "no .gguf file listed in Hugging Face repo {}",
                spec.repo_id
            ))
        })?;
        let basename = Path::new(&rfilename)
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("model.gguf")
            .to_string();

        let target_dir = self.model_root.join(spec.folder_name);
        std::fs::create_dir_all(&target_dir)
            .map_err(|e| ModelError::Io(format!("create {}: {e}", target_dir.display())))?;

        let part_path = target_dir.join(format!("{basename}.part"));
        let final_path = target_dir.join(&basename);
        let download_url = format!(
            "{}/{}/resolve/main/{}",
            self.hf_base_url, spec.repo_id, rfilename
        );

        let mut req = client.get(&download_url);
        if let Some(headers) = hf_auth_headers(hf_token) {
            req = req.headers(headers);
        }
        let mut resp = req
            .send()
            .await
            .map_err(|e| ModelError::Http(e.to_string()))?;
        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            return Err(ModelError::Http(format!("HTTP {status}: {body}")));
        }

        let total_bytes = resp.content_length();
        let mut downloaded: u64 = 0;
        let mut file = std::fs::File::create(&part_path)
            .map_err(|e| ModelError::Io(format!("create {}: {e}", part_path.display())))?;

        self.set_download_state(
            spec.provider_id,
            "downloading",
            Some(format!("Downloading {basename}...")),
        );

        let write_result: Result<(), ModelError> = async {
            use std::io::Write;
            while let Some(chunk) = resp
                .chunk()
                .await
                .map_err(|e| ModelError::Http(e.to_string()))?
            {
                file.write_all(&chunk)
                    .map_err(|e| ModelError::Io(format!("write {}: {e}", part_path.display())))?;
                downloaded += chunk.len() as u64;
                let msg = format_progress_message(&basename, downloaded, total_bytes);
                self.set_download_state(spec.provider_id, "downloading", Some(msg));
            }
            file.flush()
                .map_err(|e| ModelError::Io(format!("flush {}: {e}", part_path.display())))?;
            Ok(())
        }
        .await;

        if let Err(err) = write_result {
            let _ = std::fs::remove_file(&part_path);
            return Err(err);
        }

        std::fs::rename(&part_path, &final_path).map_err(|e| {
            let _ = std::fs::remove_file(&part_path);
            ModelError::Io(format!("rename to {}: {e}", final_path.display()))
        })?;

        if let Some(ref sha) = meta.sha {
            let _ = std::fs::write(target_dir.join(REVISION_MARKER_FILE), sha.as_bytes());
        }

        let done_msg = format!("Downloaded {basename}");
        self.set_download_state(spec.provider_id, "completed", Some(done_msg.clone()));

        Ok(ModelDownloadStatus {
            provider_id: spec.provider_id.to_string(),
            state: "completed".to_string(),
            message: Some(done_msg),
            local_path: target_dir.to_string_lossy().into_owned(),
            revision: meta.sha,
        })
    }

    pub async fn check_update(
        &self,
        client: &reqwest::Client,
        provider_id: &str,
        hf_token: Option<&str>,
    ) -> Result<ModelUpdateInfo, ModelError> {
        let spec = find_spec(provider_id)
            .ok_or_else(|| ModelError::UnknownProvider(provider_id.to_string()))?;
        let target_dir = self.model_root.join(spec.folder_name);
        let installed_revision = read_revision_marker(&target_dir);
        let meta = self
            .fetch_repo_metadata(client, spec.repo_id, hf_token)
            .await?;
        let remote_revision = meta
            .sha
            .ok_or_else(|| ModelError::InvalidResponse("missing repo sha".to_string()))?;
        let update_available = match (&installed_revision, self.is_spec_installed(spec)) {
            (Some(local), true) => local != &remote_revision,
            (_, true) => false,
            _ => true,
        };

        Ok(ModelUpdateInfo {
            provider_id: spec.provider_id.to_string(),
            repo_id: spec.repo_id.to_string(),
            installed_revision,
            remote_revision,
            update_available,
        })
    }

    pub async fn validate_huggingface_access(
        &self,
        client: &reqwest::Client,
        provider_id: &str,
        token: &str,
    ) -> Result<HuggingFaceAuthStatus, ModelError> {
        let spec = find_spec(provider_id)
            .ok_or_else(|| ModelError::UnknownProvider(provider_id.to_string()))?;
        let trimmed = token.trim();
        let source = if trimmed.is_empty() {
            "none".to_string()
        } else {
            "token".to_string()
        };

        let mut username: Option<String> = None;
        let mut connected = false;
        if !trimmed.is_empty() {
            let whoami_url = format!("{}/api/whoami-v2", self.hf_base_url);
            if let Some(headers) = hf_auth_headers(Some(trimmed)) {
                if let Ok(resp) = client.get(&whoami_url).headers(headers).send().await {
                    if resp.status().is_success() {
                        connected = true;
                        if let Ok(val) = resp.json::<Value>().await {
                            username = val["name"]
                                .as_str()
                                .or_else(|| val["fullname"].as_str())
                                .map(|s| s.to_string());
                        }
                    }
                }
            }
        }

        let repo_url = format!("{}/api/models/{}", self.hf_base_url, spec.repo_id);
        let mut repo_req = client.get(&repo_url);
        if let Some(headers) = hf_auth_headers(Some(trimmed)) {
            repo_req = repo_req.headers(headers);
        }
        let access_granted = match repo_req.send().await {
            Ok(resp) => Some(resp.status().is_success()),
            Err(_) => Some(false),
        };

        let message = if !trimmed.is_empty() && !connected {
            "Hugging Face token was rejected (401 Unauthorized).".to_string()
        } else if access_granted == Some(true) {
            match &username {
                Some(user) => format!("Connected as {user} — repo accessible."),
                None => "Repository accessible.".to_string(),
            }
        } else {
            "Repository access check failed or requires authorization.".to_string()
        };

        Ok(HuggingFaceAuthStatus {
            connected,
            source,
            username,
            provider_id: Some(spec.provider_id.to_string()),
            repo_id: Some(spec.repo_id.to_string()),
            access_granted,
            message,
        })
    }

    pub fn download_state(&self, provider_id: &str) -> Result<ModelDownloadStatus, String> {
        let spec = find_spec(provider_id)
            .ok_or_else(|| format!("unknown model provider: {provider_id}"))?;

        let target_dir = self.model_root.join(spec.folder_name);
        let installed = self.is_spec_installed(spec);
        let revision = read_revision_marker(&target_dir);
        let (state, message) = self
            .get_download_state(spec.provider_id)
            .unwrap_or_else(|| {
                if installed {
                    ("completed".to_string(), None)
                } else {
                    ("idle".to_string(), None)
                }
            });

        Ok(ModelDownloadStatus {
            provider_id: spec.provider_id.to_string(),
            state,
            message,
            local_path: target_dir.to_string_lossy().into_owned(),
            revision,
        })
    }

    pub fn delete(&self, provider_id: &str) -> Result<ModelStatus, String> {
        let spec = find_spec(provider_id)
            .ok_or_else(|| format!("unknown model provider: {provider_id}"))?;

        let target_dir = self.model_root.join(spec.folder_name);
        if target_dir.exists() {
            std::fs::remove_dir_all(&target_dir)
                .map_err(|err| format!("failed removing {}: {err}", target_dir.display()))?;
        }
        self.set_download_state(
            spec.provider_id,
            "idle",
            Some("Model files deleted".to_string()),
        );
        Ok(self.status_for_spec(spec))
    }

    async fn fetch_repo_metadata(
        &self,
        client: &reqwest::Client,
        repo_id: &str,
        hf_token: Option<&str>,
    ) -> Result<HfModelMetadata, ModelError> {
        let url = format!("{}/api/models/{repo_id}", self.hf_base_url);
        let mut req = client.get(&url);
        if let Some(headers) = hf_auth_headers(hf_token) {
            req = req.headers(headers);
        }
        let resp = req
            .send()
            .await
            .map_err(|e| ModelError::Http(e.to_string()))?;
        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            return Err(ModelError::Http(format!("HTTP {status}: {body}")));
        }
        resp.json::<HfModelMetadata>()
            .await
            .map_err(|e| ModelError::InvalidResponse(e.to_string()))
    }

    fn is_spec_installed(&self, spec: &ModelSpec) -> bool {
        let target_dir = self.model_root.join(spec.folder_name);
        directory_has_files(&target_dir)
            || fluid_audio_cache_dir(spec.folder_name)
                .as_ref()
                .is_some_and(|p| directory_has_files(p))
    }

    fn set_download_state(&self, provider_id: &str, state: &str, message: Option<String>) {
        let mut guard = self
            .download_states
            .lock()
            .expect("model manager mutex poisoned");
        guard.insert(provider_id.to_string(), (state.to_string(), message));
    }

    fn get_download_state(&self, provider_id: &str) -> Option<(String, Option<String>)> {
        let guard = self
            .download_states
            .lock()
            .expect("model manager mutex poisoned");
        guard.get(provider_id).cloned()
    }

    fn status_for_spec(&self, spec: &ModelSpec) -> ModelStatus {
        let target_dir = self.model_root.join(spec.folder_name);
        let installed = self.is_spec_installed(spec);
        let installed_revision = read_revision_marker(&target_dir);

        let (download_state, download_message) = self
            .get_download_state(spec.provider_id)
            .unwrap_or_else(|| {
                if installed {
                    ("completed".to_string(), None)
                } else {
                    ("idle".to_string(), None)
                }
            });

        ModelStatus {
            provider_id: spec.provider_id.to_string(),
            label: spec.label.to_string(),
            repo_id: spec.repo_id.to_string(),
            local_path: target_dir.to_string_lossy().into_owned(),
            installed,
            category: spec.category.to_string(),
            recommendation: Some(spec.recommendation.to_string()),
            detail: Some(spec.detail.to_string()),
            size: Some(spec.size.to_string()),
            precision: Some(spec.precision.to_string()),
            requires_hf_auth: false,
            agreement_url: None,
            license: Some(spec.license.to_string()),
            installed_revision,
            remote_revision: None,
            update_available: None,
            missing_files: if installed {
                Vec::new()
            } else {
                vec![spec.folder_name.to_string()]
            },
            download_state,
            download_message,
        }
    }
}

#[derive(Debug, Deserialize)]
struct HfSibling {
    rfilename: String,
}

#[derive(Debug, Deserialize)]
struct HfModelMetadata {
    sha: Option<String>,
    #[serde(default)]
    siblings: Vec<HfSibling>,
}

fn find_spec(provider_id: &str) -> Option<&'static ModelSpec> {
    let canonical = canonical_provider_id(provider_id);
    MODEL_SPECS.iter().find(|s| s.provider_id == canonical)
}

fn select_gguf_filename(siblings: &[HfSibling]) -> Option<String> {
    let ggufs: Vec<&str> = siblings
        .iter()
        .map(|s| s.rfilename.as_str())
        .filter(|name| name.to_ascii_lowercase().ends_with(".gguf"))
        .collect();
    if let Some(q4_k_m) = ggufs
        .iter()
        .find(|name| name.to_ascii_lowercase().contains("q4_k_m"))
    {
        return Some((*q4_k_m).to_string());
    }
    ggufs.first().map(|s| (*s).to_string())
}

fn hf_auth_headers(hf_token: Option<&str>) -> Option<HeaderMap> {
    let token = hf_token?.trim();
    if token.is_empty() {
        return None;
    }
    let val = HeaderValue::from_str(&format!("Bearer {token}")).ok()?;
    let mut map = HeaderMap::new();
    map.insert(AUTHORIZATION, val);
    Some(map)
}

fn format_progress_message(basename: &str, downloaded: u64, total: Option<u64>) -> String {
    let mb = downloaded as f64 / (1024.0 * 1024.0);
    if let Some(total_bytes) = total.filter(|t| *t > 0) {
        let pct = ((downloaded as f64 / total_bytes as f64) * 100.0).min(100.0);
        let total_mb = total_bytes as f64 / (1024.0 * 1024.0);
        format!("Downloading {basename} ({pct:.0}% · {mb:.1} MB / {total_mb:.1} MB)")
    } else {
        format!("Downloading {basename} ({mb:.1} MB downloaded)")
    }
}

fn read_revision_marker(target_dir: &Path) -> Option<String> {
    std::fs::read_to_string(target_dir.join(REVISION_MARKER_FILE))
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

fn default_model_root() -> PathBuf {
    if let Some(app_support) = std::env::var_os("OMNIVOICE_APP_SUPPORT_DIR") {
        if !app_support.is_empty() {
            return PathBuf::from(app_support).join("Models");
        }
    }
    if let Some(home) = std::env::var_os("HOME") {
        return PathBuf::from(home)
            .join("Library")
            .join("Application Support")
            .join("OmniSpeak")
            .join("Models");
    }
    PathBuf::from("models")
}

fn fluid_audio_cache_dir(folder_name: &str) -> Option<PathBuf> {
    let home = std::env::var_os("HOME")?;
    Some(
        PathBuf::from(home)
            .join("Library")
            .join("Application Support")
            .join("FluidAudio")
            .join("Models")
            .join(folder_name),
    )
}

fn directory_has_files(path: &Path) -> bool {
    let Ok(entries) = std::fs::read_dir(path) else {
        return false;
    };
    entries
        .flatten()
        .any(|entry| !entry.file_name().to_string_lossy().starts_with('.'))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::Arc;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tokio::net::TcpListener;

    async fn spawn_mock_hf(rev_v2: Arc<AtomicBool>) -> String {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        tokio::spawn(async move {
            loop {
                let Ok((mut stream, _)) = listener.accept().await else {
                    break;
                };
                let rev_flag = rev_v2.clone();
                tokio::spawn(async move {
                    let mut buf = [0u8; 4096];
                    let Ok(n) = stream.read(&mut buf).await else {
                        return;
                    };
                    let req = String::from_utf8_lossy(&buf[..n]);
                    let first_line = req.lines().next().unwrap_or("");
                    let path = first_line.split_whitespace().nth(1).unwrap_or("/");
                    let lower = req.to_ascii_lowercase();

                    let (status, content_type, body): (&str, &str, Vec<u8>) =
                        if path == "/api/whoami-v2" {
                            if lower.contains("authorization: bearer good-token") {
                                (
                                    "200 OK",
                                    "application/json",
                                    br#"{"name":"tester"}"#.to_vec(),
                                )
                            } else {
                                (
                                    "401 Unauthorized",
                                    "application/json",
                                    br#"{"error":"invalid token"}"#.to_vec(),
                                )
                            }
                        } else if path.starts_with("/api/models/") {
                            let sha = if rev_flag.load(Ordering::SeqCst) {
                                "rev-sha-2"
                            } else {
                                "rev-sha-1"
                            };
                            let payload = serde_json::json!({
                                "sha": sha,
                                "siblings": [
                                    {"rfilename": "README.md"},
                                    {"rfilename": "qwen3-1.7b-q4_k_m.gguf"}
                                ]
                            })
                            .to_string();
                            ("200 OK", "application/json", payload.into_bytes())
                        } else if path.ends_with("/resolve/main/qwen3-1.7b-q4_k_m.gguf") {
                            ("200 OK", "application/octet-stream", b"GGUF_MOCK_BYTES".to_vec())
                        } else {
                            ("404 Not Found", "text/plain", b"not found".to_vec())
                        };

                    let header = format!(
                        "HTTP/1.1 {status}\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                        body.len()
                    );
                    let _ = stream.write_all(header.as_bytes()).await;
                    let _ = stream.write_all(&body).await;
                });
            }
        });
        format!("http://{addr}")
    }

    #[tokio::test]
    async fn streams_gguf_download_checks_updates_and_validates_hf_token() {
        let rev_v2 = Arc::new(AtomicBool::new(false));
        let hf_base = spawn_mock_hf(rev_v2.clone()).await;
        let temp_root =
            std::env::temp_dir().join(format!("omnivoice-models-hf-{}", uuid::Uuid::new_v4()));
        let manager = ModelManager::with_hf_base_url(&temp_root, &hf_base);
        let client = reqwest::Client::new();

        // Legacy alias resolves cleanly to canonical GGUF model
        let queued = manager.queue_download("qwen3-1.7b-mlx-4bit").unwrap();
        assert_eq!(queued.provider_id, "qwen3-1.7b-gguf-q4");
        assert_eq!(queued.state, "downloading");

        let done = manager
            .run_download(&client, "qwen3-1.7b-mlx-4bit", None)
            .await
            .unwrap();
        assert_eq!(done.state, "completed");
        assert_eq!(done.revision.as_deref(), Some("rev-sha-1"));

        let gguf = manager.find_gguf_file("qwen3-1.7b-mlx-4bit").unwrap();
        assert_eq!(std::fs::read(&gguf).unwrap(), b"GGUF_MOCK_BYTES");
        assert!(!temp_root
            .join("qwen3-1.7b-gguf-q4")
            .join("qwen3-1.7b-q4_k_m.gguf.part")
            .exists());

        let update_before = manager
            .check_update(&client, "qwen3-1.7b-gguf-q4", None)
            .await
            .unwrap();
        assert!(!update_before.update_available);
        assert_eq!(update_before.installed_revision.as_deref(), Some("rev-sha-1"));

        rev_v2.store(true, Ordering::SeqCst);
        let update_after = manager
            .check_update(&client, "qwen3-1.7b-gguf-q4", None)
            .await
            .unwrap();
        assert!(update_after.update_available);
        assert_eq!(update_after.remote_revision, "rev-sha-2");

        let good_auth = manager
            .validate_huggingface_access(&client, "qwen3-1.7b-gguf-q4", "good-token")
            .await
            .unwrap();
        assert!(good_auth.connected);
        assert_eq!(good_auth.username.as_deref(), Some("tester"));
        assert_eq!(good_auth.access_granted, Some(true));

        let bad_auth = manager
            .validate_huggingface_access(&client, "qwen3-1.7b-gguf-q4", "bad-token")
            .await
            .unwrap();
        assert!(!bad_auth.connected);
        assert!(bad_auth.username.is_none());

        let deleted = manager.delete("qwen3-1.7b-gguf-q4").unwrap();
        assert!(!deleted.installed);
        let _ = std::fs::remove_dir_all(&temp_root);
    }
}
