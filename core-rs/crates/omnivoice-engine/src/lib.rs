use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Instant;

use axum::extract::{Path, Query, Request, State};
use axum::http::{HeaderMap, HeaderValue, StatusCode};
use axum::middleware::{self, Next};
use axum::response::{Html, IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use omnivoice_core::reqwest;
use omnivoice_core::cleanup::{
    build_llm_cleanup_messages, clean_transcript, sanitize_llm_cleanup_output, ChatMessage,
    CleanupRequest, CleanupResponse,
};
use omnivoice_core::grammar::{
    check_and_correct_grammar, GrammarCheckRequest, GrammarCheckResponse,
};
use omnivoice_core::llm::{complete_chat, list_models, llm_config_is_ready};
use omnivoice_core::local_llm::LocalLlmRuntime;
use omnivoice_core::models::{
    HuggingFaceAuthStatus, ModelDownloadStatus, ModelError, ModelManager, ModelStatus,
    ModelUpdateInfo,
};
use omnivoice_core::security::{
    is_allowed_host, is_allowed_origin, token_matches, ENGINE_AUTH_COOKIE, ENGINE_AUTH_HEADER,
};
use omnivoice_core::store::{
    merge_json_objects, ConversationAssistCardRecord, ConversationDetail,
    ConversationSegmentRecord, ConversationSessionRecord, EngineEvent, RuntimeStore, StoreError,
    TranscriptRecord,
};
use serde::{Deserialize, Serialize};
use serde_json::json;

pub struct AppState {
    pub store: RuntimeStore,
    pub models: Arc<ModelManager>,
    pub local_llm: Arc<LocalLlmRuntime>,
    pub http_client: reqwest::Client,
    pub started_at: Instant,
    pub auth_token: Option<String>,
}

impl AppState {
    pub fn new(store: RuntimeStore, auth_token: Option<String>) -> Self {
        Self::with_model_root(store, auth_token, None)
    }

    pub fn with_model_root(
        store: RuntimeStore,
        auth_token: Option<String>,
        model_root: Option<PathBuf>,
    ) -> Self {
        let models = Arc::new(match model_root {
            Some(root) => ModelManager::new(root),
            None => ModelManager::from_env(),
        });
        Self::with_custom(store, auth_token, models, Arc::new(LocalLlmRuntime::new()))
    }

    pub fn with_custom(
        store: RuntimeStore,
        auth_token: Option<String>,
        models: Arc<ModelManager>,
        local_llm: Arc<LocalLlmRuntime>,
    ) -> Self {
        Self {
            store,
            models,
            local_llm,
            http_client: reqwest::Client::new(),
            started_at: Instant::now(),
            auth_token: auth_token
                .map(|t| t.trim().to_string())
                .filter(|t| !t.is_empty()),
        }
    }

    fn effective_token(&self) -> Option<String> {
        if let Some(token) = &self.auth_token {
            return Some(token.clone());
        }
        std::env::var("OMNIVOICE_ENGINE_TOKEN")
            .ok()
            .map(|t| t.trim().to_string())
            .filter(|t| !t.is_empty())
    }
}

pub fn build_router(state: Arc<AppState>) -> Router {
    Router::new()
        .route("/", get(dashboard))
        .route("/health", get(health))
        .route("/api/status", get(engine_status))
        .route(
            "/api/settings",
            get(get_voice_settings)
                .patch(patch_voice_settings)
                .delete(delete_voice_settings),
        )
        .route("/api/settings/profiles", get(list_voice_settings_profiles))
        .route("/api/theme/default", get(default_theme))
        .route("/providers", get(providers))
        .route("/diarization/providers", get(diarization_providers))
        .route("/translation/providers", get(translation_providers))
        .route("/cleanup/providers", get(cleanup_providers))
        .route("/models", get(list_models_endpoint))
        .route("/models/:provider_id", axum::routing::delete(delete_model))
        .route("/models/:provider_id/update", get(model_update))
        .route(
            "/models/:provider_id/download",
            get(model_download_status).post(start_model_download),
        )
        .route("/huggingface/validate", post(validate_huggingface))
        .route("/cleanup", post(cleanup))
        .route("/api/grammar", post(check_grammar_endpoint))
        .route("/api/ai/handoff", post(ai_handoff))
        .route("/api/ai/chat", post(ai_chat))
        .route("/api/ai/models", post(ai_models))
        .route("/api/transcripts", get(list_transcripts))
        .route("/api/events", get(list_events))
        .route(
            "/api/conversations",
            get(list_conversations).post(create_conversation),
        )
        .route(
            "/api/conversations/:session_id",
            get(get_conversation)
                .patch(update_conversation)
                .delete(delete_conversation),
        )
        .route(
            "/api/conversations/:session_id/stop",
            post(stop_conversation),
        )
        .route(
            "/api/conversations/:session_id/segments",
            post(add_conversation_segment),
        )
        .route(
            "/api/conversations/:session_id/assist-cards",
            post(add_conversation_assist_card),
        )
        .layer(middleware::from_fn_with_state(
            state.clone(),
            security_middleware,
        ))
        .with_state(state)
}

async fn security_middleware(
    State(state): State<Arc<AppState>>,
    request: Request,
    next: Next,
) -> Response {
    let host = request
        .headers()
        .get("host")
        .and_then(|v| v.to_str().ok());
    if !is_allowed_host(host) {
        return (
            StatusCode::FORBIDDEN,
            Json(json!({ "detail": "forbidden host" })),
        )
            .into_response();
    }

    let origin = request
        .headers()
        .get("origin")
        .and_then(|v| v.to_str().ok());
    if !is_allowed_origin(origin) {
        return (
            StatusCode::FORBIDDEN,
            Json(json!({ "detail": "forbidden origin" })),
        )
            .into_response();
    }

    let path = request.uri().path().to_string();
    let expected = state.effective_token();
    if let Some(ref expected_token) = expected {
        if path != "/health" && !path.starts_with("/assets/") {
            let provided = extract_request_token(&request);
            if !token_matches(provided.as_deref(), expected_token) {
                return (
                    StatusCode::UNAUTHORIZED,
                    Json(json!({ "detail": "unauthorized" })),
                )
                    .into_response();
            }
        }
    }

    let query_token = query_param(request.uri().query(), "token");
    let mut response = next.run(request).await;
    if let Some(expected_token) = expected {
        if path == "/" && token_matches(query_token.as_deref(), &expected_token) {
            if let Ok(cookie) = HeaderValue::from_str(&format!(
                "{ENGINE_AUTH_COOKIE}={expected_token}; HttpOnly; SameSite=Strict"
            )) {
                response
                    .headers_mut()
                    .append(axum::http::header::SET_COOKIE, cookie);
            }
        }
    }
    response
}

fn extract_request_token(request: &Request) -> Option<String> {
    if let Some(header) = request
        .headers()
        .get(ENGINE_AUTH_HEADER)
        .and_then(|v| v.to_str().ok())
    {
        return Some(header.to_string());
    }
    if let Some(token) = query_param(request.uri().query(), "token") {
        return Some(token);
    }
    if let Some(cookies) = request
        .headers()
        .get(axum::http::header::COOKIE)
        .and_then(|v| v.to_str().ok())
    {
        for part in cookies.split(';') {
            let trimmed = part.trim();
            if let Some((k, v)) = trimmed.split_once('=') {
                if k.trim() == ENGINE_AUTH_COOKIE {
                    return Some(v.trim().to_string());
                }
            }
        }
    }
    None
}

fn query_param(query: Option<&str>, key: &str) -> Option<String> {
    let query = query?;
    for pair in query.split('&') {
        if let Some((k, v)) = pair.split_once('=') {
            if k == key {
                return Some(v.to_string());
            }
        }
    }
    None
}

async fn health() -> Json<serde_json::Value> {
    Json(json!({ "status": "ok" }))
}

async fn dashboard() -> Html<&'static str> {
    Html(
        "<!doctype html><html><head><meta charset=\"utf-8\"><title>OmniSpeak Rust Engine</title></head><body><h1>OmniSpeak Rust Engine</h1><p>Running in-process CoreML ANE + Rust omnivoice-engine mode.</p></body></html>",
    )
}

