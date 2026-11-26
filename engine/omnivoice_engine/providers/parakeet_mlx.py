from __future__ import annotations

import importlib.util
import io
import math
import os
import platform
from pathlib import Path

from omnivoice_engine.paths import default_model_root
from omnivoice_engine.schemas import ProviderInfo

from .base import ASRProvider, ASRSentence, ASRToken, ASRTranscript


class ParakeetMLXProvider(ASRProvider):
    id = "parakeet-tdt-mlx"
    label = "Parakeet TDT MLX"
    required_files = ("config.json", "model.safetensors")

    def __init__(self, model_dir: str | None = None) -> None:
        configured = model_dir or os.environ.get("OMNIVOICE_PARAKEET_MLX_MODEL_DIR")
        self.model_dir = Path(configured).expanduser() if configured else default_model_root(__file__) / self.id
        self._model = None

    def info(self) -> ProviderInfo:
        if not self._is_apple_silicon_macos():
            return ProviderInfo(
                id=self.id,
                label=self.label,
                available=False,
                reason="Parakeet MLX requires Apple Silicon macOS",
            )

        missing = [filename for filename in self.required_files if not (self.model_dir / filename).exists()]
        if missing:
            return ProviderInfo(
                id=self.id,
                label=self.label,
                available=False,
                reason=f"model files not found in {self.model_dir}: {', '.join(missing)}",
            )

        if importlib.util.find_spec("parakeet_mlx") is None:
            return ProviderInfo(
                id=self.id,
                label=self.label,
                available=False,
                reason="parakeet-mlx runtime is not installed",
            )

        return ProviderInfo(id=self.id, label=self.label, available=True)

    def transcribe(self, audio_bytes: bytes) -> str:
        info = self.info()
        if not info.available:
            raise RuntimeError(info.reason)
        if not audio_bytes:
            return ""

        import soundfile as sf

        # Parakeet's file API shells out to ffmpeg, which is not installed on
        # a fresh Mac. Decode WAV bytes directly in memory with no temp file.
        samples, sample_rate = sf.read(io.BytesIO(audio_bytes), dtype="float32", always_2d=True)
        return self._transcribe_samples_aligned(samples.mean(axis=1), int(sample_rate)).text

    def transcribe_pcm_float32(self, pcm_bytes: bytes, sample_rate: int) -> str:
        return self.transcribe_aligned_pcm_float32(pcm_bytes, sample_rate).text

    def transcribe_aligned_pcm_float32(self, pcm_bytes: bytes, sample_rate: int) -> ASRTranscript:
        info = self.info()
        if not info.available:
            raise RuntimeError(info.reason)
        usable_bytes = (len(pcm_bytes) // 4) * 4
        if usable_bytes == 0:
            return ASRTranscript(text="")

        import numpy as np

        samples = np.frombuffer(pcm_bytes[:usable_bytes], dtype=np.float32)
        if samples.size == 0:
            return ASRTranscript(text="")
        clipped = np.clip(samples, -1.0, 1.0)
        return self._transcribe_samples_aligned(clipped, sample_rate)

    def _transcribe_file(self, audio_path: str) -> str:
        return self._transcribe_file_aligned(audio_path).text

    def _transcribe_file_aligned(self, audio_path: str) -> ASRTranscript:
        import soundfile as sf

        samples, sample_rate = sf.read(audio_path, dtype="float32", always_2d=True)
        return self._transcribe_samples_aligned(samples.mean(axis=1), int(sample_rate))

    def _transcribe_samples_aligned(self, samples, sample_rate: int) -> ASRTranscript:
        import mlx.core as mx
        import numpy as np
        from parakeet_mlx.audio import get_logmel
        from scipy.signal import resample_poly

        model = self._get_model()
        config = model.preprocessor_config
        if sample_rate != config.sample_rate:
            divisor = math.gcd(sample_rate, config.sample_rate)
            samples = resample_poly(samples, config.sample_rate // divisor, sample_rate // divisor)
        if samples.size < config.hop_length:
            return ASRTranscript(text="")
        audio = mx.array(np.asarray(samples, dtype=np.float32))
        result = model.generate(get_logmel(audio, config))[0]
        text = getattr(result, "text", str(result)).strip()
        raw_sentences = getattr(result, "sentences", None) or []

        sentences: list[ASRSentence] = []
        all_tokens: list[ASRToken] = []
        for raw_sentence in raw_sentences:
            sentence_tokens = tuple(self._aligned_token(token) for token in (getattr(raw_sentence, "tokens", None) or []))
            all_tokens.extend(sentence_tokens)
            sentences.append(
                ASRSentence(
                    text=str(getattr(raw_sentence, "text", "") or "".join(token.text for token in sentence_tokens)).strip(),
                    start_ms=self._seconds_to_ms(getattr(raw_sentence, "start", None)),
                    end_ms=self._seconds_to_ms(getattr(raw_sentence, "end", None)),
                    confidence=self._optional_float(getattr(raw_sentence, "confidence", None)),
                    tokens=sentence_tokens,
                )
            )

        return ASRTranscript(text=text, sentences=tuple(sentences), tokens=tuple(all_tokens))

    def _get_model(self):
        if self._model is None:
            from parakeet_mlx import from_pretrained

            self._model = from_pretrained(str(self.model_dir))
        return self._model

    def _is_apple_silicon_macos(self) -> bool:
        return platform.system() == "Darwin" and platform.machine() in {"arm64", "aarch64"}

    def _aligned_token(self, raw_token: object) -> ASRToken:
        start = self._seconds_to_ms(getattr(raw_token, "start", None))
        end = self._seconds_to_ms(getattr(raw_token, "end", None))
        if end is None:
            duration = self._seconds_to_ms(getattr(raw_token, "duration", None))
            if start is not None and duration is not None:
                end = start + duration
        return ASRToken(
            text=str(getattr(raw_token, "text", "") or ""),
            start_ms=start,
            end_ms=end,
            confidence=self._optional_float(getattr(raw_token, "confidence", None)),
        )

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
