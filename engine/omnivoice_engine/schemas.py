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
AIHandoffTransport = Literal["openai_compatible", "anthropic", "openai_codex_oauth", "github_copilot_oauth"]
AIChatMessageRole = Literal["system", "user", "assistant"]
AIChatAttachmentKind = Literal["file", "image", "audio", "subject", "conversation", "document", "transcript"]
TranslationProviderID = Literal["fake", "translategemma-mlx", "nllb-200-distilled-600m"]
TranslationValidationStatus = Literal["pass", "review", "fail"]
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
    transport: AIHandoffTransport = "openai_compatible"
    oauth_access_token: str = ""
    headers: dict[str, str] = Field(default_factory=dict)
    context: str = ""


class AIHandoffResponse(BaseModel):
    text: str
    provider: str
    model: str


class AIChatMessage(BaseModel):
    role: AIChatMessageRole
    content: str = Field(min_length=0)


class AIChatAttachment(BaseModel):
    kind: AIChatAttachmentKind = "file"
    title: str = Field(min_length=1)
    text: str = ""
    mime_type: str = ""
    data_url: str = ""


class AIChatRequest(BaseModel):
    provider: str = "custom"
    base_url: str = ""
    model: str = ""
    api_key: str = ""
    transport: AIHandoffTransport = "openai_compatible"
    oauth_access_token: str = ""
    headers: dict[str, str] = Field(default_factory=dict)
    messages: list[AIChatMessage] = Field(default_factory=list)
    attachments: list[AIChatAttachment] = Field(default_factory=list)
    web_search_enabled: bool = False
    web_search_query: str = ""


class AIChatResponse(BaseModel):
    text: str
    provider: str
    model: str


class AIModelListRequest(BaseModel):
    provider: str = "custom"
    base_url: str = ""
    api_key: str = ""
    transport: AIHandoffTransport = "openai_compatible"
    oauth_access_token: str = ""
    headers: dict[str, str] = Field(default_factory=dict)


class AIModelListResponse(BaseModel):
    provider: str
    models: list[str]


class TranslationRequest(BaseModel):
    text: str = Field(min_length=0)
    provider: TranslationProviderID = "fake"
    source_language: str = "auto"
    target_language: NonBlankString = "en"
    context: list[str] = Field(default_factory=list)
    model_path: str = ""
    is_final: bool = True

    @model_validator(mode="after")
    def normalize_languages(self) -> "TranslationRequest":
        self.source_language = (self.source_language or "auto").strip().lower() or "auto"
        self.target_language = self.target_language.strip().lower()
        self.model_path = self.model_path.strip()
        self.context = [item.strip() for item in self.context if item.strip()]
        return self


class TranslationResponse(BaseModel):
    text: str
    provider: TranslationProviderID
    source_language: str
    detected_language: str
    target_language: str
    confidence: Confidence
    is_final: bool


class TranslationValidationRequest(BaseModel):
    text: str = "Hello, thank you for coming."
    provider: TranslationProviderID = "translategemma-mlx"
    source_language: str = "en"
    model_path: str = ""
    target_languages: list[str] = Field(default_factory=list)
    max_languages: int | None = Field(default=None, ge=1, le=500)

    @model_validator(mode="after")
    def normalize_values(self) -> "TranslationValidationRequest":
        self.text = self.text.strip() or "Hello, thank you for coming."
        self.source_language = (self.source_language or "en").strip().lower() or "en"
        self.model_path = self.model_path.strip()
        self.target_languages = [language.strip().lower() for language in self.target_languages if language.strip()]
        return self


class TranslationValidationItem(BaseModel):
    code: str
    name: str
    text: str
    status: TranslationValidationStatus
    expected_scripts: list[str] = Field(default_factory=list)
    dominant_script: str | None = None
    scripts: dict[str, int] = Field(default_factory=dict)
    letter_count: int = 0
    expected_script_characters: int = 0
    expected_script_ratio: float = 0.0
    replacement_characters: int = 0
    output_preview: str = ""
    failure_category: str | None = None
    notes: list[str] = Field(default_factory=list)


class TranslationValidationResponse(BaseModel):
    provider: TranslationProviderID
    source_language: str
    text: str
    capability_source: str
    tested: int
    passed: int
    review: int
    failed: int
    items: list[TranslationValidationItem] = Field(default_factory=list)


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
    category: str = "asr"
    recommendation: str | None = None
    detail: str | None = None
    size: str | None = None
    precision: str | None = None
    requires_hf_auth: bool = False
    agreement_url: str | None = None
    license: str | None = None
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


