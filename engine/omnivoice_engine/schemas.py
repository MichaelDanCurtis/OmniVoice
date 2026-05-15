from pydantic import BaseModel, Field


class CleanupRequest(BaseModel):
    raw_transcript: str = Field(min_length=0)
    style: str = "neutral"
    dictionary_terms: list[str] = Field(default_factory=list)


class CleanupResponse(BaseModel):
    text: str
    cleanup_applied: bool


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
