import asyncio
import base64
import binascii
import hashlib
import json
import os
import subprocess
import time
import urllib.error
import urllib.request
import uuid
from dataclasses import dataclass
from http.client import HTTPMessage
from html.parser import HTMLParser
from pathlib import Path
from typing import Iterable
from urllib.parse import parse_qs, urlencode, urlparse

from fastapi import BackgroundTasks, FastAPI, Header, HTTPException, Query, Request, Response, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles

from .cleanup import clean_transcript
from .conversation_alignment import build_speaker_lines
from .diarization import DiarizationAudio, DiarizationRegistry
from .model_manager import ModelManager
from .providers.registry import ProviderRegistry
from .runtime_store import RuntimeStore
from .schemas import (
    AIChatRequest,
    AIChatResponse,
    AIHandoffRequest,
    AIHandoffResponse,
    AIModelListRequest,
    AIModelListResponse,
    CleanupRequest,
    CleanupResponse,
    ConversationAssistCardCreateRequest,
    ConversationAssistCardRecord,
    ConversationDetail,
    ConversationDetailUpdateRequest,
    ConversationImportResult,
    ConversationSegmentCreateRequest,
    ConversationSegmentRecord,
    ConversationSpeakerLineRecord,
    ConversationSessionCreateRequest,
    ConversationSessionRecord,
    DesktopAppLaunchResponse,
    EngineEvent,
    EngineStatus,
    HuggingFaceAuthStatus,
    HuggingFaceTokenValidationRequest,
    ModelDownloadStatus,
    ModelStatus,
    ModelUpdateInfo,
    ProviderInfo,
    SpeakerTurnRecord,
    ThemePayload,
    TranscriptRecord,
    TranscribeResponse,
    TranslationCapabilities,
    TranslationRequest,
    TranslationResponse,
    TranslationValidationRequest,
    TranslationValidationResponse,
)
from .translation import TranslationRegistry, validate_translation_targets

app = FastAPI(title="OmniSpeak Local Engine")
registry = ProviderRegistry()
diarization_registry = DiarizationRegistry()
translation_registry = TranslationRegistry()
model_manager = ModelManager()
runtime_store = RuntimeStore()
STARTED_MONOTONIC = time.monotonic()
STATIC_DIR = Path(__file__).parent / "static"
REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DESKTOP_APP_PATH = REPO_ROOT / "dist" / "OmniSpeak.app"
DEFAULT_THEME_CSS_VARIABLES = {
    "--ov-accent": "#38BDF8",
    "--ov-accent-text": "#38BDF8",
    "--ov-accent-secondary": "#818CF8",
    "--ov-accent-secondary-text": "#818CF8",
    "--ov-bg": "#06121C",
    "--ov-surface": "rgba(6, 18, 28, 0.36)",
    "--ov-surface-strong": "rgba(6, 18, 28, 0.54)",
    "--ov-text": "#F8FAFC",
    "--ov-muted": "rgba(248, 250, 252, 0.64)",
    "--ov-on-accent": "#06121C",
    "--ov-border": "rgba(56, 189, 248, 0.26)",
    "--ov-glow": "rgba(56, 189, 248, 0.34)",
    "--ov-caption-bg": "rgba(6, 18, 28, 0.14)",
}


@dataclass(frozen=True)
class WebSearchResult:
    title: str
    url: str
    snippet: str = ""


AI_CHAT_SYSTEM_PROMPT = (
    "You are OmniSpeak Ask AI, a full chat assistant inside a local dictation app. "
    "Answer naturally and directly. Use attached files, transcripts, conversations, "
    "and images when they are provided. If the user asks for editing or drafting, "
    "produce useful finished text and explain briefly only when that helps."
)
OPENAI_CODEX_RECOMMENDED_MODELS = [
    "gpt-5.5",
    "gpt-5.4",
    "gpt-5.4-mini",
    "gpt-5.3-codex",
    "gpt-5.3-codex-spark",
    "gpt-5.2",
]
_github_copilot_token_cache: dict[str, tuple[str, float]] = {}
app.mount("/assets", StaticFiles(directory=STATIC_DIR), name="assets")


@app.middleware("http")
async def record_http_event(request: Request, call_next):
    started = time.monotonic()
    status_code = 500
    try:
        response = await call_next(request)
        status_code = response.status_code
        return response
    except Exception as exc:
        duration_ms = int((time.monotonic() - started) * 1000)
        if _should_record_request(request.url.path):
            runtime_store.record_event(
                "http.error",
                f"{request.method} {request.url.path} failed",
                level="error",
                detail={"duration_ms": duration_ms, "error": str(exc)},
            )
        raise
    finally:
        duration_ms = int((time.monotonic() - started) * 1000)
        if _should_record_request(request.url.path):
            runtime_store.record_event(
                "http.request",
                f"{request.method} {request.url.path} -> {status_code}",
                level="error" if status_code >= 500 else "warning" if status_code >= 400 else "info",
                detail={
                    "method": request.method,
                    "path": request.url.path,
                    "status_code": status_code,
                    "duration_ms": duration_ms,
                },
            )


@app.get("/", response_class=HTMLResponse)
def dashboard() -> HTMLResponse:
    return HTMLResponse((STATIC_DIR / "index.html").read_text(encoding="utf-8"))


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/theme/default", response_model=ThemePayload)
def default_theme() -> ThemePayload:
    return ThemePayload(id="auroraBlue", name="Aurora Blue", css_variables=dict(DEFAULT_THEME_CSS_VARIABLES))


@app.get("/providers", response_model=list[ProviderInfo])
def providers() -> list[ProviderInfo]:
    return registry.list_providers()


@app.get("/diarization/providers", response_model=list[ProviderInfo])
def diarization_providers() -> list[ProviderInfo]:
    return diarization_registry.list_providers()


@app.get("/translation/providers", response_model=list[ProviderInfo])
def translation_providers() -> list[ProviderInfo]:
    return translation_registry.list_providers()


@app.get("/translation/capabilities", response_model=TranslationCapabilities)
def translation_capabilities(
    provider_id: str = Query("translategemma-mlx"),
    model_provider_id: str = Query(""),
    model_path: str = Query(""),
    asr_provider: str = Query("parakeet-tdt-mlx"),
) -> TranslationCapabilities:
    try:
        return translation_registry.capabilities(
            provider_id,
            model_path=model_path,
            model_provider_id=model_provider_id or None,
            asr_provider_id=asr_provider,
        )
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"unknown translation provider: {provider_id}") from exc


@app.get("/models", response_model=list[ModelStatus])
def models() -> list[ModelStatus]:
    return model_manager.list_statuses()


@app.get("/models/{provider_id}/update", response_model=ModelUpdateInfo)
def model_update(provider_id: str, authorization: str | None = Header(default=None)) -> ModelUpdateInfo:
    try:
        return model_manager.check_update(provider_id, token=bearer_token(authorization))
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"unknown model provider: {provider_id}") from exc
    except Exception as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@app.post("/models/{provider_id}/download", response_model=ModelDownloadStatus)
def model_download(
    provider_id: str,
    background_tasks: BackgroundTasks,
    authorization: str | None = Header(default=None),
) -> ModelDownloadStatus:
    try:
        state = model_manager.start_download(provider_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"unknown model provider: {provider_id}") from exc

    runtime_store.record_event(
        "model.download.queued",
        f"Queued model download for {provider_id}",
        detail={"provider_id": provider_id, "state": state.state},
    )
    background_tasks.add_task(_download_model, provider_id, bearer_token(authorization))
    return state


@app.get("/models/{provider_id}/download", response_model=ModelDownloadStatus)
def model_download_status(provider_id: str) -> ModelDownloadStatus:
    try:
        return model_manager.download_state(provider_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"unknown model provider: {provider_id}") from exc


@app.delete("/models/{provider_id}", response_model=ModelStatus)
def model_delete(provider_id: str) -> ModelStatus:
    try:
        status = model_manager.delete(provider_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"unknown model provider: {provider_id}") from exc
    except RuntimeError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc

    runtime_store.record_event(
        "model.deleted",
        f"Deleted model files for {provider_id}",
        detail={"provider_id": provider_id, "local_path": status.local_path},
    )
    return status


@app.post("/huggingface/validate", response_model=HuggingFaceAuthStatus)
def huggingface_validate(request: HuggingFaceTokenValidationRequest) -> HuggingFaceAuthStatus:
    try:
        return model_manager.validate_huggingface_access(request.provider_id, token=request.token)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"unknown model provider: {request.provider_id}") from exc


@app.post("/api/desktop-app/start", response_model=DesktopAppLaunchResponse)
def start_desktop_app() -> DesktopAppLaunchResponse:
    app_path = desktop_app_path()
    if not app_path.exists():
        runtime_store.record_event(
            "desktop_app.start_failed",
            "Desktop app bundle was not found",
            level="error",
            detail={"app_path": str(app_path)},
        )
        raise HTTPException(status_code=404, detail=f"desktop app bundle not found: {app_path}")

    try:
        launch_desktop_app(app_path)
    except Exception as exc:
        runtime_store.record_event(
            "desktop_app.start_failed",
            "Desktop app launch failed",
            level="error",
            detail={"app_path": str(app_path), "error": str(exc)},
        )
        raise HTTPException(status_code=502, detail=f"desktop app launch failed: {exc}") from exc

    runtime_store.record_event(
        "desktop_app.start",
        "Desktop app launch requested",
        detail={"app_path": str(app_path)},
    )
    return DesktopAppLaunchResponse(
        status="started",
        message="Desktop app launch requested",
        app_path=str(app_path),
    )


