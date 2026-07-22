from __future__ import annotations

import os
from pathlib import Path

from omnivoice_engine.paths import default_model_root
from omnivoice_engine.schemas import ProviderInfo

from .base import ASRProvider
from .device import available_onnx_providers, requested_device_from_env, resolve_device
from .sherpa_runtime import build_recognizer


class ParakeetSherpaProvider(ASRProvider):
    id = "parakeet-tdt"
    label = "Parakeet TDT"
    model_layouts = [
        ("encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"),
        ("encoder.onnx", "decoder.onnx", "joiner.onnx", "tokens.txt"),
    ]

    def __init__(
        self,
        model_dir: str | None = None,
        device: str | None = None,
        available_providers: list[str] | None = None,
    ) -> None:
        configured = model_dir or os.environ.get("OMNIVOICE_PARAKEET_MODEL_DIR")
        self.model_dir = Path(configured).expanduser() if configured else default_model_root(__file__) / "parakeet-tdt"
        self._recognizer = None
        requested = device if device is not None else requested_device_from_env(os.environ)
        detected = available_providers if available_providers is not None else available_onnx_providers()
        # The device we intend to use; `device` becomes the *actual* one after the
        # recognizer is built (a failed CUDA build silently degrades to CPU).
        self._device = resolve_device(requested, detected)
        self._fallback_reason: str | None = None

    @property
    def device(self) -> str:
        return self._device

    @property
    def fallback_reason(self) -> str | None:
        return self._fallback_reason

    def info(self) -> ProviderInfo:
        missing = [path.name for path in self._required_paths() if not path.exists()]
        if missing:
            return ProviderInfo(
                id=self.id,
                label=self.label,
                available=False,
                reason=f"model files not found in {self.model_dir}: {', '.join(missing)}",
                device=self._device,
            )

        import_error = self._sherpa_import_error()
        if import_error:
            return ProviderInfo(
                id=self.id,
                label=self.label,
                available=False,
                reason=f"sherpa-onnx import failed: {import_error}",
                device=self._device,
            )

        return ProviderInfo(
            id=self.id,
            label=self.label,
            available=True,
            reason=self._fallback_reason,
            device=self._device,
        )

    def _sherpa_import_error(self) -> str | None:
        try:
            import sherpa_onnx  # noqa: F401
        except Exception as exc:
            return str(exc)
        return None

    def transcribe(self, audio_bytes: bytes) -> str:
        info = self.info()
        if not info.available:
            raise RuntimeError(info.reason)
        if not audio_bytes:
            return ""

        import tempfile

        import soundfile as sf

        with tempfile.NamedTemporaryFile(suffix=".wav") as wav_file:
            wav_file.write(audio_bytes)
            wav_file.flush()
            samples, sample_rate = sf.read(wav_file.name, dtype="float32")

        return self._decode_samples(samples, sample_rate)

    def transcribe_pcm_float32(self, pcm_bytes: bytes, sample_rate: int) -> str:
        info = self.info()
        if not info.available:
            raise RuntimeError(info.reason)

        import numpy as np

        samples = np.frombuffer(pcm_bytes, dtype=np.float32)
        return self._decode_samples(samples, sample_rate)

    def _decode_samples(self, samples, sample_rate: int) -> str:
        normalized = self._normalize_audio(samples, sample_rate)
        if normalized.size < 8000:
            return ""

        recognizer = self._get_recognizer()
        stream = recognizer.create_stream()
        stream.accept_waveform(16000, normalized)
        recognizer.decode_stream(stream)
        return stream.result.text.strip()

    def _get_recognizer(self):
        if self._recognizer is None:
            built = build_recognizer(self._build_recognizer, self._device)
            self._recognizer = built.recognizer
            self._device = built.device
            self._fallback_reason = built.fallback_reason
        return self._recognizer

    def _build_recognizer(self, execution_provider: str):
        import sherpa_onnx

        model_files = self._model_files()
        return sherpa_onnx.OfflineRecognizer.from_transducer(
            encoder=str(model_files["encoder"]),
            decoder=str(model_files["decoder"]),
            joiner=str(model_files["joiner"]),
            tokens=str(model_files["tokens"]),
            num_threads=4,
            sample_rate=16000,
            feature_dim=80,
            decoding_method="greedy_search",
            model_type="nemo_transducer",
            provider=execution_provider,
        )

    def _normalize_audio(self, samples, sample_rate: int):
        import numpy as np

        normalized = np.asarray(samples, dtype=np.float32)
        if normalized.ndim > 1:
            normalized = normalized.mean(axis=1)

        if sample_rate == 16000 or normalized.size == 0:
            return normalized

        duration = normalized.size / float(sample_rate)
        target_size = max(1, int(duration * 16000))
        source_positions = np.linspace(0.0, duration, num=normalized.size, endpoint=False)
        target_positions = np.linspace(0.0, duration, num=target_size, endpoint=False)
        return np.interp(target_positions, source_positions, normalized).astype(np.float32)

    def _required_paths(self) -> list[Path]:
        for layout in self.model_layouts:
            paths = [self.model_dir / filename for filename in layout]
            if all(path.exists() for path in paths):
                return paths

        return [self.model_dir / filename for filename in self.model_layouts[0]]

    def _model_files(self) -> dict[str, Path]:
        encoder, decoder, joiner, tokens = [path for path in self._required_paths()]
        return {
            "encoder": encoder,
            "decoder": decoder,
            "joiner": joiner,
            "tokens": tokens,
        }
