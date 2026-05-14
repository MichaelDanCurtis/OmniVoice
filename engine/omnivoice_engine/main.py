import asyncio
import time

from fastapi import FastAPI, HTTPException, Query, Request, WebSocket, WebSocketDisconnect

from .cleanup import clean_transcript
from .providers.registry import ProviderRegistry
from .schemas import CleanupRequest, CleanupResponse, ProviderInfo, TranscribeResponse

app = FastAPI(title="OmniVoice Local Engine")
registry = ProviderRegistry()


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/providers", response_model=list[ProviderInfo])
def providers() -> list[ProviderInfo]:
    return registry.list_providers()


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