@app.post("/cleanup", response_model=CleanupResponse)
def cleanup(request: CleanupRequest) -> CleanupResponse:
    result = clean_transcript(request)
    runtime_store.record_transcript(
        source="cleanup",
        raw_text=request.raw_transcript,
        cleaned_text=result.text,
        style=request.style,
    )
    runtime_store.record_event(
        "cleanup.completed",
        "Transcript cleanup completed",
        detail={
            "style": request.style,
            "cleanup_applied": result.cleanup_applied,
            "raw_length": len(request.raw_transcript),
            "cleaned_length": len(result.text),
        },
    )
    return result


@app.post("/api/ai/handoff", response_model=AIHandoffResponse)
def ai_handoff(request: AIHandoffRequest) -> AIHandoffResponse:
    base_url = request.base_url.strip()
    model = request.model.strip()
    prompt = request.prompt.strip()
    context = request.context.strip()
    provider = request.provider.strip() or "custom"
    if not model:
        raise HTTPException(status_code=400, detail="AI endpoint and model are required")
    if request.transport in {"openai_compatible", "anthropic"} and not base_url:
        raise HTTPException(status_code=400, detail="AI endpoint and model are required")
    if request.transport in {"openai_codex_oauth", "github_copilot_oauth"} and not request.oauth_access_token.strip():
        raise HTTPException(status_code=400, detail="OAuth access token is required")

    messages = [
        {
            "role": "system",
            "content": (
                "You write concise, directly usable text to insert at the user's cursor. "
                "Return only the text to insert."
            ),
        },
        {
            "role": "user",
            "content": _ai_handoff_user_content(prompt=prompt, context=context),
        },
    ]

    try:
        chat_completion = ai_handoff_completion_handler(request.transport)
        text = chat_completion(
            base_url=base_url,
            api_key=request.api_key.strip(),
            oauth_access_token=request.oauth_access_token.strip(),
            headers=normalized_headers(request.headers),
            model=model,
            messages=messages,
            timeout=45.0,
        )
    except Exception as exc:
        runtime_store.record_event(
            "ai_handoff.failed",
            "AI handoff failed",
            level="error",
            detail={"provider": provider, "model": model, "error": str(exc)},
        )
        raise HTTPException(status_code=502, detail=f"AI handoff failed: {exc}") from exc

    runtime_store.record_event(
        "ai_handoff.completed",
        "AI handoff completed",
        detail={
            "provider": provider,
            "model": model,
            "transport": request.transport,
            "prompt_length": len(prompt),
            "context_length": len(context),
        },
    )
    return AIHandoffResponse(text=text, provider=provider, model=model)


@app.post("/api/ai/chat", response_model=AIChatResponse)
def ai_chat(request: AIChatRequest) -> AIChatResponse:
    base_url = request.base_url.strip()
    model = request.model.strip()
    provider = request.provider.strip() or "custom"
    if not model:
        raise HTTPException(status_code=400, detail="AI endpoint and model are required")
    if request.transport in {"openai_compatible", "anthropic"} and not base_url:
        raise HTTPException(status_code=400, detail="AI endpoint and model are required")
    if request.transport in {"openai_codex_oauth", "github_copilot_oauth"} and not request.oauth_access_token.strip():
        raise HTTPException(status_code=400, detail="OAuth access token is required")

    web_search_context = ""
    if request.web_search_enabled:
        query = ai_chat_web_search_query(request)
        if query:
            try:
                results = web_search_handler(query)
            except Exception as exc:
                runtime_store.record_event(
                    "ai_chat.web_search.failed",
                    "Ask AI web search failed",
                    level="warning",
                    detail={"provider": provider, "query": query, "error": str(exc)},
                )
                web_search_context = f"Web search was requested for: {query}\nSearch failed: {exc}"
            else:
                web_search_context = ai_chat_web_search_context(query, results)
                runtime_store.record_event(
                    "ai_chat.web_search.completed",
                    "Ask AI web search completed",
                    detail={"provider": provider, "query": query, "result_count": len(results)},
                )

    messages = build_ai_chat_messages(request, web_search_context=web_search_context)
    try:
        chat_completion = ai_handoff_completion_handler(request.transport)
        text = chat_completion(
            base_url=base_url,
            api_key=request.api_key.strip(),
            oauth_access_token=request.oauth_access_token.strip(),
            headers=normalized_headers(request.headers),
            model=model,
            messages=messages,
            timeout=90.0,
        )
    except Exception as exc:
        runtime_store.record_event(
            "ai_chat.failed",
            "AI chat failed",
            level="error",
            detail={"provider": provider, "model": model, "error": str(exc)},
        )
        raise HTTPException(status_code=502, detail=f"AI chat failed: {exc}") from exc

    runtime_store.record_event(
        "ai_chat.completed",
        "AI chat completed",
        detail={
            "provider": provider,
            "model": model,
            "transport": request.transport,
            "message_count": len(request.messages),
            "attachment_count": len(request.attachments),
            "web_search_enabled": request.web_search_enabled,
        },
    )
    return AIChatResponse(text=text, provider=provider, model=model)


def ai_handoff_completion_handler(transport: str):
    if transport == "anthropic":
        return anthropic_chat_completion
    if transport == "openai_codex_oauth":
        return openai_codex_oauth_completion
    if transport == "github_copilot_oauth":
        return github_copilot_oauth_completion
    return openai_compatible_chat_completion


@app.post("/api/ai/models", response_model=AIModelListResponse)
def ai_models(request: AIModelListRequest) -> AIModelListResponse:
    base_url = request.base_url.strip()
    provider = request.provider.strip() or "custom"
    if request.transport in {"openai_compatible", "anthropic"} and not base_url:
        raise HTTPException(status_code=400, detail="AI endpoint is required")
    if request.transport in {"openai_codex_oauth", "github_copilot_oauth"} and not request.oauth_access_token.strip():
        raise HTTPException(status_code=400, detail="OAuth access token is required")

    try:
        model_lister = ai_model_list_handler(request.transport)
        models = model_lister(
            base_url=base_url,
            api_key=request.api_key.strip(),
            oauth_access_token=request.oauth_access_token.strip(),
            headers=normalized_headers(request.headers),
            timeout=20.0,
        )
    except Exception as exc:
        runtime_store.record_event(
            "ai_models.failed",
            "AI model refresh failed",
            level="error",
            detail={"provider": provider, "transport": request.transport, "error": str(exc)},
        )
        raise HTTPException(status_code=502, detail=f"AI model refresh failed: {exc}") from exc

    runtime_store.record_event(
        "ai_models.completed",
        "AI model refresh completed",
        detail={"provider": provider, "transport": request.transport, "model_count": len(models)},
    )
    return AIModelListResponse(provider=provider, models=models)


def ai_model_list_handler(transport: str):
    if transport == "anthropic":
        return anthropic_model_list
    if transport == "openai_codex_oauth":
        return openai_codex_model_list
    if transport == "github_copilot_oauth":
        return github_copilot_model_list
    return openai_compatible_model_list


@app.post("/translate", response_model=TranslationResponse)
def translate(request: TranslationRequest) -> TranslationResponse:
    started = time.monotonic()
    try:
        translator = translation_registry.get(request.provider)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"unknown translation provider: {request.provider}") from exc

    info = translator.info(request.model_path)
    if not info.available:
        detail = info.reason or f"provider unavailable: {request.provider}"
        raise HTTPException(status_code=503, detail=f"provider unavailable: {detail}")

    try:
        result = translator.translate(request)
    except Exception as exc:
        runtime_store.record_event(
            "translation.failed",
            f"Translation failed for {request.provider}",
            level="error",
            detail={
                "provider": request.provider,
                "source_language": request.source_language,
                "target_language": request.target_language,
                "text_length": len(request.text),
                "error": str(exc),
            },
        )
        raise HTTPException(status_code=502, detail=f"translation failed: {exc}") from exc

    duration_ms = int((time.monotonic() - started) * 1000)
    runtime_store.record_event(
        "translation.completed",
        f"Translated text with {request.provider}",
        detail={
            "provider": result.provider,
            "source_language": result.source_language,
            "detected_language": result.detected_language,
            "target_language": result.target_language,
            "duration_ms": duration_ms,
            "text_length": len(request.text),
            "translated_length": len(result.text),
            "is_final": result.is_final,
        },
    )
    return result


@app.post("/translation/validate", response_model=TranslationValidationResponse)
def validate_translation_languages(request: TranslationValidationRequest) -> TranslationValidationResponse:
    try:
        translator = translation_registry.get(request.provider)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"unknown translation provider: {request.provider}") from exc

    info = translator.info(request.model_path)
    if not info.available:
        detail = info.reason or f"provider unavailable: {request.provider}"
        raise HTTPException(status_code=503, detail=f"provider unavailable: {detail}")

    capabilities = translation_registry.capabilities(
        request.provider,
        model_path=request.model_path,
    )
    selected_targets = capabilities.target_languages
    if request.target_languages:
        requested_codes = set(request.target_languages)
        selected_targets = [language for language in selected_targets if language.code.lower() in requested_codes]
        missing_codes = sorted(requested_codes - {language.code.lower() for language in selected_targets})
        if missing_codes:
            raise HTTPException(status_code=400, detail=f"unsupported target language(s): {', '.join(missing_codes)}")

    return validate_translation_targets(
        translator,
        text=request.text,
        source_language=request.source_language,
        model_path=request.model_path,
        target_languages=selected_targets,
        max_languages=request.max_languages,
    )


