import asyncio
import time

from fastapi import BackgroundTasks, FastAPI, HTTPException, Query, Request, WebSocket, WebSocketDisconnect

from .cleanup import clean_transcript
from .model_manager import ModelManager
from .providers.registry import ProviderRegistry
from .schemas import (
    CleanupRequest,
    CleanupResponse,
    ModelDownloadStatus,
    ModelStatus,
    ModelUpdateInfo,
    ProviderInfo,
    TranscribeResponse,
)

app = FastAPI(title="OmniVoice Local Engine")
registry = ProviderRegistry()
model_manager = ModelManager()


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


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

    background_tasks.add_task(_download_model, provider_id)
    return state


@app.get("/models/{provider_id}/download", response_model=ModelDownloadStatus)
def model_download_status(provider_id: str) -> ModelDownloadStatus:
    try:
        return model_manager.download_state(provider_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"unknown model provider: {provider_id}") from exc


@app.post("/cleanup", response_model=CleanupResponse)
def cleanup(request: CleanupRequest) -> CleanupResponse:
    return clean_transcript(request)


@app.post("/transcribe", response_model=TranscribeResponse)
async def transcribe(request: Request, provider: str = Query(default="fake")) -> TranscribeResponse:
    try:
        asr = registry.get(provider)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"unknown provider: {provider}") from exc

    info = asr.info()
    if not info.available:
        raise HTTPException(status_code=503, detail=info.reason or f"provider unavailable: {provider}")

    audio_bytes = await request.body()
    return TranscribeResponse(text=asr.transcribe(audio_bytes), provider=provider)


@app.websocket("/stream")
async def stream(websocket: WebSocket, provider: str = "fake", sample_rate: int = 16000) -> None:
    await websocket.accept()
    try:
        asr = registry.get(provider)
    except KeyError:
        await websocket.send_json({"type": "error", "text": f"unknown provider: {provider}"})
        await websocket.close()
        return

    info = asr.info()
    if not info.available:
        await websocket.send_json({"type": "error", "text": info.reason or f"provider unavailable: {provider}"})
        await websocket.close()
        return

    chunks: list[bytes] = []
    last_decode_size = 0
    last_decode_time = 0.0
    partial_decode_bytes = 4096
    await websocket.send_json({"type": "partial", "text": "listening"})

    try:
        while True:
            message = await websocket.receive()
            text_message = message.get("text")
            bytes_message = message.get("bytes")

            if text_message == "__finish__":
                combined = b"".join(chunks)
                final_text = await asyncio.to_thread(asr.transcribe_pcm_float32, combined, sample_rate)
                await websocket.send_json({"type": "final", "text": final_text})
                await websocket.close()
                return

            if bytes_message:
                chunks.append(bytes_message)
                combined = b"".join(chunks)
                now = time.monotonic()
                enough_new_audio = len(combined) - last_decode_size >= partial_decode_bytes
                enough_time = now - last_decode_time >= 1.0
                if enough_new_audio and enough_time:
                    partial = await asyncio.to_thread(asr.transcribe_pcm_float32, combined, sample_rate)
                    await websocket.send_json({"type": "partial", "text": partial})
                    last_decode_size = len(combined)
                    last_decode_time = now
    except WebSocketDisconnect:
        return


def _download_model(provider_id: str) -> None:
    try:
        model_manager.download(provider_id)
    except Exception:
        return