#[derive(Serialize)]
struct ThemePayloadResponse {
    id: String,
    name: String,
    css_variables: HashMap<String, String>,
}

async fn default_theme() -> Json<ThemePayloadResponse> {
    let mut vars = HashMap::new();
    vars.insert("--ov-accent".to_string(), "#38BDF8".to_string());
    vars.insert("--ov-accent-text".to_string(), "#38BDF8".to_string());
    vars.insert("--ov-accent-secondary".to_string(), "#818CF8".to_string());
    vars.insert("--ov-accent-secondary-text".to_string(), "#818CF8".to_string());
    vars.insert("--ov-bg".to_string(), "#06121C".to_string());
    vars.insert("--ov-surface".to_string(), "rgba(6, 18, 28, 0.36)".to_string());
    vars.insert("--ov-surface-strong".to_string(), "rgba(6, 18, 28, 0.54)".to_string());
    vars.insert("--ov-text".to_string(), "#F8FAFC".to_string());
    vars.insert("--ov-muted".to_string(), "rgba(248, 250, 252, 0.64)".to_string());
    vars.insert("--ov-on-accent".to_string(), "#06121C".to_string());
    vars.insert("--ov-border".to_string(), "rgba(56, 189, 248, 0.26)".to_string());
    vars.insert("--ov-glow".to_string(), "rgba(56, 189, 248, 0.34)".to_string());
    vars.insert("--ov-caption-bg".to_string(), "rgba(6, 18, 28, 0.14)".to_string());
    Json(ThemePayloadResponse {
        id: "auroraBlue".to_string(),
        name: "Aurora Blue".to_string(),
        css_variables: vars,
    })
}

#[derive(Serialize)]
struct EngineStatusResponse {
    status: String,
    engine: String,
    uptime_seconds: u64,
    transcripts: usize,
    events: usize,
    conversations: usize,
}

async fn engine_status(State(state): State<Arc<AppState>>) -> Result<Json<EngineStatusResponse>, ApiError> {
    let (transcripts, events, conversations) = state.store.counts()?;
    Ok(Json(EngineStatusResponse {
        status: "ok".to_string(),
        engine: "omnivoice-core-rs".to_string(),
        uptime_seconds: state.started_at.elapsed().as_secs(),
        transcripts,
        events,
        conversations,
    }))
}

