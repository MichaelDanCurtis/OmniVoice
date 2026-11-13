from __future__ import annotations

import importlib.util
import os
import platform
import tempfile
import wave
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

        with tempfile.NamedTemporaryFile(suffix=".wav") as wav_file:
            wav_file.write(audio_bytes)
            wav_file.flush()
            return self._transcribe_file(wav_file.name)

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

    def _transcribe_file(self, audio_path: str) -> str:
        return self._transcribe_file_aligned(audio_path).text

    def _transcribe_file_aligned(self, audio_path: str) -> ASRTranscript:
        model = self._get_model()
        mel = self._audio_features(audio_path, model.preprocessor_config)
        if mel is None:
            return ASRTranscript(text="")
        result = model.generate(mel)[0]
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

    def _audio_features(self, audio_path: str, config):
        # Parakeet's file transcription helper shells out to ffmpeg. Decode the
        # app's audio with the bundled Python libraries instead, including when
        # Finder launches the app with no developer tools on PATH.
        import librosa
        import mlx.core as mx
        import soundfile as sf
        from parakeet_mlx.audio import get_logmel

        samples, sample_rate = sf.read(audio_path, dtype="float32", always_2d=True)
        samples = samples.mean(axis=1)
        if sample_rate != config.sample_rate and samples.size:
            samples = librosa.resample(samples, orig_sr=sample_rate, target_sr=config.sample_rate)
        if samples.size < config.hop_length:
            return None
        return get_logmel(mx.array(samples), config)

    def _get_model(self):
        if self._model is None:
            from parakeet_mlx import from_pretrained

            self._model = from_pretrained(str(self.model_dir))
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