@app.post("/transcribe", response_model=TranscribeResponse)
async def transcribe(request: Request, provider: str = Query(default="fake")) -> TranscribeResponse:
    started = time.monotonic()
    try:
        asr = registry.get(provider)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"unknown provider: {provider}") from exc

    info = asr.info()
    if not info.available:
        raise HTTPException(status_code=503, detail=info.reason or f"provider unavailable: {provider}")

    audio_bytes = await request.body()
    try:
        text = asr.transcribe(audio_bytes)
    except Exception as exc:
        runtime_store.record_event(
            "transcribe.failed",
            f"Transcription failed for {provider}",
            level="error",
            detail={"provider": provider, "audio_bytes": len(audio_bytes), "error": str(exc)},
        )
        raise HTTPException(status_code=502, detail=f"transcription failed: {exc}") from exc

    duration_ms = int((time.monotonic() - started) * 1000)
    runtime_store.record_transcript(
        source="transcribe",
        raw_text=text,
        provider=provider,
        audio_bytes=len(audio_bytes),
        duration_ms=duration_ms,
    )
    runtime_store.record_event(
        "transcribe.completed",
        f"Transcribed audio with {provider}",
        detail={"provider": provider, "audio_bytes": len(audio_bytes), "duration_ms": duration_ms, "text_length": len(text)},
    )
    return TranscribeResponse(text=text, provider=provider)


@app.websocket("/translation/stream")
async def translation_stream(
    websocket: WebSocket,
    provider: str = "fake",
    source_language: str = "auto",
    target_language: str = "en",
    model_path: str = "",
) -> None:
    await websocket.accept()
    try:
        translator = translation_registry.get(provider)
    except KeyError:
        await websocket.send_json({"type": "error", "text": f"unknown translation provider: {provider}"})
        await websocket.close()
        return

    info = translator.info(model_path)
    if not info.available:
        await websocket.send_json({"type": "error", "text": info.reason or f"provider unavailable: {provider}"})
        await websocket.close()
        return

    try:
        while True:
            message = await websocket.receive_json()
            message_type = str(message.get("type", "partial"))
            if message_type == "finish":
                await websocket.close()
                return

            text = str(message.get("text", ""))
            request = TranslationRequest(
                text=text,
                provider=provider,
                source_language=str(message.get("source_language", source_language)),
                target_language=str(message.get("target_language", target_language)),
                context=message.get("context", []),
                model_path=str(message.get("model_path", model_path)),
                is_final=message_type == "final",
            )
            result = translator.translate(request)
            await websocket.send_json(
                {
                    "type": "final_translation" if result.is_final else "partial_translation",
                    "text": result.text,
                    "provider": result.provider,
                    "source_language": result.source_language,
                    "detected_language": result.detected_language,
                    "target_language": result.target_language,
                    "confidence": result.confidence,
                    "is_final": result.is_final,
                }
            )
    except WebSocketDisconnect:
        return
    except Exception as exc:
        await websocket.send_json({"type": "error", "text": f"translation failed: {exc}"})
        await websocket.close()


@app.websocket("/stream")
async def stream(
    websocket: WebSocket,
    provider: str = "fake",
    sample_rate: int = 16000,
    translate: bool = False,
    translation_provider: str = "fake",
    source_language: str = "auto",
    target_language: str = "en",
    translation_model_path: str = "",
) -> None:
    await websocket.accept()
    runtime_store.record_stream_opened(provider=provider, sample_rate=sample_rate)
    runtime_store.record_event(
        "stream.opened",
        f"Streaming session opened for {provider}",
        detail={"provider": provider, "sample_rate": sample_rate},
    )
    try:
        asr = registry.get(provider)
    except KeyError:
        await websocket.send_json({"type": "error", "text": f"unknown provider: {provider}"})
        runtime_store.record_event(
            "stream.failed",
            "Streaming session used an unknown provider",
            level="warning",
            detail={"provider": provider},
        )
        runtime_store.record_stream_failed(provider=provider, error=f"unknown provider: {provider}")
        await websocket.close()
        return

    info = asr.info()
    if not info.available:
        await websocket.send_json({"type": "error", "text": info.reason or f"provider unavailable: {provider}"})
        runtime_store.record_event(
            "stream.failed",
            f"Streaming provider unavailable: {provider}",
            level="warning",
            detail={"provider": provider, "reason": info.reason},
        )
        runtime_store.record_stream_failed(
            provider=provider,
            error=info.reason or f"provider unavailable: {provider}",
        )
        await websocket.close()
        return

    translator = None
    if translate:
        try:
            translator = translation_registry.get(translation_provider)
        except KeyError:
            await websocket.send_json({"type": "error", "text": f"unknown translation provider: {translation_provider}"})
            runtime_store.record_stream_failed(provider=provider, error=f"unknown translation provider: {translation_provider}")
            await websocket.close()
            return

        translation_info = translator.info(translation_model_path)
        if not translation_info.available:
            await websocket.send_json(
                {
                    "type": "error",
                    "text": translation_info.reason or f"translation provider unavailable: {translation_provider}",
                }
            )
            runtime_store.record_stream_failed(
                provider=provider,
                error=translation_info.reason or f"translation provider unavailable: {translation_provider}",
            )
            await websocket.close()
            return

    chunks: list[bytes] = []
    chunk_count = 0
    partial_count = 0
    last_decode_size = 0
    last_decode_time = 0.0
    partial_decode_bytes = max(4096, sample_rate * 4)
    await websocket.send_json({"type": "partial", "text": "listening"})

    try:
        while True:
            message = await websocket.receive()
            text_message = message.get("text")
            bytes_message = message.get("bytes")

            if text_message == "__finish__":
                combined = b"".join(chunks)
                started = time.monotonic()
                try:
                    final_text = await asyncio.to_thread(asr.transcribe_pcm_float32, combined, sample_rate)
                except Exception as exc:
                    await websocket.send_json({"type": "error", "text": f"transcription failed: {exc}"})
                    runtime_store.record_event(
                        "stream.failed",
                        f"Streaming transcription failed for {provider}",
                        level="error",
                        detail={
                            "provider": provider,
                            "sample_rate": sample_rate,
                            "audio_bytes": len(combined),
                            "chunk_count": chunk_count,
                            "partial_count": partial_count,
                            "error": str(exc),
                        },
                    )
                    runtime_store.record_stream_failed(provider=provider, error=str(exc))
                    await websocket.close()
                    return
                duration_ms = int((time.monotonic() - started) * 1000)
                runtime_store.record_transcript(
                    source="stream",
                    raw_text=final_text,
                    provider=provider,
                    audio_bytes=len(combined),
                    sample_rate=sample_rate,
                    duration_ms=duration_ms,
                )
                runtime_store.record_event(
                    "stream.completed",
                    f"Streaming session completed for {provider}",
                    detail={
                        "provider": provider,
                        "sample_rate": sample_rate,
                        "audio_bytes": len(combined),
                        "chunk_count": chunk_count,
                        "partial_count": partial_count,
                        "duration_ms": duration_ms,
                        "text_length": len(final_text),
                        "translation_enabled": translate,
                        "target_language": target_language if translate else None,
                    },
                )
                runtime_store.record_stream_completed(provider=provider)
                await websocket.send_json(
                    await _stream_transcript_payload(
                        message_type="final",
                        text=final_text,
                        translator=translator,
                        translation_provider=translation_provider,
                        source_language=source_language,
                        target_language=target_language,
                        translation_model_path=translation_model_path,
                    )
                )
                await websocket.close()
                return

            if bytes_message:
                chunks.append(bytes_message)
                chunk_count += 1
                runtime_store.record_stream_chunk(provider=provider, chunk_bytes=len(bytes_message))
                combined = b"".join(chunks)
                now = time.monotonic()
                enough_new_audio = len(combined) - last_decode_size >= partial_decode_bytes
                enough_time = now - last_decode_time >= 1.0
                if enough_new_audio and enough_time:
                    try:
                        partial = await asyncio.to_thread(asr.transcribe_pcm_float32, combined, sample_rate)
                    except Exception as exc:
                        await websocket.send_json({"type": "error", "text": f"transcription failed: {exc}"})
                        runtime_store.record_event(
                            "stream.failed",
                            f"Streaming partial transcription failed for {provider}",
                            level="error",
                            detail={
                                "provider": provider,
                                "sample_rate": sample_rate,
                                "audio_bytes": len(combined),
                                "chunk_count": chunk_count,
                                "partial_count": partial_count,
                                "error": str(exc),
                            },
                        )
                        runtime_store.record_stream_failed(provider=provider, error=str(exc))
                        await websocket.close()
                        return
                    partial_count += 1
                    runtime_store.record_stream_partial(provider=provider, text=partial)
                    await websocket.send_json(
                        await _stream_transcript_payload(
                            message_type="partial",
                            text=partial,
                            translator=translator,
                            translation_provider=translation_provider,
                            source_language=source_language,
                            target_language=target_language,
                            translation_model_path=translation_model_path,
                        )
                    )
                    last_decode_size = len(combined)
                    last_decode_time = now
    except WebSocketDisconnect:
        runtime_store.record_stream_closed(provider=provider)
        runtime_store.record_event(
            "stream.closed",
            f"Streaming session disconnected for {provider}",
            detail={"provider": provider, "chunk_count": chunk_count, "partial_count": partial_count},
        )
        return
    except RuntimeError as exc:
        if "disconnect" in str(exc).lower():
            runtime_store.record_stream_closed(provider=provider)
            runtime_store.record_event(
                "stream.closed",
                f"Streaming session disconnected for {provider}",
                detail={"provider": provider, "chunk_count": chunk_count, "partial_count": partial_count},
            )
            return
        raise