#[derive(Deserialize)]
struct SettingsProfileQuery {
    profile: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct VoiceSettingsEnvelope {
    profile_id: String,
    mode: String,
    effective: serde_json::Value,
    defaults: serde_json::Value,
    #[serde(rename = "override")]
    override_settings: Option<serde_json::Value>,
    profiles: Vec<String>,
    updated_at: Option<String>,
}

fn normalize_profile_id(raw: Option<&str>) -> Result<String, ApiError> {
    let cleaned = raw.unwrap_or("default").trim().to_ascii_lowercase();
    if cleaned.is_empty() {
        return Ok("default".to_string());
    }
    let valid = cleaned.len() <= 48
        && cleaned
            .chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-' || c == '_');
    if !valid {
        return Err(ApiError::BadRequest(
            "profile must be 1-48 chars of [a-z0-9_-]".to_string(),
        ));
    }
    Ok(cleaned)
}

fn baseline_voice_settings() -> serde_json::Value {
    json!({
        "asr_provider": "parakeet-tdt-coreml-ane",
        "style": "neutral",
        "llm_cleanup_enabled": true,
        "llm_cleanup_backend": "agent",
        "llm_cleanup_agent_id": "antigravity",
        "llm_cleanup_local_model_id": "qwen3-1.7b-mlx-4bit",
        "auto_learn_corrections_enabled": true,
        "recording_sound_cues_enabled": true,
        "idle_mlx_auto_unload_minutes": 15,
        "service_mode": {
            "enabled": false,
            "deepgram_model": "nova-3",
            "deepgram_language": "multi",
            "deepgram_smart_format": true
        }
    })
}

fn build_settings_envelope(
    store: &RuntimeStore,
    profile_id: &str,
) -> Result<VoiceSettingsEnvelope, ApiError> {
    let stored_default = store.get_settings_profile("default")?;
    let defaults = match &stored_default {
        Some((val, _)) => merge_json_objects(&baseline_voice_settings(), val),
        None => baseline_voice_settings(),
    };
    let mut updated_at = stored_default.as_ref().map(|(_, ts)| ts.clone());

    let (mode, override_settings, effective) = if profile_id == "default" {
        ("shared".to_string(), None, defaults.clone())
    } else if let Some((ov, ov_ts)) = store.get_settings_profile(profile_id)? {
        updated_at = Some(ov_ts);
        let merged = merge_json_objects(&defaults, &ov);
        ("custom".to_string(), Some(ov), merged)
    } else {
        ("shared".to_string(), None, defaults.clone())
    };

    let mut profiles: Vec<String> = store
        .list_settings_profiles()?
        .into_iter()
        .map(|(id, _)| id)
        .collect();
    if !profiles.iter().any(|p| p == "default") {
        profiles.insert(0, "default".to_string());
    }

    Ok(VoiceSettingsEnvelope {
        profile_id: profile_id.to_string(),
        mode,
        effective,
        defaults,
        override_settings,
        profiles,
        updated_at,
    })
}

async fn get_voice_settings(
    State(state): State<Arc<AppState>>,
    Query(query): Query<SettingsProfileQuery>,
) -> Result<Json<VoiceSettingsEnvelope>, ApiError> {
    let profile_id = normalize_profile_id(query.profile.as_deref())?;
    Ok(Json(build_settings_envelope(&state.store, &profile_id)?))
}

async fn patch_voice_settings(
    State(state): State<Arc<AppState>>,
    Query(query): Query<SettingsProfileQuery>,
    Json(patch): Json<serde_json::Value>,
) -> Result<Json<VoiceSettingsEnvelope>, ApiError> {
    if !patch.is_object() {
        return Err(ApiError::BadRequest(
            "settings patch must be a JSON object".to_string(),
        ));
    }
    let profile_id = normalize_profile_id(query.profile.as_deref())?;
    state.store.upsert_settings_profile(&profile_id, &patch)?;
    Ok(Json(build_settings_envelope(&state.store, &profile_id)?))
}

async fn delete_voice_settings(
    State(state): State<Arc<AppState>>,
    Query(query): Query<SettingsProfileQuery>,
) -> Result<Json<VoiceSettingsEnvelope>, ApiError> {
    let profile_id = normalize_profile_id(query.profile.as_deref())?;
    if profile_id == "default" {
        return Err(ApiError::BadRequest(
            "cannot delete the shared default profile".to_string(),
        ));
    }
    state.store.delete_settings_profile(&profile_id)?;
    Ok(Json(build_settings_envelope(&state.store, &profile_id)?))
}

async fn list_voice_settings_profiles(
    State(state): State<Arc<AppState>>,
) -> Result<Json<serde_json::Value>, ApiError> {
    let rows = state.store.list_settings_profiles()?;
    let profiles: Vec<serde_json::Value> = rows
        .into_iter()
        .map(|(profile_id, updated_at)| json!({ "profileId": profile_id, "updatedAt": updated_at }))
        .collect();
    Ok(Json(json!({ "profiles": profiles })))
}

#[derive(Serialize)]
struct ProviderInfoResponse {
    id: String,
    label: String,
    available: bool,
    reason: Option<String>,
}

async fn providers() -> Json<Vec<ProviderInfoResponse>> {
    Json(vec![
        ProviderInfoResponse {
            id: "parakeet-tdt-coreml-ane".to_string(),
            label: "Parakeet TDT CoreML (Neural Engine)".to_string(),
            available: cfg!(target_os = "macos"),
            reason: if cfg!(target_os = "macos") {
                None
            } else {
                Some("CoreML ANE is available on Apple Silicon macOS".to_string())
            },
        },
        ProviderInfoResponse {
            id: "apple-speech".to_string(),
            label: "Apple Speech (Built-in)".to_string(),
            available: cfg!(target_os = "macos"),
            reason: if cfg!(target_os = "macos") {
                None
            } else {
                Some("Apple Speech is available on macOS 26+".to_string())
            },
        },
    ])
}

async fn diarization_providers() -> Json<Vec<ProviderInfoResponse>> {
    Json(vec![
        ProviderInfoResponse {
            id: "sortformer-coreml-ane".to_string(),
            label: "Sortformer Diarizer (CoreML ANE)".to_string(),
            available: cfg!(target_os = "macos"),
            reason: None,
        },
        ProviderInfoResponse {
            id: "none".to_string(),
            label: "Off".to_string(),
            available: true,
            reason: None,
        },
    ])
}

async fn translation_providers() -> Json<Vec<ProviderInfoResponse>> {
    Json(vec![ProviderInfoResponse {
        id: "apple-translation".to_string(),
        label: "Apple Translation (On-device)".to_string(),
        available: cfg!(target_os = "macos"),
        reason: None,
    }])
}

async fn cleanup_providers(
    State(state): State<Arc<AppState>>,
) -> Json<Vec<ProviderInfoResponse>> {
    let (q1_avail, q1_reason) = state
        .local_llm
        .status_summary(&state.http_client, &state.models, "qwen3-1.7b-gguf-q4")
        .await;
    let (q4_avail, q4_reason) = state
        .local_llm
        .status_summary(
            &state.http_client,
            &state.models,
            "qwen3-4b-instruct-gguf-q4",
        )
        .await;

    Json(vec![
        ProviderInfoResponse {
            id: "deterministic".to_string(),
            label: "Rust Deterministic Cleanup".to_string(),
            available: true,
            reason: None,
        },
        ProviderInfoResponse {
            id: "qwen3-1.7b-gguf-q4".to_string(),
            label: "Qwen3 1.7B Cleanup (GGUF Q4)".to_string(),
            available: q1_avail,
            reason: q1_reason,
        },
        ProviderInfoResponse {
            id: "qwen3-4b-instruct-gguf-q4".to_string(),
            label: "Qwen3 4B Instruct (GGUF Q4)".to_string(),
            available: q4_avail,
            reason: q4_reason,
        },
    ])
}

async fn list_models_endpoint(State(state): State<Arc<AppState>>) -> Json<Vec<ModelStatus>> {
    Json(state.models.list_statuses())
}

fn bearer_token(headers: &HeaderMap) -> Option<String> {
    let raw = headers
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())?
        .trim();
    let stripped = raw
        .strip_prefix("Bearer ")
        .or_else(|| raw.strip_prefix("bearer "))
        .unwrap_or(raw)
        .trim();
    if stripped.is_empty() {
        None
    } else {
        Some(stripped.to_string())
    }
}

fn map_model_error(err: ModelError) -> ApiError {
    match err {
        ModelError::UnknownProvider(msg) => ApiError::NotFound(msg),
        ModelError::Http(msg) | ModelError::InvalidResponse(msg) => ApiError::BadGateway(msg),
        ModelError::Io(msg) => ApiError::Internal(msg),
    }
}

async fn model_update(
    State(state): State<Arc<AppState>>,
    Path(provider_id): Path<String>,
    headers: HeaderMap,
) -> Result<Json<ModelUpdateInfo>, ApiError> {
    let token = bearer_token(&headers);
    let info = state
        .models
        .check_update(&state.http_client, &provider_id, token.as_deref())
        .await
        .map_err(map_model_error)?;
    Ok(Json(info))
}

#[derive(Deserialize)]
struct HuggingFaceValidateBody {
    token: String,
    provider_id: String,
}

async fn validate_huggingface(
    State(state): State<Arc<AppState>>,
    Json(body): Json<HuggingFaceValidateBody>,
) -> Result<Json<HuggingFaceAuthStatus>, ApiError> {
    let status = state
        .models
        .validate_huggingface_access(&state.http_client, &body.provider_id, &body.token)
        .await
        .map_err(map_model_error)?;
    Ok(Json(status))
}

