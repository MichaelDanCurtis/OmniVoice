from pydantic import BaseModel, Field
from typing import Any


class CleanupRequest(BaseModel):
    raw_transcript: str = Field(min_length=0)
    style: str = "neutral"
    dictionary_terms: list[str] = Field(default_factory=list)


class CleanupResponse(BaseModel):
    text: str
    cleanup_applied: bool


class AIHandoffRequest(BaseModel):
    prompt: str = Field(min_length=1)
    provider: str = "custom"
    base_url: str = ""
    model: str = ""
    api_key: str = ""
    context: str = ""


class AIHandoffResponse(BaseModel):
    text: str
    provider: str
    model: str


class TranslationRequest(BaseModel):
    text: str = Field(min_length=1)
    source_language: str = "auto"
    target_language: str = "en"
    provider: str = "custom"
    base_url: str = ""
    model: str = ""
    api_key: str = ""


class TranslationResponse(BaseModel):
    text: str
    provider: str
    model: str
    source_language: str
    target_language: str


class ProviderInfo(BaseModel):
    id: str
    label: str
    available: bool
    reason: str | None = None


class TranscribeResponse(BaseModel):
    text: str
    provider: str


class ModelStatus(BaseModel):
    provider_id: str
    label: str
    repo_id: str
    local_path: str
    installed: bool
    installed_revision: str | None = None
    remote_revision: str | None = None
    update_available: bool | None = None
    missing_files: list[str] = Field(default_factory=list)
    download_state: str = "idle"
    download_message: str | None = None


class ModelUpdateInfo(BaseModel):
    provider_id: str
    repo_id: str
    installed_revision: str | None = None
    remote_revision: str
    update_available: bool


class ModelDownloadStatus(BaseModel):
    provider_id: str
    state: str
    message: str | None = None
    local_path: str
    revision: str | None = None


class DesktopAppLaunchResponse(BaseModel):
    status: str
    message: str
    app_path: str


class ThemePayload(BaseModel):
    id: str
    name: str
    css_variables: dict[str, str]


class EngineEvent(BaseModel):
    id: str
    timestamp: str
    level: str
    kind: str
    message: str
    detail: dict[str, Any] = Field(default_factory=dict)


class TranscriptRecord(BaseModel):
    id: str
    created_at: str
    source: str
    raw_text: str
    cleaned_text: str | None = None
    provider: str | None = None
    style: str | None = None
    audio_bytes: int | None = None
    sample_rate: int | None = None
    duration_ms: int | None = None


class StreamingStats(BaseModel):
    active_streams: int = 0
    opened_streams: int = 0
    completed_streams: int = 0
    failed_streams: int = 0
    closed_streams: int = 0
    total_chunks: int = 0
    total_audio_bytes: int = 0
    total_partials: int = 0
    last_provider: str | None = None
    last_sample_rate: int | None = None
    last_partial_text: str = ""
    last_error: str | None = None


class EngineStatus(BaseModel):
    status: str
    started_at: str
    uptime_seconds: int
    providers: list[ProviderInfo]
    models: list[ModelStatus]
    event_count: int
    transcript_count: int
    streaming: StreamingStats = Field(default_factory=StreamingStats)