class HuggingFaceTokenValidationRequest(BaseModel):
    token: str = ""
    provider_id: str = ""

    @model_validator(mode="after")
    def normalize_values(self) -> "HuggingFaceTokenValidationRequest":
        self.token = self.token.strip()
        self.provider_id = self.provider_id.strip()
        return self


class HuggingFaceAuthStatus(BaseModel):
    connected: bool
    source: str
    username: str | None = None
    provider_id: str | None = None
    repo_id: str | None = None
    access_granted: bool | None = None
    message: str


class TranslationLanguageOption(BaseModel):
    code: str
    name: str
    is_default: bool = False


class TranslationCapabilities(BaseModel):
    provider_id: str
    model_provider_id: str | None = None
    source_language_locked: bool
    source_language_reason: str | None = None
    source_languages: list[TranslationLanguageOption] = Field(default_factory=list)
    target_languages: list[TranslationLanguageOption] = Field(default_factory=list)
    capability_source: str
    message: str | None = None


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
    diarization_provider: NonBlankString = "none"
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
    speaker_id: NonBlankString | None = None
    speaker_display_name: NonBlankString | None = None
    audio_start_ms: Milliseconds | None = None
    start_ms: Milliseconds
    end_ms: Milliseconds | None = None
    text: NonBlankString
    state: ConversationSegmentState = "settled"
    confidence: Confidence | None = None
    audio_pcm_float32_base64: str | None = None
    audio_sample_rate: int | None = Field(default=None, gt=0)

    @model_validator(mode="after")
    def validate_end_ms(self) -> "ConversationSegmentCreateRequest":
        if self.end_ms is not None and self.end_ms < self.start_ms:
            raise ValueError("end_ms must be greater than or equal to start_ms")
        if (self.speaker_id is None) != (self.speaker_display_name is None):
            raise ValueError("speaker_id and speaker_display_name must be provided together")
        if (self.audio_pcm_float32_base64 is None) != (self.audio_sample_rate is None):
            raise ValueError("audio_pcm_float32_base64 and audio_sample_rate must be provided together")
        if self.audio_start_ms is not None and self.audio_pcm_float32_base64 is None:
            raise ValueError("audio_start_ms requires audio_pcm_float32_base64")
        if self.audio_start_ms is not None and self.audio_start_ms > self.start_ms:
            raise ValueError("audio_start_ms must be less than or equal to start_ms")
        return self


class SpeakerTurnRecord(BaseModel):
    id: str
    session_id: str
    speaker_id: NonBlankString
    start_ms: Milliseconds
    end_ms: Milliseconds | None = None
    confidence: Confidence | None = None
    overlap: bool = False
    source_provider: NonBlankString

    @model_validator(mode="after")
    def validate_end_ms(self) -> "SpeakerTurnRecord":
        if self.end_ms is not None and self.end_ms < self.start_ms:
            raise ValueError("end_ms must be greater than or equal to start_ms")
        return self


class ConversationSpeakerLineRecord(BaseModel):
    id: str
    session_id: str
    speaker_id: NonBlankString
    start_ms: Milliseconds
    end_ms: Milliseconds | None = None
    text: NonBlankString
    confidence: Confidence | None = None
    source_provider: NonBlankString

    @model_validator(mode="after")
    def validate_end_ms(self) -> "ConversationSpeakerLineRecord":
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
    speaker_turns: list[SpeakerTurnRecord] = Field(default_factory=list)
    speaker_lines: list[ConversationSpeakerLineRecord] = Field(default_factory=list)

    @model_validator(mode="after")
    def validate_end_ms(self) -> "ConversationSegmentRecord":
        if self.end_ms is not None and self.end_ms < self.start_ms:
            raise ValueError("end_ms must be greater than or equal to start_ms")
        return self


class ConversationSegmentUpdateRequest(BaseModel):
    id: NonBlankString
    text: NonBlankString


class ConversationDetailUpdateRequest(BaseModel):
    title: NonBlankString | None = None
    speaker_names: dict[NonBlankString, NonBlankString] = Field(default_factory=dict)
    segments: list[ConversationSegmentUpdateRequest] = Field(default_factory=list)


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


class ConversationImportResult(BaseModel):
    status: Literal["created", "updated"]
    session_id: str
    segments: int
    assist_cards: int


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