async fn start_model_download(
    State(state): State<Arc<AppState>>,
    Path(provider_id): Path<String>,
    headers: HeaderMap,
) -> Result<Json<ModelDownloadStatus>, ApiError> {
    let token = bearer_token(&headers);
    let status = state
        .models
        .queue_download(&provider_id)
        .map_err(map_model_error)?;
    let _ = state.store.record_event(
        "model.download.queued",
        &format!("Queued model download for {provider_id}"),
        "info",
        json!({ "provider_id": provider_id, "state": status.state }),
    );
    if status.state == "downloading" {
        let bg_state = state.clone();
        let bg_provider = provider_id.clone();
        tokio::spawn(async move {
            match bg_state
                .models
                .run_download(&bg_state.http_client, &bg_provider, token.as_deref())
                .await
            {
                Ok(done) => {
                    let _ = bg_state.store.record_event(
                        "model.download.completed",
                        &format!("Completed model download for {bg_provider}"),
                        "info",
                        json!({
                            "provider_id": bg_provider,
                            "state": done.state,
                            "revision": done.revision,
                        }),
                    );
                }
                Err(err) => {
                    let _ = bg_state.store.record_event(
                        "model.download.failed",
                        &format!("Model download failed for {bg_provider}"),
                        "error",
                        json!({
                            "provider_id": bg_provider,
                            "error": err.to_string(),
                        }),
                    );
                }
            }
        });
    }
    Ok(Json(status))
}

async fn model_download_status(
    State(state): State<Arc<AppState>>,
    Path(provider_id): Path<String>,
) -> Result<Json<ModelDownloadStatus>, ApiError> {
    let status = state
        .models
        .download_state(&provider_id)
        .map_err(ApiError::NotFound)?;
    Ok(Json(status))
}

async fn delete_model(
    State(state): State<Arc<AppState>>,
    Path(provider_id): Path<String>,
) -> Result<Json<ModelStatus>, ApiError> {
    let status = state
        .models
        .delete(&provider_id)
        .map_err(ApiError::NotFound)?;
    let _ = state.store.record_event(
        "model.deleted",
        &format!("Deleted model files for {provider_id}"),
        "info",
        json!({ "provider_id": provider_id, "local_path": status.local_path }),
    );
    Ok(Json(status))
}

fn apply_llm_cleanup_outcome(
    state: &AppState,
    request: &CleanupRequest,
    llm_provider: &str,
    llm_model: &str,
    outcome: Result<String, String>,
    result: &mut CleanupResponse,
) {
    match outcome {
        Ok(raw_llm) => {
            let polished = sanitize_llm_cleanup_output(
                &raw_llm,
                &request.raw_transcript,
                &request.dictionary_terms,
                &request.dictionary_entries,
            );
            if !polished.is_empty() {
                *result = CleanupResponse {
                    text: polished,
                    cleanup_applied: true,
                    llm_applied: Some(true),
                    llm_fallback_reason: None,
                };
            } else {
                result.llm_applied = Some(false);
                result.llm_fallback_reason = Some("LLM returned empty text".to_string());
            }
        }
        Err(err) => {
            let _ = state.store.record_event(
                "cleanup.llm_fallback",
                "LLM cleanup failed; fell back to deterministic cleanup",
                "warning",
                json!({ "provider": llm_provider, "model": llm_model, "error": err }),
            );
            result.llm_applied = Some(false);
            result.llm_fallback_reason = Some(err);
        }
    }
}

async fn cleanup(
    State(state): State<Arc<AppState>>,
    Json(request): Json<CleanupRequest>,
) -> Result<Json<CleanupResponse>, ApiError> {
    let mut result = clean_transcript(&request);
    if let Some(ref llm) = request.llm {
        if llm.enabled && !request.style.eq_ignore_ascii_case("raw") && !result.text.trim().is_empty()
        {
            if llm.transport == "local_mlx" || llm.transport == "local_gguf" {
                let messages = build_llm_cleanup_messages(&request, &result.text);
                let outcome = state
                    .local_llm
                    .complete_cleanup(
                        &state.http_client,
                        &state.models,
                        &llm.model,
                        &messages,
                        llm.timeout_seconds,
                    )
                    .await
                    .map_err(|e| e.to_string());
                apply_llm_cleanup_outcome(
                    &state,
                    &request,
                    &llm.provider,
                    &llm.model,
                    outcome,
                    &mut result,
                );
            } else if llm_config_is_ready(llm) {
                let messages = build_llm_cleanup_messages(&request, &result.text);
                let outcome = complete_chat(
                    &state.http_client,
                    &llm.transport,
                    &llm.base_url,
                    &llm.api_key,
                    &llm.oauth_access_token,
                    &llm.headers,
                    &llm.model,
                    &messages,
                    llm.timeout_seconds,
                )
                .await
                .map_err(|e| e.to_string());
                apply_llm_cleanup_outcome(
                    &state,
                    &request,
                    &llm.provider,
                    &llm.model,
                    outcome,
                    &mut result,
                );
            }
        }
    }

    let _ = state.store.record_transcript(
        "cleanup",
        &request.raw_transcript,
        Some(&result.text),
        None,
        Some(&request.style),
        None,
        None,
        None,
    );
    let _ = state.store.record_event(
        "cleanup.completed",
        "Transcript cleanup completed",
        "info",
        json!({
            "style": request.style,
            "cleanup_applied": result.cleanup_applied,
            "llm_applied": result.llm_applied.unwrap_or(false),
            "raw_length": request.raw_transcript.len(),
            "cleaned_length": result.text.len(),
        }),
    );

    Ok(Json(result))
}

async fn check_grammar_endpoint(
    Json(request): Json<GrammarCheckRequest>,
) -> Json<GrammarCheckResponse> {
    let result = tokio::task::spawn_blocking(move || {
        check_and_correct_grammar(&request.text, &request.protected_terms)
    })
    .await
    .unwrap_or_else(|_| GrammarCheckResponse {
        text: String::new(),
        applied_count: 0,
        engine: "harper-core".to_string(),
        edits: Vec::new(),
    });
    Json(result)
}

#[derive(Deserialize)]
struct AiHandoffRequest {
    prompt: String,
    #[serde(default = "default_custom")]
    provider: String,
    #[serde(default)]
    base_url: String,
    #[serde(default)]
    model: String,
    #[serde(default)]
    api_key: String,
    #[serde(default = "default_openai_transport")]
    transport: String,
    #[serde(default)]
    oauth_access_token: String,
    #[serde(default)]
    headers: HashMap<String, String>,
    #[serde(default)]
    context: String,
}

fn default_custom() -> String {
    "custom".to_string()
}

fn default_openai_transport() -> String {
    "openai_compatible".to_string()
}

#[derive(Serialize)]
struct AiHandoffResponse {
    text: String,
    provider: String,
    model: String,
}

