import asyncio
import json
import os
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path

from fastapi import BackgroundTasks, FastAPI, HTTPException, Query, Request, Response, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles

from .cleanup import clean_transcript
from .model_manager import ModelManager
from .providers.registry import ProviderRegistry
from .runtime_store import RuntimeStore
from .schemas import (
    AIHandoffRequest,
    AIHandoffResponse,
    CleanupRequest,
    CleanupResponse,
    ConversationAssistCardCreateRequest,
    ConversationAssistCardRecord,
    ConversationDetail,
    ConversationSegmentCreateRequest,
    ConversationSegmentRecord,
    ConversationSessionCreateRequest,
    ConversationSessionRecord,
    DesktopAppLaunchResponse,
    EngineEvent,
    EngineStatus,
    ModelDownloadStatus,
    ModelStatus,
    ModelUpdateInfo,
    ProviderInfo,
    ThemePayload,
    TranscriptRecord,
    TranscribeResponse,
)

app = FastAPI(title="OmniVoice Local Engine")
registry = ProviderRegistry()
model_manager = ModelManager()
runtime_store = RuntimeStore()
STARTED_MONOTONIC = time.monotonic()
STATIC_DIR = Path(__file__).parent / "static"
REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DESKTOP_APP_PATH = REPO_ROOT / "dist" / "OmniVoice.app"
DEFAULT_THEME_CSS_VARIABLES = {
    "--ov-accent": "#38BDF8",
    "--ov-accent-secondary": "#818CF8",
    "--ov-bg": "#06121C",
    "--ov-surface": "rgba(6, 18, 28, 0.36)",
    "--ov-surface-strong": "rgba(6, 18, 28, 0.54)",
    "--ov-text": "#F8FAFC",
    "--ov-muted": "rgba(248, 250, 252, 0.64)",
    "--ov-border": "rgba(56, 189, 248, 0.26)",
    "--ov-glow": "rgba(56, 189, 248, 0.34)",
    "--ov-caption-bg": "rgba(6, 18, 28, 0.14)",
}
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


@app.get("/models", response_model=list[ModelStatus])
def models() -> list[ModelStatus]:
    return model_manager.list_statuses()


@app.get("/models/{provider_id}/update", response_model=ModelUpdateInfo)
def model_update(provider_id: str) -> ModelUpdateInfo:
    try:
        return model_manager.check_update(provider_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"unknown model provider: {provider_id}") from exc
    except Exception as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@app.post("/models/{provider_id}/download", response_model=ModelDownloadStatus)
def model_download(provider_id: str, background_tasks: BackgroundTasks) -> ModelDownloadStatus:
    try:
        state = model_manager.start_download(provider_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"unknown model provider: {provider_id}") from exc

    runtime_store.record_event(
        "model.download.queued",
        f"Queued model download for {provider_id}",
        detail={"provider_id": provider_id, "state": state.state},
    )
    background_tasks.add_task(_download_model, provider_id)
    return state


@app.get("/models/{provider_id}/download", response_model=ModelDownloadStatus)
def model_download_status(provider_id: str) -> ModelDownloadStatus:
    try:
        return model_manager.download_state(provider_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"unknown model provider: {provider_id}") from exc


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
    if not base_url or not model:
        raise HTTPException(status_code=400, detail="AI endpoint and model are required")

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
        text = openai_compatible_chat_completion(
            base_url=base_url,
            api_key=request.api_key.strip(),
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
            "prompt_length": len(prompt),
            "context_length": len(context),
        },
    )
    return AIHandoffResponse(text=text, provider=provider, model=model)


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


@app.websocket("/stream")
async def stream(websocket: WebSocket, provider: str = "fake", sample_rate: int = 16000) -> None:
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
                    },
                )
                runtime_store.record_stream_completed(provider=provider)
                await websocket.send_json({"type": "final", "text": final_text})
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
                    await websocket.send_json({"type": "partial", "text": partial})
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
        detail={"session_id": session.id, "capture_mode": session.capture_mode},
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


@app.post("/api/conversations/{session_id}/segments", response_model=ConversationSegmentRecord)
def add_conversation_segment(session_id: str, request: ConversationSegmentCreateRequest) -> ConversationSegmentRecord:
    if runtime_store.conversation_session(session_id) is None:
        raise HTTPException(status_code=404, detail=f"conversation not found: {session_id}")
    return runtime_store.add_conversation_segment(
        session_id=session_id,
        speaker_id=request.speaker_id,
        speaker_display_name=request.speaker_display_name,
        start_ms=request.start_ms,
        end_ms=request.end_ms,
        text=request.text,
        state=request.state,
        confidence=request.confidence,
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


def _download_model(provider_id: str) -> None:
    try:
        state = model_manager.download(provider_id)
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


def _ai_handoff_user_content(*, prompt: str, context: str) -> str:
    if context:
        return f"Foreground context:\n{context}\n\nUser request:\n{prompt}"
    return prompt


def openai_compatible_chat_completion(
    *,
    base_url: str,
    api_key: str,
    model: str,
    messages: list[dict[str, str]],
    timeout: float,
) -> str:
    endpoint = f"{base_url.rstrip('/')}/chat/completions"
    payload = json.dumps(
        {
            "model": model,
            "messages": messages,
            "temperature": 0.3,
        }
    ).encode("utf-8")
    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"

    request = urllib.request.Request(endpoint, data=payload, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            response_body = response.read()
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace").strip()
        message = f"upstream returned {exc.code}"
        if detail:
            message = f"{message}: {detail}"
        raise RuntimeError(message) from exc
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


def desktop_app_path() -> Path:
    configured_path = os.environ.get("OMNIVOICE_DESKTOP_APP_PATH")
    if configured_path:
        return Path(configured_path).expanduser()

    candidates = [
        DEFAULT_DESKTOP_APP_PATH,
        Path("/Applications/OmniVoice.app"),
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