async def _stream_transcript_payload(
    *,
    message_type: str,
    text: str,
    translator,
    translation_provider: str,
    source_language: str,
    target_language: str,
    translation_model_path: str,
) -> dict[str, object]:
    if translator is None:
        return {"type": message_type, "text": text}

    result = await asyncio.to_thread(
        translator.translate,
        TranslationRequest(
            text=text,
            provider=translation_provider,
            source_language=source_language,
            target_language=target_language,
            model_path=translation_model_path,
            is_final=message_type == "final",
        ),
    )
    return {
        "type": message_type,
        "text": result.text,
        "raw_text": text,
        "translated": True,
        "detected_language": result.detected_language,
        "target_language": result.target_language,
    }


@app.get("/api/status", response_model=EngineStatus)
def engine_status() -> EngineStatus:
    return EngineStatus(
        status="ok",
        started_at=runtime_store.started_at,
        uptime_seconds=int(time.monotonic() - STARTED_MONOTONIC),
        providers=registry.list_providers(),
        models=model_manager.list_statuses(),
        event_count=runtime_store.event_count(),
        transcript_count=runtime_store.transcript_count(),
        streaming=runtime_store.streaming_stats(),
    )


@app.post("/api/conversations", response_model=ConversationSessionRecord)
def create_conversation(request: ConversationSessionCreateRequest) -> ConversationSessionRecord:
    session = runtime_store.create_conversation_session(
        title=request.title,
        capture_mode=request.capture_mode,
        asr_provider=request.asr_provider,
        diarization_provider=request.diarization_provider,
        external_processing_enabled=request.external_processing_enabled,
    )
    runtime_store.record_event(
        "conversation.started",
        "Conversation session started",
        detail={
            "session_id": session.id,
            "capture_mode": session.capture_mode,
            "asr_provider": session.asr_provider,
            "diarization_provider": session.diarization_provider,
        },
    )
    return session


@app.get("/api/conversations", response_model=list[ConversationSessionRecord])
def conversations(limit: int = Query(default=100, ge=1, le=1000)) -> list[ConversationSessionRecord]:
    return runtime_store.recent_conversation_sessions(limit)