async fn ai_handoff(
    State(state): State<Arc<AppState>>,
    Json(request): Json<AiHandoffRequest>,
) -> Result<Json<AiHandoffResponse>, ApiError> {
    let model = request.model.trim().to_string();
    let base_url = request.base_url.trim().to_string();
    let prompt = request.prompt.trim().to_string();
    if model.is_empty() || prompt.is_empty() {
        return Err(ApiError::BadRequest(
            "AI endpoint, model, and prompt are required".to_string(),
        ));
    }
    let user_content = if request.context.trim().is_empty() {
        prompt
    } else {
        format!("{prompt}\n\nContext:\n{}", request.context.trim())
    };
    let messages = vec![
        ChatMessage {
            role: "system".to_string(),
            content: "You write concise, directly usable text to insert at the user's cursor. Return only the text to insert.".to_string(),
        },
        ChatMessage {
            role: "user".to_string(),
            content: user_content,
        },
    ];
    let text = complete_chat(
        &state.http_client,
        &request.transport,
        &base_url,
        request.api_key.trim(),
        request.oauth_access_token.trim(),
        &request.headers,
        &model,
        &messages,
        45.0,
    )
    .await
    .map_err(|e| ApiError::BadGateway(format!("AI handoff failed: {e}")))?;

    let _ = state.store.record_event(
        "ai_handoff.completed",
        "AI handoff completed",
        "info",
        json!({ "provider": request.provider, "model": model }),
    );
    Ok(Json(AiHandoffResponse {
        text,
        provider: request.provider,
        model,
    }))
}

#[derive(Deserialize)]
struct AiChatMessageBody {
    role: String,
    content: String,
}

#[derive(Deserialize)]
struct AiChatRequestBody {
    #[serde(default = "default_custom")]
    provider: String,
    #[serde(default)]
    base_url: String,
    #[serde(default)]
    model: String,
    #[serde(default)]
    api_key: String,
    #[serde(default = "default_openai_transport")]
    transport: String,
    #[serde(default)]
    oauth_access_token: String,
    #[serde(default)]
    headers: HashMap<String, String>,
    #[serde(default)]
    messages: Vec<AiChatMessageBody>,
}

async fn ai_chat(
    State(state): State<Arc<AppState>>,
    Json(request): Json<AiChatRequestBody>,
) -> Result<Json<AiHandoffResponse>, ApiError> {
    let model = request.model.trim().to_string();
    let base_url = request.base_url.trim().to_string();
    if model.is_empty() {
        return Err(ApiError::BadRequest(
            "AI endpoint and model are required".to_string(),
        ));
    }
    let mut messages = Vec::with_capacity(request.messages.len() + 1);
    if !request.messages.iter().any(|m| m.role == "system") {
        messages.push(ChatMessage {
            role: "system".to_string(),
            content: "You are OmniSpeak Ask AI, a helpful local assistant inside a dictation app. Answer concisely and directly.".to_string(),
        });
    }
    for msg in request.messages {
        messages.push(ChatMessage {
            role: msg.role,
            content: msg.content,
        });
    }
    let text = complete_chat(
        &state.http_client,
        &request.transport,
        &base_url,
        request.api_key.trim(),
        request.oauth_access_token.trim(),
        &request.headers,
        &model,
        &messages,
        90.0,
    )
    .await
    .map_err(|e| ApiError::BadGateway(format!("AI chat failed: {e}")))?;

    let _ = state.store.record_event(
        "ai_chat.completed",
        "AI chat completed",
        "info",
        json!({ "provider": request.provider, "model": model }),
    );
    Ok(Json(AiHandoffResponse {
        text,
        provider: request.provider,
        model,
    }))
}

#[derive(Deserialize)]
struct AiModelListRequestBody {
    #[serde(default = "default_custom")]
    provider: String,
    #[serde(default)]
    base_url: String,
    #[serde(default)]
    api_key: String,
    #[serde(default = "default_openai_transport")]
    transport: String,
    #[serde(default)]
    oauth_access_token: String,
    #[serde(default)]
    headers: HashMap<String, String>,
}

#[derive(Serialize)]
struct AiModelListResponseBody {
    provider: String,
    models: Vec<String>,
}

async fn ai_models(
    State(state): State<Arc<AppState>>,
    Json(request): Json<AiModelListRequestBody>,
) -> Result<Json<AiModelListResponseBody>, ApiError> {
    let models = list_models(
        &state.http_client,
        &request.transport,
        request.base_url.trim(),
        request.api_key.trim(),
        request.oauth_access_token.trim(),
        &request.headers,
        std::time::Duration::from_secs(20),
    )
    .await
    .map_err(|e| ApiError::BadGateway(format!("AI model refresh failed: {e}")))?;

    let _ = state.store.record_event(
        "ai_models.completed",
        "AI model refresh completed",
        "info",
        json!({ "provider": request.provider, "model_count": models.len() }),
    );
    Ok(Json(AiModelListResponseBody {
        provider: request.provider,
        models,
    }))
}

#[derive(Deserialize)]
struct LimitQuery {
    limit: Option<usize>,
}

async fn list_transcripts(
    State(state): State<Arc<AppState>>,
    Query(query): Query<LimitQuery>,
) -> Result<Json<Vec<TranscriptRecord>>, ApiError> {
    let limit = query.limit.unwrap_or(200).clamp(1, 1000);
    Ok(Json(state.store.list_transcripts(limit)?))
}

async fn list_events(
    State(state): State<Arc<AppState>>,
    Query(query): Query<LimitQuery>,
) -> Result<Json<Vec<EngineEvent>>, ApiError> {
    let limit = query.limit.unwrap_or(200).clamp(1, 1000);
    Ok(Json(state.store.list_events(limit)?))
}

#[derive(Deserialize)]
struct ConversationCreateBody {
    title: String,
    #[serde(default = "default_capture_mode")]
    capture_mode: String,
    #[serde(default = "default_asr_provider")]
    asr_provider: String,
    #[serde(default = "default_none")]
    diarization_provider: String,
    #[serde(default)]
    external_processing_enabled: bool,
    #[serde(default)]
    source_ids: Vec<String>,
}

fn default_capture_mode() -> String {
    "microphone_only".to_string()
}
fn default_asr_provider() -> String {
    "parakeet-tdt-coreml-ane".to_string()
}
fn default_none() -> String {
    "none".to_string()
}

async fn create_conversation(
    State(state): State<Arc<AppState>>,
    Json(body): Json<ConversationCreateBody>,
) -> Result<Json<ConversationSessionRecord>, ApiError> {
    let session = state.store.create_conversation(
        &body.title,
        &body.capture_mode,
        &body.asr_provider,
        &body.diarization_provider,
        body.external_processing_enabled,
        body.source_ids,
    )?;
    Ok(Json(session))
}

async fn list_conversations(
    State(state): State<Arc<AppState>>,
    Query(query): Query<LimitQuery>,
) -> Result<Json<Vec<ConversationSessionRecord>>, ApiError> {
    let limit = query.limit.unwrap_or(100).clamp(1, 1000);
    Ok(Json(state.store.list_conversations(limit)?))
}

