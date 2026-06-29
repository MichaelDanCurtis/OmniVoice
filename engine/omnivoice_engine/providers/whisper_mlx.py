from __future__ import annotations

import importlib.util
import os
import platform
import tempfile
import wave
from pathlib import Path
from typing import Any

from omnivoice_engine.paths import default_model_root
from omnivoice_engine.schemas import ProviderInfo

from .base import ASRProvider, ASRSentence, ASRTranscript


class WhisperMLXProvider(ASRProvider):
    id = "whisper-large-v3-turbo-mlx-6bit"
    label = "Whisper Large v3 Turbo MLX 6-bit"
    required_files = ("config.json", "model.safetensors", "tokenizer.json", "preprocessor_config.json")

    def __init__(self, model_dir: str | None = None) -> None:
        configured = model_dir or os.environ.get("OMNIVOICE_WHISPER_MLX_MODEL_DIR")
        self.model_dir = Path(configured).expanduser() if configured else default_model_root(__file__) / self.id
        self._model = None

    def info(self) -> ProviderInfo:
        if not self._is_apple_silicon_macos():
            return ProviderInfo(
                id=self.id,
                label=self.label,
                available=False,
                reason="Whisper MLX requires Apple Silicon macOS",
            )

        missing = [filename for filename in self.required_files if not (self.model_dir / filename).exists()]
        if missing:
            return ProviderInfo(
                id=self.id,
                label=self.label,
                available=False,
                reason=f"model files not found in {self.model_dir}: {', '.join(missing)}",
            )

        if importlib.util.find_spec("mlx_audio") is None:
            return ProviderInfo(
                id=self.id,
                label=self.label,
                available=False,
                reason="mlx-audio runtime is not installed",
            )

        return ProviderInfo(id=self.id, label=self.label, available=True)

    def transcribe(self, audio_bytes: bytes) -> str:
        info = self.info()
        if not info.available:
            raise RuntimeError(info.reason)
        if not audio_bytes:
            return ""

        with tempfile.NamedTemporaryFile(suffix=".wav") as wav_file:
            wav_file.write(audio_bytes)
            wav_file.flush()
            return self._transcribe_file_aligned(wav_file.name).text

    def transcribe_pcm_float32(self, pcm_bytes: bytes, sample_rate: int) -> str:
        return self.transcribe_aligned_pcm_float32(pcm_bytes, sample_rate).text

    def transcribe_aligned_pcm_float32(self, pcm_bytes: bytes, sample_rate: int) -> ASRTranscript:
        info = self.info()
        if not info.available:
            raise RuntimeError(info.reason)
        if not pcm_bytes:
            return ASRTranscript(text="")

        with tempfile.NamedTemporaryFile(suffix=".wav") as wav_file:
            self._write_pcm_float32_wav(wav_file.name, pcm_bytes, sample_rate)
            return self._transcribe_file_aligned(wav_file.name)

    def _transcribe_file_aligned(self, audio_path: str) -> ASRTranscript:
        from mlx_audio.stt.generate import generate_transcription

        with tempfile.TemporaryDirectory() as output_dir:
            result = generate_transcription(
                model=self._get_model(),
                audio=audio_path,
                output_path=str(Path(output_dir) / "whisper"),
                format="txt",
                verbose=False,
                task="transcribe",
            )

        text = str(getattr(result, "text", "") or "").strip()
        raw_segments = getattr(result, "segments", None) or []
        sentences = tuple(self._sentence_from_segment(segment) for segment in raw_segments)
        if not text:
            text = " ".join(sentence.text for sentence in sentences).strip()
        return ASRTranscript(text=text, sentences=sentences)

    def _get_model(self):
        if self._model is None:
            from mlx_audio.stt.utils import load_model

            self._model = load_model(str(self.model_dir), lazy=False, strict=False)
        return self._model

    def _is_apple_silicon_macos(self) -> bool:
        return platform.system() == "Darwin" and platform.machine() in {"arm64", "aarch64"}

    def _write_pcm_float32_wav(self, path: str, pcm_bytes: bytes, sample_rate: int) -> None:
        import numpy as np

        samples = np.frombuffer(pcm_bytes, dtype=np.float32)
        if samples.size == 0:
            with wave.open(path, "wb") as wav:
                wav.setnchannels(1)
                wav.setsampwidth(2)
                wav.setframerate(sample_rate)
                wav.writeframes(b"")
            return

        clipped = np.clip(samples, -1.0, 1.0)
        int16_samples = (clipped * 32767.0).astype(np.int16)
        with wave.open(path, "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(sample_rate)
            wav.writeframes(int16_samples.tobytes())

    def _sentence_from_segment(self, segment: object) -> ASRSentence:
        return ASRSentence(
            text=str(self._value(segment, "text") or "").strip(),
            start_ms=self._seconds_to_ms(self._value(segment, "start", "start_time")),
            end_ms=self._seconds_to_ms(self._value(segment, "end", "end_time")),
            confidence=self._optional_float(self._value(segment, "confidence", "avg_logprob")),
        )

    def _value(self, source: object, *keys: str) -> Any:
        for key in keys:
            if isinstance(source, dict) and key in source:
                return source[key]
            value = getattr(source, key, None)
            if value is not None:
                return value
        return None

    def _seconds_to_ms(self, value: object) -> int | None:
        try:
            seconds = float(value)
        except (TypeError, ValueError):
            return None
        return int(round(seconds * 1_000))

    def _optional_float(self, value: object) -> float | None:
        try:
            return float(value)
        except (TypeError, ValueError):
            return None