@app.get("/api/conversations/{session_id}/export")
def export_conversation(session_id: str) -> Response:
    session = runtime_store.conversation_session(session_id)
    if session is None:
        raise HTTPException(status_code=404, detail=f"conversation not found: {session_id}")

    lines = [f"# {session.title}", ""]
    for segment in runtime_store.conversation_segments(session_id):
        seconds = max(0, segment.start_ms // 1000)
        timestamp = f"{seconds // 60:02d}:{seconds % 60:02d}"
        lines.append(f"{segment.speaker_display_name} [{timestamp}]: {segment.text}")

    return Response(
        content="\n".join(lines).strip() + "\n",
        media_type="text/plain",
        headers={"Content-Disposition": f'attachment; filename="conversation-{session_id}.txt"'},
    )


@app.get("/api/conversations/{session_id}", response_model=ConversationDetail)
def conversation_detail(session_id: str) -> ConversationDetail:
    session = runtime_store.conversation_session(session_id)
    if session is None:
        raise HTTPException(status_code=404, detail=f"conversation not found: {session_id}")
    return ConversationDetail(
        session=session,
        segments=runtime_store.conversation_segments(session_id),
        assist_cards=runtime_store.conversation_assist_cards(session_id),
    )


@app.patch("/api/conversations/{session_id}", response_model=ConversationDetail)
def update_conversation(session_id: str, request: ConversationDetailUpdateRequest) -> ConversationDetail:
    session = runtime_store.conversation_session(session_id)
    if session is None:
        raise HTTPException(status_code=404, detail=f"conversation not found: {session_id}")

    updated_session = runtime_store.update_conversation_session(session_id, title=request.title)
    if updated_session is None:
        raise HTTPException(status_code=404, detail=f"conversation not found: {session_id}")

    segment_texts = {segment.id: segment.text for segment in request.segments}
    updated_segments = runtime_store.update_conversation_segments(
        session_id,
        speaker_names=request.speaker_names,
        segment_texts=segment_texts,
    )
    if updated_segments is None:
        requested_ids = set(segment_texts)
        existing_ids = {segment.id for segment in runtime_store.conversation_segments(session_id)}
        missing_id = sorted(requested_ids.difference(existing_ids))[0]
        raise HTTPException(status_code=404, detail=f"conversation segment not found: {missing_id}")

    runtime_store.record_event(
        "conversation.updated",
        "Conversation session updated",
        detail={
            "session_id": session_id,
            "renamed_speakers": len(request.speaker_names),
            "edited_segments": len(request.segments),
        },
    )
    return ConversationDetail(
        session=updated_session,
        segments=updated_segments,
        assist_cards=runtime_store.conversation_assist_cards(session_id),
    )


@app.delete("/api/conversations/{session_id}")
def delete_conversation(session_id: str) -> dict[str, str]:
    deleted = runtime_store.delete_conversation_session(session_id)
    if not deleted:
        raise HTTPException(status_code=404, detail=f"conversation not found: {session_id}")
    runtime_store.record_event(
        "conversation.deleted",
        "Conversation session deleted",
        detail={"session_id": session_id},
    )
    return {"status": "deleted", "session_id": session_id}


@app.post("/api/conversations/import", response_model=ConversationImportResult)
def import_conversation(detail: ConversationDetail) -> ConversationImportResult:
    session_id = detail.session.id
    mismatched_segment_ids = [segment.id for segment in detail.segments if segment.session_id != session_id]
    mismatched_card_ids = [card.id for card in detail.assist_cards if card.session_id != session_id]
    if mismatched_segment_ids or mismatched_card_ids:
        raise HTTPException(
            status_code=422,
            detail={
                "message": "conversation archive contains records for a different session",
                "segments": mismatched_segment_ids,
                "assist_cards": mismatched_card_ids,
            },
        )

    status = runtime_store.import_conversation_detail(detail)
    runtime_store.record_event(
        "conversation.imported",
        "Conversation session imported from archive",
        detail={
            "session_id": session_id,
            "status": status,
            "segments": len(detail.segments),
            "assist_cards": len(detail.assist_cards),
        },
    )
    return ConversationImportResult(
        status=status,
        session_id=session_id,
        segments=len(detail.segments),
        assist_cards=len(detail.assist_cards),
    )


@app.post("/api/conversations/{session_id}/segments", response_model=ConversationSegmentRecord)
def add_conversation_segment(session_id: str, request: ConversationSegmentCreateRequest) -> ConversationSegmentRecord:
    resolved = _resolve_conversation_segment(
        session_id=session_id,
        request=request,
        record_events=True,
        align_speaker_lines=True,
    )

    return runtime_store.add_conversation_segment(
        session_id=session_id,
        speaker_id=resolved.speaker_id,
        speaker_display_name=resolved.speaker_display_name,
        start_ms=request.start_ms,
        end_ms=request.end_ms,
        text=request.text,
        state=request.state,
        confidence=resolved.confidence,
        speaker_turns=resolved.speaker_turns,
        speaker_lines=resolved.speaker_lines,
    )


@app.post("/api/conversations/{session_id}/segments/preview", response_model=ConversationSegmentRecord)
def preview_conversation_segment(session_id: str, request: ConversationSegmentCreateRequest) -> ConversationSegmentRecord:
    resolved = _resolve_conversation_segment(
        session_id=session_id,
        request=request,
        record_events=False,
        align_speaker_lines=True,
    )

    segment = ConversationSegmentRecord(
        id=f"live-{session_id}",
        session_id=session_id,
        speaker_id=resolved.speaker_id,
        speaker_display_name=resolved.speaker_display_name,
        start_ms=request.start_ms,
        end_ms=request.end_ms,
        text=request.text,
        state=request.state,
        confidence=resolved.confidence,
        speaker_turns=resolved.speaker_turns,
        speaker_lines=resolved.speaker_lines,
    )
    runtime_store.remember_conversation_preview_segment(session_id, segment)
    return segment


@dataclass(frozen=True)
class ResolvedConversationSegment:
    speaker_id: str
    speaker_display_name: str
    confidence: float | None
    speaker_turns: list[SpeakerTurnRecord]
    speaker_lines: list[ConversationSpeakerLineRecord]


def _resolve_conversation_segment(
    *,
    session_id: str,
    request: ConversationSegmentCreateRequest,
    record_events: bool,
    align_speaker_lines: bool,
) -> ResolvedConversationSegment:
    session = runtime_store.conversation_session(session_id)
    if session is None:
        raise HTTPException(status_code=404, detail=f"conversation not found: {session_id}")
    speaker_id = request.speaker_id
    speaker_display_name = request.speaker_display_name
    confidence = request.confidence
    speaker_turns: list[SpeakerTurnRecord] = []
    speaker_lines: list[ConversationSpeakerLineRecord] = []
    audio: DiarizationAudio | None = None

    if speaker_id is None or speaker_display_name is None:
        audio = _diarization_audio_from_request(request)
        try:
            diarizer = diarization_registry.get(session.diarization_provider)
        except KeyError as exc:
            raise HTTPException(status_code=404, detail=f"unknown diarization provider: {session.diarization_provider}") from exc
        info = diarizer.info()
        if not info.available:
            if record_events:
                runtime_store.record_event(
                    "diarization.unavailable",
                    "Speaker diarization unavailable; saved transcript with a generic speaker",
                    level="warning",
                    detail={
                        "session_id": session_id,
                        "provider": session.diarization_provider,
                        "reason": info.reason or f"diarization provider unavailable: {info.id}",
                    },
                )
            speaker_id = "speaker"
            speaker_display_name = "Speaker"
        else:
            try:
                assignment = diarizer.assign_speaker(
                    session_id=session_id,
                    text=request.text,
                    start_ms=request.start_ms,
                    end_ms=request.end_ms,
                    existing_segments=runtime_store.conversation_segments(session_id),
                    audio=audio,
                )
            except Exception as exc:
                if record_events:
                    runtime_store.record_event(
                        "diarization.failed",
                        "Speaker diarization failed; saved transcript with a generic speaker",
                        level="error",
                        detail={"session_id": session_id, "provider": session.diarization_provider, "error": str(exc)},
                    )
                speaker_id = "speaker"
                speaker_display_name = "Speaker"
            else:
                speaker_id = assignment.speaker_id
                speaker_display_name = assignment.speaker_display_name
                confidence = confidence if confidence is not None else assignment.confidence
                speaker_turns = _speaker_turn_records_from_assignment(
                    session_id=session_id,
                    assignment=assignment,
                    source_provider=session.diarization_provider,
                )
                if record_events:
                    runtime_store.record_event(
                        "diarization.assigned",
                        "Local diarization assigned a speaker",
                        detail={
                            "session_id": session_id,
                            "provider": session.diarization_provider,
                            "speaker_id": speaker_id,
                            "unique_speakers": len({turn.speaker_id for turn in speaker_turns}),
                            "turn_count": len(speaker_turns),
                            "start_ms": request.start_ms,
                            "end_ms": request.end_ms,
                            "audio_bytes": len(audio.pcm_float32) if audio else 0,
                        },
                    )

    if align_speaker_lines and audio is not None and speaker_turns:
        speaker_lines = _speaker_line_records_from_aligned_transcript(
            session_id=session_id,
            asr_provider_id=session.asr_provider,
            audio=audio,
            speaker_turns=speaker_turns,
            source_provider=session.diarization_provider,
        )

    preview_fallback = _preview_diarization_fallback(
        session_id=session_id,
        speaker_turns=speaker_turns,
        speaker_lines=speaker_lines,
    )
    if record_events and preview_fallback is not None:
        speaker_turns = preview_fallback.speaker_turns
        speaker_lines = preview_fallback.speaker_lines or speaker_lines
        speaker_id, confidence = _dominant_speaker_from_turn_records(speaker_turns)
        speaker_display_name = _speaker_display_name(speaker_id)
        runtime_store.record_event(
            "diarization.preview_fallback",
            "Final diarization collapsed; reused live preview speaker evidence",
            level="warning",
            detail={
                "session_id": session_id,
                "provider": session.diarization_provider,
                "unique_speakers": _speaker_count_from_turn_records(speaker_turns),
                "turn_count": len(speaker_turns),
                "line_count": len(speaker_lines),
            },
        )

    return ResolvedConversationSegment(
        speaker_id=speaker_id,
        speaker_display_name=speaker_display_name,
        confidence=confidence,
        speaker_turns=speaker_turns,
        speaker_lines=speaker_lines,
    )


@dataclass(frozen=True)
class PreviewDiarizationFallback:
    speaker_turns: list[SpeakerTurnRecord]
    speaker_lines: list[ConversationSpeakerLineRecord]


def _preview_diarization_fallback(
    *,
    session_id: str,
    speaker_turns: list[SpeakerTurnRecord],
    speaker_lines: list[ConversationSpeakerLineRecord],
) -> PreviewDiarizationFallback | None:
    if _speaker_count_from_turn_records(speaker_turns) > 1:
        return None

    preview_segments = runtime_store.conversation_preview_segments(session_id)
    preview_turns = _dedupe_speaker_turn_records(
        turn
        for segment in preview_segments
        for turn in segment.speaker_turns
    )
    if _speaker_count_from_turn_records(preview_turns) <= 1:
        return None

    preview_lines = _dedupe_speaker_line_records(
        line
        for segment in preview_segments
        for line in segment.speaker_lines
    )
    if speaker_lines and _speaker_count_from_line_records(speaker_lines) > 1:
        preview_lines = speaker_lines

    return PreviewDiarizationFallback(speaker_turns=preview_turns, speaker_lines=preview_lines)


def _speaker_count_from_turn_records(turns: list[SpeakerTurnRecord]) -> int:
    return len({turn.speaker_id for turn in turns})


def _speaker_count_from_line_records(lines: list[ConversationSpeakerLineRecord]) -> int:
    return len({line.speaker_id for line in lines})


def _dedupe_speaker_turn_records(turns: Iterable[SpeakerTurnRecord]) -> list[SpeakerTurnRecord]:
    deduped: dict[tuple[str, int, int | None], SpeakerTurnRecord] = {}
    for turn in turns:
        deduped[(turn.speaker_id, turn.start_ms, turn.end_ms)] = turn
    return sorted(deduped.values(), key=lambda turn: (turn.start_ms, turn.end_ms or turn.start_ms, turn.speaker_id))


def _dedupe_speaker_line_records(lines: Iterable[ConversationSpeakerLineRecord]) -> list[ConversationSpeakerLineRecord]:
    deduped: dict[tuple[str, int, int | None, str], ConversationSpeakerLineRecord] = {}
    for line in lines:
        text = line.text.strip()
        if not text:
            continue
        deduped[(line.speaker_id, line.start_ms, line.end_ms, text)] = line
    return sorted(deduped.values(), key=lambda line: (line.start_ms, line.end_ms or line.start_ms, line.speaker_id))


def _dominant_speaker_from_turn_records(turns: list[SpeakerTurnRecord]) -> tuple[str, float | None]:
    totals: dict[str, int] = {}
    confidences: dict[str, list[float]] = {}
    for turn in turns:
        duration = max(0, (turn.end_ms or turn.start_ms) - turn.start_ms)
        if duration <= 0:
            continue
        totals[turn.speaker_id] = totals.get(turn.speaker_id, 0) + duration
        if turn.confidence is not None:
            confidences.setdefault(turn.speaker_id, []).append(turn.confidence)

    if not totals:
        return "speaker-1", None
    speaker_id = max(totals, key=totals.get)
    confidence_values = confidences.get(speaker_id, [])
    if not confidence_values:
        return speaker_id, 0.7
    return speaker_id, sum(confidence_values) / len(confidence_values)


def _speaker_display_name(speaker_id: str) -> str:
    suffix = speaker_id.removeprefix("speaker-")
    if suffix.isdigit():
        return f"Speaker {suffix}"
    return speaker_id.replace("-", " ").title()


def _speaker_line_records_from_aligned_transcript(
    *,
    session_id: str,
    asr_provider_id: str,
    audio: DiarizationAudio,
    speaker_turns: list[SpeakerTurnRecord],
    source_provider: str,
) -> list[ConversationSpeakerLineRecord]:
    try:
        asr = registry.get(asr_provider_id)
        transcript = asr.transcribe_aligned_pcm_float32(audio.pcm_float32, audio.sample_rate)
        return build_speaker_lines(
            session_id=session_id,
            transcript=transcript,
            speaker_turns=speaker_turns,
            audio_start_ms=audio.start_ms,
            source_provider=source_provider,
        )
    except Exception as exc:
        runtime_store.record_event(
            "diarization.alignment_failed",
            "Speaker diarization completed but transcript alignment failed",
            level="warning",
            detail={"session_id": session_id, "asr_provider": asr_provider_id, "error": str(exc)},
        )
        return []


def _speaker_turn_records_from_assignment(
    *,
    session_id: str,
    assignment: object,
    source_provider: str,
) -> list[SpeakerTurnRecord]:
    raw_turns = getattr(assignment, "speaker_turns", None) or getattr(assignment, "turns", None) or []
    records: list[SpeakerTurnRecord] = []
    for raw_turn in raw_turns:
        speaker_id = _turn_value(raw_turn, "speaker_id") or _turn_value(raw_turn, "speaker") or _turn_value(raw_turn, "label")
        start_ms = _turn_int(raw_turn, "start_ms")
        if start_ms is None:
            start_seconds = _turn_float(raw_turn, "start")
            start_ms = int(round(start_seconds * 1_000)) if start_seconds is not None else None
        if speaker_id is None or start_ms is None:
            continue

        end_ms = _turn_int(raw_turn, "end_ms")
        if end_ms is None:
            end_seconds = _turn_float(raw_turn, "end")
            end_ms = int(round(end_seconds * 1_000)) if end_seconds is not None else None

        confidence = _turn_float(raw_turn, "confidence")
        overlap = bool(_turn_value(raw_turn, "overlap") or _turn_value(raw_turn, "overlapped"))
        provider = str(_turn_value(raw_turn, "source_provider") or source_provider)
        try:
            records.append(
                SpeakerTurnRecord(
                    id=str(uuid.uuid4()),
                    session_id=session_id,
                    speaker_id=str(speaker_id),
                    start_ms=start_ms,
                    end_ms=end_ms,
                    confidence=confidence,
                    overlap=overlap,
                    source_provider=provider,
                )
            )
        except ValueError:
            continue
    return records


def _turn_value(raw_turn: object, key: str) -> object | None:
    if isinstance(raw_turn, dict):
        return raw_turn.get(key)
    return getattr(raw_turn, key, None)


def _turn_int(raw_turn: object, key: str) -> int | None:
    value = _turn_value(raw_turn, key)
    if value is None:
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _turn_float(raw_turn: object, key: str) -> float | None:
    value = _turn_value(raw_turn, key)
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _diarization_audio_from_request(request: ConversationSegmentCreateRequest) -> DiarizationAudio | None:
    if request.audio_pcm_float32_base64 is None:
        return None
    try:
        pcm_float32 = base64.b64decode(request.audio_pcm_float32_base64, validate=True)
    except binascii.Error as exc:
        raise HTTPException(status_code=422, detail="audio_pcm_float32_base64 must be valid base64") from exc
    if len(pcm_float32) % 4 != 0:
        raise HTTPException(status_code=422, detail="audio_pcm_float32_base64 must contain float32 PCM bytes")
    return DiarizationAudio(
        pcm_float32=pcm_float32,
        sample_rate=request.audio_sample_rate or 0,
        start_ms=request.audio_start_ms if request.audio_start_ms is not None else request.start_ms,
        end_ms=request.end_ms,
    )


@app.post("/api/conversations/{session_id}/assist-cards", response_model=ConversationAssistCardRecord)
def add_conversation_assist_card(
    session_id: str,
    request: ConversationAssistCardCreateRequest,
) -> ConversationAssistCardRecord:
    if runtime_store.conversation_session(session_id) is None:
        raise HTTPException(status_code=404, detail=f"conversation not found: {session_id}")
    return runtime_store.add_conversation_assist_card(
        session_id=session_id,
        kind=request.kind,
        title=request.title,
        body=request.body,
        source_references=request.source_references,
        confidence=request.confidence,
    )


@app.post("/api/conversations/{session_id}/stop", response_model=ConversationSessionRecord)
def stop_conversation(session_id: str) -> ConversationSessionRecord:
    session = runtime_store.stop_conversation_session(session_id)
    if session is None:
        raise HTTPException(status_code=404, detail=f"conversation not found: {session_id}")
    runtime_store.record_event(
        "conversation.stopped",
        "Conversation session stopped",
        detail={"session_id": session.id},
    )
    return session


@app.get("/api/events", response_model=list[EngineEvent])
def engine_events(limit: int = Query(default=200, ge=1, le=1000)) -> list[EngineEvent]:
    return runtime_store.recent_events(limit)


@app.get("/api/transcripts", response_model=list[TranscriptRecord])
def transcripts(limit: int = Query(default=200, ge=1, le=1000)) -> list[TranscriptRecord]:
    return runtime_store.recent_transcripts(limit)


@app.get("/api/events/export")
def export_events() -> Response:
    return Response(
        content=runtime_store.export_events(),
        media_type="application/x-ndjson",
        headers={"Content-Disposition": 'attachment; filename="omnivoice-events.jsonl"'},
    )


@app.get("/api/transcripts/export")
def export_transcripts() -> Response:
    return Response(
        content=runtime_store.export_transcripts(),
        media_type="application/x-ndjson",
        headers={"Content-Disposition": 'attachment; filename="omnivoice-transcripts.jsonl"'},
    )


def _download_model(provider_id: str, token: str | None = None) -> None:
    try:
        state = model_manager.download(provider_id, token=token)
        runtime_store.record_event(
            "model.download.completed",
            f"Model download completed for {provider_id}",
            detail={"provider_id": provider_id, "state": state.state, "revision": state.revision},
        )
    except Exception as exc:
        runtime_store.record_event(
            "model.download.failed",
            f"Model download failed for {provider_id}",
            level="error",
            detail={"provider_id": provider_id, "error": str(exc)},
        )
        return


def bearer_token(authorization: str | None) -> str | None:
    value = (authorization or "").strip()
    if not value:
        return None
    prefix = "bearer "
    if value.lower().startswith(prefix):
        return value[len(prefix) :].strip() or None
    return value


def _ai_handoff_user_content(*, prompt: str, context: str) -> str:
    if context:
        return f"Foreground context:\n{context}\n\nUser request:\n{prompt}"
    return prompt


def ai_chat_web_search_query(request: AIChatRequest) -> str:
    explicit_query = request.web_search_query.strip()
    if explicit_query:
        return explicit_query
    for message in reversed(request.messages):
        if message.role == "user" and message.content.strip():
            return message.content.strip()
    return ""


def ai_chat_web_search_context(query: str, results: list[WebSearchResult]) -> str:
    if not results:
        return f"Web search was requested for: {query}\nNo web results were found."

    lines = [
        f"Web search results for: {query}",
        "Use these results as current external context. Cite URLs when using them.",
    ]
    for index, result in enumerate(results[:5], start=1):
        lines.append(f"{index}. {result.title}")
        lines.append(f"URL: {result.url}")
        if result.snippet:
            lines.append(f"Snippet: {result.snippet}")
    return "\n".join(lines)


def web_search_handler(query: str, limit: int = 5) -> list[WebSearchResult]:
    return duckduckgo_web_search(query, limit=limit)


def duckduckgo_web_search(query: str, limit: int = 5) -> list[WebSearchResult]:
    normalized_query = query.strip()
    if not normalized_query:
        return []

    endpoint = "https://duckduckgo.com/html/?" + urlencode({"q": normalized_query})
    request = urllib.request.Request(
        endpoint,
        headers={
            "User-Agent": "OmniSpeak/1.0 (+https://localhost)",
            "Accept": "text/html,application/xhtml+xml",
        },
        method="GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=10.0) as response:
            body = response.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        raise RuntimeError(upstream_http_error_message(endpoint, exc)) from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(str(exc.reason)) from exc

    parser = DuckDuckGoHTMLParser(limit=limit)
    parser.feed(body)
    return parser.results


class DuckDuckGoHTMLParser(HTMLParser):
    def __init__(self, limit: int):
        super().__init__()
        self.limit = max(1, limit)
        self.results: list[WebSearchResult] = []
        self._capturing_title = False
        self._capturing_snippet = False
        self._current_title: list[str] = []
        self._current_url = ""
        self._pending_result_index: int | None = None
        self._current_snippet: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attrs_dict = {name: value or "" for name, value in attrs}
        class_name = attrs_dict.get("class", "")
        if tag == "a" and "result__a" in class_name:
            self._capturing_title = True
            self._current_title = []
            self._current_url = clean_duckduckgo_url(attrs_dict.get("href", ""))
        elif "result__snippet" in class_name:
            self._capturing_snippet = True
            self._current_snippet = []

    def handle_data(self, data: str) -> None:
        if self._capturing_title:
            self._current_title.append(data)
        elif self._capturing_snippet:
            self._current_snippet.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag == "a" and self._capturing_title:
            self._capturing_title = False
            title = compact_whitespace("".join(self._current_title))
            if title and self._current_url and len(self.results) < self.limit:
                self.results.append(WebSearchResult(title=title, url=self._current_url))
                self._pending_result_index = len(self.results) - 1
        elif self._capturing_snippet and tag in {"a", "div", "span"}:
            self._capturing_snippet = False
            snippet = compact_whitespace("".join(self._current_snippet))
            if snippet and self._pending_result_index is not None:
                result = self.results[self._pending_result_index]
                self.results[self._pending_result_index] = WebSearchResult(
                    title=result.title,
                    url=result.url,
                    snippet=snippet,
                )
                self._pending_result_index = None


def clean_duckduckgo_url(value: str) -> str:
    parsed = urlparse(value)
    if parsed.netloc.endswith("duckduckgo.com") and parsed.path.startswith("/l/"):
        target = parse_qs(parsed.query).get("uddg", [""])[0]
        if target:
            return target
    return value


def compact_whitespace(value: str) -> str:
    return " ".join(value.split())


def build_ai_chat_messages(request: AIChatRequest, web_search_context: str = "") -> list[dict[str, object]]:
    messages: list[dict[str, object]] = [{"role": "system", "content": AI_CHAT_SYSTEM_PROMPT}]
    for message in request.messages:
        content = message.content.strip()
        if content or message.role == "assistant":
            messages.append({"role": message.role, "content": content})

    if request.attachments or web_search_context:
        last_user_index = next(
            (index for index in range(len(messages) - 1, 0, -1) if messages[index]["role"] == "user"),
            None,
        )
        if last_user_index is None:
            messages.append({"role": "user", "content": ""})
            last_user_index = len(messages) - 1
        messages[last_user_index]["content"] = ai_chat_content_with_attachments(
            existing_content=messages[last_user_index]["content"],
            attachments=request.attachments,
            transport=request.transport,
            extra_context=web_search_context,
        )

    if len(messages) == 1:
        messages.append({"role": "user", "content": ""})
    return messages


def ai_chat_content_with_attachments(
    *,
    existing_content: object,
    attachments: list[object],
    transport: str,
    extra_context: str = "",
) -> object:
    text = message_content_as_text(existing_content).strip()
    if extra_context:
        text = f"{text}\n\n{extra_context}".strip()
    attachment_context = ai_chat_attachment_context(attachments)
    if attachment_context:
        text = f"{text}\n\n{attachment_context}".strip()

    image_attachments = [
        attachment
        for attachment in attachments
        if getattr(attachment, "kind", "") == "image" and getattr(attachment, "data_url", "").strip()
    ]
    if image_attachments and transport in {"openai_compatible", "anthropic", "github_copilot_oauth"}:
        content_parts: list[dict[str, object]] = [{"type": "text", "text": text or "Please analyze the attached image."}]
        for attachment in image_attachments:
            content_parts.append(
                {
                    "type": "image_url",
                    "image_url": {"url": getattr(attachment, "data_url").strip()},
                }
            )
        return content_parts
    return text


def ai_chat_attachment_context(attachments: list[object]) -> str:
    sections: list[str] = []
    for attachment in attachments:
        title = str(getattr(attachment, "title", "")).strip() or "Attachment"
        kind = str(getattr(attachment, "kind", "file")).strip() or "file"
        text = str(getattr(attachment, "text", "")).strip()
        if kind == "image":
            image_detail = text or "Image attached."
            sections.append(f"### Image: {title}\n{image_detail}")
        elif text:
            sections.append(f"### {kind.title()}: {title}\n{text}")
        else:
            sections.append(f"### {kind.title()}: {title}\nNo text was extracted from this attachment.")
    if not sections:
        return ""
    return "Attached context:\n\n" + "\n\n".join(sections)


def message_content_as_text(content: object) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts: list[str] = []
        for item in content:
            if isinstance(item, dict):
                if item.get("type") == "text":
                    parts.append(str(item.get("text", "")))
                elif item.get("type") == "image_url":
                    parts.append("[Image attachment]")
        return "\n".join(part for part in parts if part)
    return str(content or "")


def anthropic_message_content(content: object) -> object:
    if not isinstance(content, list):
        return content

    blocks: list[dict[str, object]] = []
    for item in content:
        if not isinstance(item, dict):
            continue
        if item.get("type") == "text":
            blocks.append({"type": "text", "text": str(item.get("text", ""))})
        elif item.get("type") == "image_url":
            image_url = item.get("image_url")
            url = image_url.get("url", "") if isinstance(image_url, dict) else ""
            parsed = parse_data_url(str(url))
            if parsed is None:
                continue
            media_type, data = parsed
            blocks.append(
                {
                    "type": "image",
                    "source": {
                        "type": "base64",
                        "media_type": media_type,
                        "data": data,
                    },
                }
            )
    return blocks or message_content_as_text(content)


def parse_data_url(value: str) -> tuple[str, str] | None:
    prefix = "data:"
    marker = ";base64,"
    if not value.startswith(prefix) or marker not in value:
        return None
    media_type, data = value[len(prefix) :].split(marker, 1)
    media_type = media_type.strip() or "application/octet-stream"
    data = data.strip()
    if not data:
        return None
    return media_type, data


def normalized_headers(headers: dict[str, str]) -> dict[str, str]:
    normalized: dict[str, str] = {}
    for name, value in headers.items():
        key = str(name).strip()
        if key:
            normalized[key] = str(value).strip()
    return normalized


def merge_extra_headers(headers: dict[str, str], extra_headers: dict[str, str]) -> dict[str, str]:
    merged = dict(headers)
    for name, value in extra_headers.items():
        if name.lower() == "content-length":
            continue
        merged[name] = value
    return merged


def upstream_http_error_message(endpoint: str, exc: urllib.error.HTTPError) -> str:
    detail = exc.read().decode("utf-8", errors="replace").strip()
    host = urlparse(endpoint).netloc or "upstream"
    reason = str(exc.reason or "").strip()
    status = f"{exc.code} {reason}".strip()
    if is_html_response(detail, exc.headers):
        return f"upstream returned {status} from {host}; response was HTML instead of JSON"
    if not detail:
        return f"upstream returned {status} from {host}"
    return f"upstream returned {status} from {host}: {compact_upstream_detail(detail)}"


def is_html_response(detail: str, headers: HTTPMessage | None) -> bool:
    content_type = headers.get("Content-Type", "") if headers is not None else ""
    prefix = detail.lstrip()[:256].lower()
    return (
        "text/html" in content_type.lower()
        or prefix.startswith("<!doctype html")
        or prefix.startswith("<html")
    )


def compact_upstream_detail(detail: str, max_length: int = 420) -> str:
    try:
        body = json.loads(detail)
    except ValueError:
        compacted = " ".join(detail.split())
    else:
        compacted = compact_upstream_json_detail(body)
    if len(compacted) <= max_length:
        return compacted
    return f"{compacted[:max_length].rstrip()}..."


def compact_upstream_json_detail(body: object) -> str:
    if isinstance(body, dict):
        value = body.get("detail") or body.get("message")
        error = body.get("error")
        if not value and isinstance(error, dict):
            value = error.get("message") or error.get("error_description") or error.get("type")
        if not value and isinstance(error, str):
            value = error
        return str(value or body)
    return str(body)


def openai_compatible_chat_completion(
    *,
    base_url: str,
    api_key: str,
    model: str,
    messages: list[dict[str, object]],
    timeout: float,
    oauth_access_token: str = "",
    headers: dict[str, str] | None = None,
) -> str:
    endpoint = f"{base_url.rstrip('/')}/chat/completions"
    payload = json.dumps(
        {
            "model": model,
            "messages": messages,
            "temperature": 0.3,
        }
    ).encode("utf-8")
    request_headers = {"Content-Type": "application/json"}
    if api_key:
        request_headers["Authorization"] = f"Bearer {api_key}"
    request_headers = merge_extra_headers(request_headers, headers or {})

    request = urllib.request.Request(endpoint, data=payload, headers=request_headers, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            response_body = response.read()
    except urllib.error.HTTPError as exc:
        raise RuntimeError(upstream_http_error_message(endpoint, exc)) from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(str(exc.reason)) from exc

    try:
        body = json.loads(response_body.decode("utf-8"))
        text = body["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError, ValueError) as exc:
        raise RuntimeError("upstream response did not include message content") from exc

    cleaned = str(text).strip()
    if not cleaned:
        raise RuntimeError("upstream returned empty content")
    return cleaned


def anthropic_chat_completion(
    *,
    base_url: str,
    api_key: str,
    model: str,
    messages: list[dict[str, object]],
    timeout: float,
    oauth_access_token: str = "",
    headers: dict[str, str] | None = None,
) -> str:
    endpoint = f"{base_url.rstrip('/')}/messages"
    system_prompt = "\n\n".join(
        message_content_as_text(message.get("content", "")).strip()
        for message in messages
        if message["role"] == "system" and message_content_as_text(message.get("content", "")).strip()
    )
    user_messages = [
        {"role": message["role"], "content": anthropic_message_content(message.get("content", ""))}
        for message in messages
        if message["role"] != "system"
    ]
    payload = json.dumps(
        {
            "model": model,
            "max_tokens": 1200,
            "temperature": 0.3,
            "system": system_prompt,
            "messages": user_messages,
        }
    ).encode("utf-8")
    request_headers = {
        "Content-Type": "application/json",
        "anthropic-version": "2023-06-01",
    }
    if api_key:
        request_headers["x-api-key"] = api_key
    request_headers = merge_extra_headers(request_headers, headers or {})

    request = urllib.request.Request(endpoint, data=payload, headers=request_headers, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            response_body = response.read()
    except urllib.error.HTTPError as exc:
        raise RuntimeError(upstream_http_error_message(endpoint, exc)) from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(str(exc.reason)) from exc

    try:
        body = json.loads(response_body.decode("utf-8"))
        content = body["content"]
        text_parts = [part.get("text", "") for part in content if part.get("type") == "text"]
        text = "\n".join(part for part in text_parts if part)
    except (KeyError, TypeError, ValueError) as exc:
        raise RuntimeError("upstream response did not include message content") from exc

    cleaned = str(text).strip()
    if not cleaned:
        raise RuntimeError("upstream returned empty content")
    return cleaned


def openai_codex_oauth_completion(
    *,
    base_url: str,
    oauth_access_token: str,
    model: str,
    messages: list[dict[str, object]],
    timeout: float,
    api_key: str = "",
    headers: dict[str, str] | None = None,
) -> str:
    endpoint_base = base_url.rstrip("/") if base_url else "https://chatgpt.com/backend-api"
    endpoint = f"{endpoint_base}/codex/responses"
    instructions, input_messages = openai_codex_response_parts(messages)
    payload = json.dumps(
        {
            "model": model,
            "instructions": instructions,
            "input": input_messages,
            "store": False,
            "stream": True,
        }
    ).encode("utf-8")
    request_headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {oauth_access_token}",
    }
    request_headers = merge_extra_headers(request_headers, headers or {})

    request = urllib.request.Request(endpoint, data=payload, headers=request_headers, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            response_body = response.read()
    except urllib.error.HTTPError as exc:
        raise RuntimeError(upstream_http_error_message(endpoint, exc)) from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(str(exc.reason)) from exc

    return extract_chat_text(response_body)


def openai_codex_response_parts(messages: list[dict[str, object]]) -> tuple[str, list[dict[str, str]]]:
    instructions = "\n\n".join(
        message_content_as_text(message.get("content", "")).strip()
        for message in messages
        if message.get("role") == "system" and message_content_as_text(message.get("content", "")).strip()
    ).strip()
    input_messages = [
        {"role": str(message.get("role", "user")), "content": message_content_as_text(message.get("content", ""))}
        for message in messages
        if message.get("role") != "system" and message_content_as_text(message.get("content", "")).strip()
    ]
    if not instructions:
        instructions = "Return only the text to insert."
    if not input_messages:
        input_messages = [{"role": "user", "content": ""}]
    return instructions, input_messages


def github_copilot_oauth_completion(
    *,
    base_url: str,
    oauth_access_token: str,
    model: str,
    messages: list[dict[str, object]],
    timeout: float,
    api_key: str = "",
    headers: dict[str, str] | None = None,
) -> str:
    endpoint_base = base_url.rstrip("/") if base_url else "https://api.githubcopilot.com"
    endpoint = f"{endpoint_base}/chat/completions"
    copilot_token = fetch_github_copilot_token(
        oauth_access_token,
        timeout=timeout,
        headers=headers or {},
    )
    payload = json.dumps(
        {
            "model": model,
            "messages": messages,
            "temperature": 0.3,
            "stream": False,
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        endpoint,
        data=payload,
        headers=github_copilot_headers(copilot_token, headers=headers or {}),
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            response_body = response.read()
    except urllib.error.HTTPError as exc:
        raise RuntimeError(upstream_http_error_message(endpoint, exc)) from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(str(exc.reason)) from exc

    return extract_chat_text(response_body)


def openai_compatible_model_list(
    *,
    base_url: str,
    api_key: str,
    oauth_access_token: str,
    timeout: float,
    headers: dict[str, str] | None = None,
) -> list[str]:
    request_headers = {"Accept": "application/json"}
    if api_key:
        request_headers["Authorization"] = f"Bearer {api_key}"
    request_headers = merge_extra_headers(request_headers, headers or {})
    return fetch_model_list(f"{base_url.rstrip('/')}/models", request_headers, timeout=timeout)


def anthropic_model_list(
    *,
    base_url: str,
    api_key: str,
    oauth_access_token: str,
    timeout: float,
    headers: dict[str, str] | None = None,
) -> list[str]:
    request_headers = {
        "Accept": "application/json",
        "anthropic-version": "2023-06-01",
    }
    if api_key:
        request_headers["x-api-key"] = api_key
    request_headers = merge_extra_headers(request_headers, headers or {})
    return fetch_model_list(f"{base_url.rstrip('/')}/models", request_headers, timeout=timeout)


def openai_codex_model_list(
    *,
    base_url: str,
    api_key: str,
    oauth_access_token: str,
    timeout: float,
    headers: dict[str, str] | None = None,
) -> list[str]:
    return codex_cli_model_list() or list(OPENAI_CODEX_RECOMMENDED_MODELS)


def codex_cli_model_list() -> list[str]:
    cache_path = Path.home() / ".codex" / "models_cache.json"
    try:
        body = json.loads(cache_path.read_text())
    except (OSError, ValueError):
        return []

    candidates = body.get("models") if isinstance(body, dict) else body
    if not isinstance(candidates, list):
        return []

    model_ids: list[str] = []
    seen: set[str] = set()
    for item in candidates:
        model_id = ""
        if isinstance(item, str):
            model_id = item
        elif isinstance(item, dict):
            value = item.get("slug") or item.get("id") or item.get("name") or item.get("model")
            if isinstance(value, str):
                model_id = value
        model_id = model_id.strip()
        if not model_id or "auto-review" in model_id:
            continue
        if model_id not in seen:
            seen.add(model_id)
            model_ids.append(model_id)
    return model_ids


def github_copilot_model_list(
    *,
    base_url: str,
    api_key: str,
    oauth_access_token: str,
    timeout: float,
    headers: dict[str, str] | None = None,
) -> list[str]:
    endpoint_base = base_url.rstrip("/") if base_url else "https://api.githubcopilot.com"
    copilot_token = fetch_github_copilot_token(
        oauth_access_token,
        timeout=timeout,
        headers=headers or {},
    )
    return fetch_model_list(
        f"{endpoint_base}/models",
        github_copilot_headers(copilot_token, headers=headers or {}),
        timeout=timeout,
    )


def fetch_github_copilot_token(
    github_token: str,
    *,
    timeout: float,
    headers: dict[str, str] | None = None,
) -> str:
    cache_key = github_copilot_token_cache_key(github_token)
    cached = _github_copilot_token_cache.get(cache_key)
    now = time.time()
    if cached and cached[1] > now + 30:
        return cached[0]

    endpoint = "https://api.github.com/copilot_internal/v2/token"
    request_headers = merge_extra_headers(
        {
            "Accept": "application/json",
            "Authorization": f"token {github_token}",
            "Content-Type": "application/json",
            "Editor-Version": "vscode/1.104.3",
            "Editor-Plugin-Version": "copilot-chat/0.26.7",
            "User-Agent": "GitHubCopilotChat/0.26.7",
            "X-GitHub-Api-Version": "2025-04-01",
            "X-VSCode-User-Agent-Library-Version": "electron-fetch",
        },
        headers or {},
    )
    request = urllib.request.Request(endpoint, headers=request_headers, method="GET")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            response_body = response.read()
    except urllib.error.HTTPError as exc:
        raise RuntimeError(upstream_http_error_message(endpoint, exc)) from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(str(exc.reason)) from exc

    try:
        body = json.loads(response_body.decode("utf-8"))
        token = str(body["token"]).strip()
    except (KeyError, TypeError, ValueError) as exc:
        raise RuntimeError("GitHub did not return a Copilot service token") from exc
    if not token:
        raise RuntimeError("GitHub did not return a Copilot service token")
    _github_copilot_token_cache[cache_key] = (token, github_copilot_token_expiry(body, now=now))
    return token


def github_copilot_token_cache_key(github_token: str) -> str:
    return hashlib.sha256(github_token.encode("utf-8")).hexdigest()


def github_copilot_token_expiry(body: dict[str, object], *, now: float) -> float:
    expires_at = body.get("expires_at")
    if isinstance(expires_at, int | float):
        return float(expires_at)
    return now + 300


def github_copilot_headers(copilot_token: str, *, headers: dict[str, str] | None = None) -> dict[str, str]:
    return merge_extra_headers(
        {
            "Accept": "application/json",
            "Authorization": f"Bearer {copilot_token}",
            "Content-Type": "application/json",
            "Copilot-Integration-Id": "vscode-chat",
            "Editor-Version": "vscode/1.104.3",
            "Editor-Plugin-Version": "copilot-chat/0.26.7",
            "OpenAI-Intent": "conversation-panel",
            "User-Agent": "GitHubCopilotChat/0.26.7",
            "X-GitHub-Api-Version": "2025-04-01",
            "X-Initiator": "user",
            "X-Request-Id": str(uuid.uuid4()),
            "X-VSCode-User-Agent-Library-Version": "electron-fetch",
        },
        headers or {},
    )


def fetch_model_list(endpoint: str, headers: dict[str, str], *, timeout: float) -> list[str]:
    request = urllib.request.Request(endpoint, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            response_body = response.read()
    except urllib.error.HTTPError as exc:
        raise RuntimeError(upstream_http_error_message(endpoint, exc)) from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(str(exc.reason)) from exc

    return extract_model_ids(response_body)


def extract_model_ids(response_body: bytes) -> list[str]:
    try:
        body = json.loads(response_body.decode("utf-8"))
    except ValueError as exc:
        raise RuntimeError("upstream response did not include a model list") from exc

    candidates: list[Any]
    if isinstance(body, list):
        candidates = body
    elif isinstance(body, dict) and isinstance(body.get("data"), list):
        candidates = body["data"]
    elif isinstance(body, dict) and isinstance(body.get("models"), list):
        candidates = body["models"]
    else:
        raise RuntimeError("upstream response did not include a model list")

    model_ids: list[str] = []
    seen: set[str] = set()
    for item in candidates:
        model_id = ""
        if isinstance(item, str):
            model_id = item
        elif isinstance(item, dict):
            value = item.get("id") or item.get("name") or item.get("model")
            if isinstance(value, str):
                model_id = value
        model_id = model_id.strip()
        if model_id and model_id not in seen:
            seen.add(model_id)
            model_ids.append(model_id)

    if not model_ids:
        raise RuntimeError("upstream response did not include model ids")
    return model_ids


def extract_chat_text(response_body: bytes) -> str:
    decoded = response_body.decode("utf-8", errors="replace")
    if decoded.lstrip().startswith(("event:", "data:")):
        return extract_streamed_chat_text(decoded)

    try:
        body = json.loads(decoded)
        if isinstance(body.get("output_text"), str):
            text = body["output_text"]
        elif "choices" in body:
            text = body["choices"][0]["message"]["content"]
        elif "content" in body:
            content = body["content"]
            if isinstance(content, str):
                text = content
            else:
                text = "\n".join(part.get("text", "") for part in content if part.get("type") == "text")
        else:
            raise KeyError("output_text")
    except (KeyError, IndexError, TypeError, ValueError) as exc:
        raise RuntimeError("upstream response did not include message content") from exc

    cleaned = str(text).strip()
    if not cleaned:
        raise RuntimeError("upstream returned empty content")
    return cleaned


def extract_streamed_chat_text(response_text: str) -> str:
    deltas: list[str] = []
    final_text = ""
    for line in response_text.splitlines():
        stripped = line.strip()
        if not stripped.startswith("data:"):
            continue
        payload = stripped.removeprefix("data:").strip()
        if not payload or payload == "[DONE]":
            continue
        try:
            body = json.loads(payload)
        except ValueError:
            continue

        event_type = body.get("type")
        if event_type == "response.output_text.delta":
            delta = body.get("delta")
            if isinstance(delta, str):
                deltas.append(delta)
        elif event_type in {"response.output_text.done", "response.output_text.completed"}:
            text = body.get("text")
            if isinstance(text, str) and text.strip():
                final_text = text
        elif event_type == "response.completed":
            response = body.get("response")
            extracted = extract_response_output_text(response)
            if extracted:
                final_text = extracted

    text = final_text or "".join(deltas)
    cleaned = text.strip()
    if not cleaned:
        raise RuntimeError("upstream response did not include message content")
    return cleaned


def extract_response_output_text(response: object) -> str:
    if not isinstance(response, dict):
        return ""
    output = response.get("output")
    if not isinstance(output, list):
        return ""

    parts: list[str] = []
    for item in output:
        if not isinstance(item, dict):
            continue
        content = item.get("content")
        if not isinstance(content, list):
            continue
        for part in content:
            if not isinstance(part, dict):
                continue
            text = part.get("text")
            if isinstance(text, str) and part.get("type") in {"output_text", "text"}:
                parts.append(text)
    return "".join(parts).strip()


def desktop_app_path() -> Path:
    configured_path = os.environ.get("OMNIVOICE_DESKTOP_APP_PATH")
    if configured_path:
        return Path(configured_path).expanduser()

    candidates = [
        DEFAULT_DESKTOP_APP_PATH,
        Path("/Applications/OmniSpeak.app"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return DEFAULT_DESKTOP_APP_PATH


def launch_desktop_app(app_path: Path) -> None:
    subprocess.Popen(["open", str(app_path)])


def _should_record_request(path: str) -> bool:
    skipped_prefixes = (
        "/assets/",
        "/api/status",
        "/api/theme",
        "/api/events",
        "/api/transcripts",
        "/api/desktop-app",
        "/health",
        "/favicon.ico",
    )
    return not any(path.startswith(prefix) for prefix in skipped_prefixes)