async fn get_conversation(
    State(state): State<Arc<AppState>>,
    Path(session_id): Path<String>,
) -> Result<Json<ConversationDetail>, ApiError> {
    Ok(Json(state.store.conversation_detail(&session_id)?))
}

async fn delete_conversation(
    State(state): State<Arc<AppState>>,
    Path(session_id): Path<String>,
) -> Result<Json<serde_json::Value>, ApiError> {
    state.store.delete_conversation(&session_id)?;
    Ok(Json(json!({ "status": "deleted", "id": session_id })))
}

#[derive(Deserialize)]
struct SegmentCreateBody {
    #[serde(default = "default_speaker_id")]
    speaker_id: String,
    #[serde(default = "default_speaker_name")]
    speaker_display_name: String,
    start_ms: i64,
    end_ms: Option<i64>,
    text: String,
    #[serde(default = "default_segment_state")]
    state: String,
    confidence: Option<f64>,
}

fn default_speaker_id() -> String {
    "speaker_1".to_string()
}
fn default_speaker_name() -> String {
    "Speaker 1".to_string()
}
fn default_segment_state() -> String {
    "settled".to_string()
}

async fn add_conversation_segment(
    State(state): State<Arc<AppState>>,
    Path(session_id): Path<String>,
    Json(body): Json<SegmentCreateBody>,
) -> Result<Json<ConversationSegmentRecord>, ApiError> {
    let segment = state.store.add_conversation_segment(
        &session_id,
        &body.speaker_id,
        &body.speaker_display_name,
        body.start_ms,
        body.end_ms,
        &body.text,
        &body.state,
        body.confidence,
    )?;
    Ok(Json(segment))
}

#[derive(Deserialize)]
struct ConversationSegmentUpdateBody {
    id: String,
    text: String,
}

#[derive(Deserialize)]
struct ConversationUpdateBody {
    title: Option<String>,
    #[serde(default)]
    speaker_names: HashMap<String, String>,
    #[serde(default)]
    segments: Vec<ConversationSegmentUpdateBody>,
}

async fn update_conversation(
    State(state): State<Arc<AppState>>,
    Path(session_id): Path<String>,
    Json(body): Json<ConversationUpdateBody>,
) -> Result<Json<ConversationDetail>, ApiError> {
    let segment_texts: HashMap<String, String> =
        body.segments.into_iter().map(|s| (s.id, s.text)).collect();
    let detail = state.store.update_conversation(
        &session_id,
        body.title.as_deref(),
        &body.speaker_names,
        &segment_texts,
    )?;
    let _ = state.store.record_event(
        "conversation.updated",
        "Conversation session updated",
        "info",
        json!({ "session_id": session_id }),
    );
    Ok(Json(detail))
}

async fn stop_conversation(
    State(state): State<Arc<AppState>>,
    Path(session_id): Path<String>,
) -> Result<Json<ConversationSessionRecord>, ApiError> {
    let session = state.store.stop_conversation(&session_id)?;
    let _ = state.store.record_event(
        "conversation.stopped",
        "Conversation session stopped",
        "info",
        json!({ "session_id": session.id }),
    );
    Ok(Json(session))
}

#[derive(Deserialize)]
struct AssistCardCreateBody {
    kind: String,
    title: String,
    body: String,
    #[serde(default)]
    source_references: Vec<String>,
    confidence: Option<f64>,
}

async fn add_conversation_assist_card(
    State(state): State<Arc<AppState>>,
    Path(session_id): Path<String>,
    Json(body): Json<AssistCardCreateBody>,
) -> Result<Json<ConversationAssistCardRecord>, ApiError> {
    let card = state.store.add_assist_card(
        &session_id,
        &body.kind,
        &body.title,
        &body.body,
        body.source_references,
        body.confidence,
    )?;
    Ok(Json(card))
}

enum ApiError {
    BadRequest(String),
    NotFound(String),
    BadGateway(String),
    Internal(String),
}

