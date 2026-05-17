from typing import Annotated, Any, Literal

from pydantic import BaseModel, Field, StringConstraints, model_validator


NonBlankString = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1)]
ConversationCaptureMode = Literal[
    "microphone_only",
    "system_audio_only",
    "microphone_and_system_audio",
    "mixed_fallback",
]
ConversationSegmentState = Literal["live", "settled", "corrected_speaker"]
ConversationAssistCardKind = Literal["question", "answer", "time_zone", "follow_up", "action_item", "warning"]
ConversationAssistCardStatus = Literal["active", "copied", "spoken", "pinned", "dismissed"]
Confidence = Annotated[float, Field(ge=0.0, le=1.0)]
Milliseconds = Annotated[int, Field(ge=0)]


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


class ConversationSessionCreateRequest(BaseModel):
    title: NonBlankString = "Conversation"
    capture_mode: ConversationCaptureMode = "microphone_only"
    asr_provider: NonBlankString = "parakeet-tdt"
    diarization_provider: NonBlankString = "mock"
    external_processing_enabled: bool = False


class ConversationSessionRecord(BaseModel):
    id: str
    title: NonBlankString
    started_at: str
    ended_at: str | None = None
    capture_mode: ConversationCaptureMode
    asr_provider: NonBlankString
    diarization_provider: NonBlankString
    external_processing_enabled: bool = False


class ConversationSegmentCreateRequest(BaseModel):
    speaker_id: NonBlankString
    speaker_display_name: NonBlankString
    start_ms: Milliseconds
    end_ms: Milliseconds | None = None
    text: NonBlankString
    state: ConversationSegmentState = "settled"
    confidence: Confidence | None = None

    @model_validator(mode="after")
    def validate_end_ms(self) -> "ConversationSegmentCreateRequest":
        if self.end_ms is not None and self.end_ms < self.start_ms:
            raise ValueError("end_ms must be greater than or equal to start_ms")
        return self


class ConversationSegmentRecord(BaseModel):
    id: str
    session_id: str
    speaker_id: NonBlankString
    speaker_display_name: NonBlankString
    start_ms: Milliseconds
    end_ms: Milliseconds | None = None
    text: NonBlankString
    state: ConversationSegmentState = "settled"
    confidence: Confidence | None = None

    @model_validator(mode="after")
    def validate_end_ms(self) -> "ConversationSegmentRecord":
        if self.end_ms is not None and self.end_ms < self.start_ms:
            raise ValueError("end_ms must be greater than or equal to start_ms")
        return self


class ConversationAssistCardCreateRequest(BaseModel):
    kind: ConversationAssistCardKind
    title: NonBlankString
    body: NonBlankString
    source_references: list[str] = Field(default_factory=list)
    confidence: Confidence | None = None


class ConversationAssistCardRecord(BaseModel):
    id: str
    session_id: str
    kind: ConversationAssistCardKind
    title: NonBlankString
    body: NonBlankString
    source_references: list[str] = Field(default_factory=list)
    confidence: Confidence | None = None
    status: ConversationAssistCardStatus = "active"
    created_at: str


class ConversationDetail(BaseModel):
    session: ConversationSessionRecord
    segments: list[ConversationSegmentRecord] = Field(default_factory=list)
    assist_cards: list[ConversationAssistCardRecord] = Field(default_factory=list)


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