impl From<StoreError> for ApiError {
    fn from(value: StoreError) -> Self {
        match value {
            StoreError::NotFound(msg) => Self::NotFound(msg),
            StoreError::Sqlite(err) => Self::Internal(err.to_string()),
        }
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let (status, detail) = match self {
            Self::BadRequest(msg) => (StatusCode::BAD_REQUEST, msg),
            Self::NotFound(msg) => (StatusCode::NOT_FOUND, msg),
            Self::BadGateway(msg) => (StatusCode::BAD_GATEWAY, msg),
            Self::Internal(msg) => (StatusCode::INTERNAL_SERVER_ERROR, msg),
        };
        (status, Json(json!({ "detail": detail }))).into_response()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::{to_bytes, Body};
    use axum::http::Method;
    use tower::ServiceExt;

    fn test_app(token: Option<&str>) -> Router {
        let state = Arc::new(AppState::new(
            RuntimeStore::in_memory().unwrap(),
            token.map(ToString::to_string),
        ));
        build_router(state)
    }

    #[tokio::test]
    async fn health_is_open_and_protected_routes_require_token() {
        let app = test_app(Some("rust-secret"));

        let health_resp = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/health")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(health_resp.status(), StatusCode::OK);

        let unauth = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/api/transcripts")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(unauth.status(), StatusCode::UNAUTHORIZED);

        let authed = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/api/transcripts")
                    .header(ENGINE_AUTH_HEADER, "rust-secret")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(authed.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn rejects_foreign_host_and_origin() {
        let app = test_app(Some("rust-secret"));

        let bad_host = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/health")
                    .header("host", "evil.example:8765")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(bad_host.status(), StatusCode::FORBIDDEN);

        let bad_origin = app
            .oneshot(
                Request::builder()
                    .uri("/api/transcripts")
                    .header(ENGINE_AUTH_HEADER, "rust-secret")
                    .header("origin", "https://evil.example")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(bad_origin.status(), StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn cleanup_and_conversations_round_trip() {
        let app = test_app(None);

        let cleanup_resp = app
            .clone()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/cleanup")
                    .header("content-type", "application/json")
                    .body(Body::from(
                        r#"{"raw_transcript":"hey so this is actually gonna work","style":"professional"}"#,
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(cleanup_resp.status(), StatusCode::OK);
        let body = to_bytes(cleanup_resp.into_body(), 1024 * 64).await.unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(json["text"], "This is actually going to work.");
        assert_eq!(json["cleanup_applied"], true);

        let transcripts_resp = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/api/transcripts")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        let tx_body = to_bytes(transcripts_resp.into_body(), 1024 * 64).await.unwrap();
        let txs: serde_json::Value = serde_json::from_slice(&tx_body).unwrap();
        assert_eq!(txs.as_array().unwrap().len(), 1);

        let create_convo = app
            .clone()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/api/conversations")
                    .header("content-type", "application/json")
                    .body(Body::from(r#"{"title":"Sync"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(create_convo.status(), StatusCode::OK);
        let convo_body = to_bytes(create_convo.into_body(), 1024 * 64).await.unwrap();
        let convo: serde_json::Value = serde_json::from_slice(&convo_body).unwrap();
        let session_id = convo["id"].as_str().unwrap();

        let add_seg = app
            .clone()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri(format!("/api/conversations/{session_id}/segments"))
                    .header("content-type", "application/json")
                    .body(Body::from(r#"{"start_ms":100,"end_ms":500,"text":"Hello"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(add_seg.status(), StatusCode::OK);

        let detail_resp = app
            .oneshot(
                Request::builder()
                    .uri(format!("/api/conversations/{session_id}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(detail_resp.status(), StatusCode::OK);
        let detail_body = to_bytes(detail_resp.into_body(), 1024 * 64).await.unwrap();
        let detail: serde_json::Value = serde_json::from_slice(&detail_body).unwrap();
        assert_eq!(detail["segments"].as_array().unwrap().len(), 1);
    }

    #[tokio::test]
    async fn cleanup_llm_gracefully_falls_back_on_error() {
        let app = test_app(None);
        let resp = app
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/cleanup")
                    .header("content-type", "application/json")
                    .body(Body::from(
                        r#"{
                            "raw_transcript":"schedule it for Monday, actually Tuesday",
                            "style":"neutral",
                            "llm":{
                                "enabled":true,
                                "provider":"custom",
                                "base_url":"http://127.0.0.1:1/v1",
                                "model":"test-model",
                                "transport":"openai_compatible",
                                "timeout_seconds":0.5
                            }
                        }"#,
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
        let body = to_bytes(resp.into_body(), 1024 * 64).await.unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(json["text"], "Schedule it for Tuesday.");
        assert_eq!(json["llm_applied"], false);
        assert!(json["llm_fallback_reason"].as_str().is_some());
    }

    #[tokio::test]
    async fn serves_dashboard_theme_providers_models_and_conversation_actions() {
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let temp_models =
            std::env::temp_dir().join(format!("omnivoice-engine-models-{nanos}"));
        let state = Arc::new(AppState::with_model_root(
            RuntimeStore::in_memory().unwrap(),
            Some("secret-token".to_string()),
            Some(temp_models.clone()),
        ));
        let app = build_router(state);

        let root_resp = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/?token=secret-token")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(root_resp.status(), StatusCode::OK);
        assert!(root_resp.headers().contains_key(axum::http::header::SET_COOKIE));

        for route in [
            "/api/theme/default",
            "/diarization/providers",
            "/translation/providers",
            "/cleanup/providers",
            "/models",
        ] {
            let resp = app
                .clone()
                .oneshot(
                    Request::builder()
                        .uri(route)
                        .header(ENGINE_AUTH_HEADER, "secret-token")
                        .body(Body::empty())
                        .unwrap(),
                )
                .await
                .unwrap();
            assert_eq!(resp.status(), StatusCode::OK, "route {route} failed");
        }

        let dl_resp = app
            .clone()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/models/parakeet-tdt-coreml-ane/download")
                    .header(ENGINE_AUTH_HEADER, "secret-token")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(dl_resp.status(), StatusCode::OK);

        let create_convo = app
            .clone()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/api/conversations")
                    .header(ENGINE_AUTH_HEADER, "secret-token")
                    .header("content-type", "application/json")
                    .body(Body::from(r#"{"title":"Rust Engine Test"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        let convo_bytes = to_bytes(create_convo.into_body(), 1024 * 64).await.unwrap();
        let convo_json: serde_json::Value = serde_json::from_slice(&convo_bytes).unwrap();
        let session_id = convo_json["id"].as_str().unwrap();

        let card_resp = app
            .clone()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri(format!("/api/conversations/{session_id}/assist-cards"))
                    .header(ENGINE_AUTH_HEADER, "secret-token")
                    .header("content-type", "application/json")
                    .body(Body::from(
                        r#"{"kind":"answer","title":"Summary","body":"All clear"}"#,
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(card_resp.status(), StatusCode::OK);

        let patch_resp = app
            .clone()
            .oneshot(
                Request::builder()
                    .method(Method::PATCH)
                    .uri(format!("/api/conversations/{session_id}"))
                    .header(ENGINE_AUTH_HEADER, "secret-token")
                    .header("content-type", "application/json")
                    .body(Body::from(r#"{"title":"Renamed Sync"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(patch_resp.status(), StatusCode::OK);
        let patch_bytes = to_bytes(patch_resp.into_body(), 1024 * 64).await.unwrap();
        let patch_json: serde_json::Value = serde_json::from_slice(&patch_bytes).unwrap();
        assert_eq!(patch_json["session"]["title"], "Renamed Sync");
        assert_eq!(patch_json["assist_cards"].as_array().unwrap().len(), 1);

        let stop_resp = app
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri(format!("/api/conversations/{session_id}/stop"))
                    .header(ENGINE_AUTH_HEADER, "secret-token")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(stop_resp.status(), StatusCode::OK);
        let stop_bytes = to_bytes(stop_resp.into_body(), 1024 * 64).await.unwrap();
        let stop_json: serde_json::Value = serde_json::from_slice(&stop_bytes).unwrap();
        assert_eq!(stop_json["ended_at"].as_str().is_some().then_some(true), Some(true));

        let _ = std::fs::remove_dir_all(&temp_models);
    }

    async fn spawn_mock_backend() -> String {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        use tokio::net::TcpListener;

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
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
                    let (status, ctype, body): (&str, &str, Vec<u8>) = if path == "/api/whoami-v2" {
                        ("200 OK", "application/json", br#"{"name":"tester"}"#.to_vec())
                    } else if path.starts_with("/api/models/") {
                        let p = serde_json::json!({
                            "sha": "hf-sha-99",
                            "siblings": [{"rfilename": "qwen3-q4_k_m.gguf"}]
                        })
                        .to_string();
                        ("200 OK", "application/json", p.into_bytes())
                    } else if path.ends_with("/resolve/main/qwen3-q4_k_m.gguf") {
                        ("200 OK", "application/octet-stream", b"MOCK_GGUF_DATA".to_vec())
                    } else if path == "/api/tags" {
                        (
                            "200 OK",
                            "application/json",
                            br#"{"models":[{"name":"qwen3:1.7b"}]}"#.to_vec(),
                        )
                    } else if path == "/v1/chat/completions" {
                        (
                            "200 OK",
                            "application/json",
                            br#"{"choices":[{"message":{"content":"Local Ollama cleaned text."}}]}"#
                                .to_vec(),
                        )
                    } else {
                        ("404 Not Found", "text/plain", b"not found".to_vec())
                    };
                    let hdr = format!(
                        "HTTP/1.1 {status}\r\nContent-Type: {ctype}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                        body.len()
                    );
                    let _ = stream.write_all(hdr.as_bytes()).await;
                    let _ = stream.write_all(&body).await;
                });
            }
        });
        format!("http://{addr}")
    }

    #[tokio::test]
    async fn downloads_gguf_validates_hf_and_runs_local_llm_cleanup() {
        let mock_url = spawn_mock_backend().await;
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let temp_models =
            std::env::temp_dir().join(format!("omnivoice-engine-option2-{nanos}"));
        let state = Arc::new(AppState::with_custom(
            RuntimeStore::in_memory().unwrap(),
            None,
            Arc::new(ModelManager::with_hf_base_url(&temp_models, &mock_url)),
            Arc::new(LocalLlmRuntime::with_config(None, &mock_url)),
        ));
        let app = build_router(state);

        // Validate Hugging Face endpoint
        let hf_resp = app
            .clone()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/huggingface/validate")
                    .header("content-type", "application/json")
                    .body(Body::from(r#"{"token":"hf_test","provider_id":"qwen3-1.7b-gguf-q4"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(hf_resp.status(), StatusCode::OK);
        let hf_json: serde_json::Value =
            serde_json::from_slice(&to_bytes(hf_resp.into_body(), 65536).await.unwrap()).unwrap();
        assert_eq!(hf_json["connected"], true);
        assert_eq!(hf_json["access_granted"], true);

        // Queue async GGUF download and poll until completed
        let dl_post = app
            .clone()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/models/qwen3-1.7b-gguf-q4/download")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(dl_post.status(), StatusCode::OK);

        let mut completed = false;
        for _ in 0..40 {
            let poll = app
                .clone()
                .oneshot(
                    Request::builder()
                        .uri("/models/qwen3-1.7b-gguf-q4/download")
                        .body(Body::empty())
                        .unwrap(),
                )
                .await
                .unwrap();
            let poll_json: serde_json::Value =
                serde_json::from_slice(&to_bytes(poll.into_body(), 65536).await.unwrap()).unwrap();
            if poll_json["state"] == "completed" {
                completed = true;
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(25)).await;
        }
        assert!(completed);

        // Check /models/:provider_id/update
        let upd_resp = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/models/qwen3-1.7b-gguf-q4/update")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(upd_resp.status(), StatusCode::OK);
        let upd_json: serde_json::Value =
            serde_json::from_slice(&to_bytes(upd_resp.into_body(), 65536).await.unwrap()).unwrap();
        assert_eq!(upd_json["remote_revision"], "hf-sha-99");
        assert_eq!(upd_json["update_available"], false);

        // Check local_mlx cleanup transport routes to LocalLlmRuntime
        let cleanup_resp = app
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/cleanup")
                    .header("content-type", "application/json")
                    .body(Body::from(
                        r#"{
                            "raw_transcript":"hello local llm cleanup world",
                            "style":"neutral",
                            "llm":{
                                "enabled":true,
                                "provider":"local_mlx",
                                "model":"qwen3-1.7b-mlx-4bit",
                                "transport":"local_mlx",
                                "timeout_seconds":2.0
                            }
                        }"#,
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(cleanup_resp.status(), StatusCode::OK);
        let cleanup_json: serde_json::Value =
            serde_json::from_slice(&to_bytes(cleanup_resp.into_body(), 65536).await.unwrap())
                .unwrap();
        assert_eq!(cleanup_json["text"], "Local Ollama cleaned text.");
        assert_eq!(cleanup_json["llm_applied"], true);

        let _ = std::fs::remove_dir_all(&temp_models);
    }

    #[tokio::test]
    async fn layered_voice_settings_profiles_isolate_apps_and_support_shared_default() {
        let app = test_app(Some("engine-secret"));

        // 1. Update shared default profile
        let patch_default = app
            .clone()
            .oneshot(
                Request::builder()
                    .method(Method::PATCH)
                    .uri("/api/settings?profile=default")
                    .header(ENGINE_AUTH_HEADER, "engine-secret")
                    .header("content-type", "application/json")
                    .body(Body::from(
                        r#"{"style":"professional","service_mode":{"enabled":false,"deepgram_model":"nova-3"}}"#,
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(patch_default.status(), StatusCode::OK);

        // 2. Inferno initially inherits shared default
        let get_inferno = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/api/settings?profile=inferno")
                    .header(ENGINE_AUTH_HEADER, "engine-secret")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        let inferno_body: serde_json::Value =
            serde_json::from_slice(&to_bytes(get_inferno.into_body(), 65536).await.unwrap())
                .unwrap();
        assert_eq!(inferno_body["mode"], "shared");
        assert_eq!(inferno_body["effective"]["style"], "professional");

        // 3. Give Inferno its own custom override (OmniSpeak/default stay untouched!)
        let patch_inferno = app
            .clone()
            .oneshot(
                Request::builder()
                    .method(Method::PATCH)
                    .uri("/api/settings?profile=inferno")
                    .header(ENGINE_AUTH_HEADER, "engine-secret")
                    .header("content-type", "application/json")
                    .body(Body::from(
                        r#"{"style":"concise","service_mode":{"enabled":true,"deepgram_model":"flux-general-en"}}"#,
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        let inferno_custom: serde_json::Value =
            serde_json::from_slice(&to_bytes(patch_inferno.into_body(), 65536).await.unwrap())
                .unwrap();
        assert_eq!(inferno_custom["mode"], "custom");
        assert_eq!(inferno_custom["effective"]["style"], "concise");
        assert_eq!(inferno_custom["effective"]["service_mode"]["enabled"], true);
        assert_eq!(inferno_custom["defaults"]["style"], "professional");

        // 4. Another app (omnispeak) still sees default untouched
        let get_omni = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/api/settings?profile=omnispeak")
                    .header(ENGINE_AUTH_HEADER, "engine-secret")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        let omni_body: serde_json::Value =
            serde_json::from_slice(&to_bytes(get_omni.into_body(), 65536).await.unwrap()).unwrap();
        assert_eq!(omni_body["mode"], "shared");
        assert_eq!(omni_body["effective"]["style"], "professional");
        assert_eq!(omni_body["effective"]["service_mode"]["enabled"], false);

        // 5. Delete Inferno override -> reverts cleanly to shared default
        let del_inferno = app
            .oneshot(
                Request::builder()
                    .method(Method::DELETE)
                    .uri("/api/settings?profile=inferno")
                    .header(ENGINE_AUTH_HEADER, "engine-secret")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        let reverted: serde_json::Value =
            serde_json::from_slice(&to_bytes(del_inferno.into_body(), 65536).await.unwrap())
                .unwrap();
        assert_eq!(reverted["mode"], "shared");
        assert_eq!(reverted["effective"]["style"], "professional");
    }
}
