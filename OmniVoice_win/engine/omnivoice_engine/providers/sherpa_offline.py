"""Shared behaviour for the offline sherpa-onnx ASR providers.

Subclasses supply an `id`, `label`, the on-disk `model_layouts` they accept, and
a `_build_recognizer(execution_provider)` that calls the right sherpa factory.
Everything else — device selection, GPU-to-CPU fallback, availability reporting,
resampling and decoding — is identical across models and lives here.
"""

from __future__ import annotations

import os
import sys
from abc import abstractmethod
from pathlib import Path

from omnivoice_engine.paths import default_model_root
from omnivoice_engine.schemas import ProviderInfo

from .base import ASRProvider
from .device import available_onnx_providers, requested_device_from_env, resolve_device
from .sherpa_runtime import build_recognizer

SAMPLE_RATE = 16000
MIN_SAMPLES = 8000


class SherpaOfflineProvider(ASRProvider):
    #: Accepted on-disk file layouts, most preferred first.
    model_layouts: list[tuple[str, ...]] = []
    #: Sub-directory under the model root when no explicit dir is configured.
    model_dir_name = ""
    #: Environment variable holding an explicit model directory.
    model_dir_env_var = ""

    def __init__(
        self,
        model_dir: str | None = None,
        device: str | None = None,
        available_providers: list[str] | None = None,
    ) -> None:
        configured = model_dir or (os.environ.get(self.model_dir_env_var) if self.model_dir_env_var else None)
        self.model_dir = (
            Path(configured).expanduser()
            if configured
            else default_model_root(self._module_anchor()) / self.model_dir_name
        )
        self._recognizer = None
        requested = device if device is not None else requested_device_from_env(os.environ)
        detected = available_providers if available_providers is not None else available_onnx_providers()
        self._device = resolve_device(requested, detected)
        self._fallback_reason: str | None = None

    def _module_anchor(self) -> str:
        """File of the concrete provider's module, used to locate the model root.

        Anchoring on the subclass (not this base) keeps each provider's model
        lookup relative to its own module, which is how the default model root
        has always been resolved.
        """
        module = sys.modules.get(type(self).__module__)
        return getattr(module, "__file__", None) or __file__

    @property
    def device(self) -> str:
        """Execution device in use — the actual one once the model is loaded."""
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

    @abstractmethod
    def _build_recognizer(self, execution_provider: str):
        """Calls the model-specific sherpa factory with `provider=execution_provider`."""
        raise NotImplementedError

    def _sherpa_import_error(self) -> str | None:
        try:
            import sherpa_onnx  # noqa: F401
        except Exception as exc:
            return str(exc)
        return None

    def _get_recognizer(self):
        if self._recognizer is None:
            built = build_recognizer(self._build_recognizer, self._device)
            self._recognizer = built.recognizer
            self._device = built.device
            self._fallback_reason = built.fallback_reason
        return self._recognizer

    def _decode_samples(self, samples, sample_rate: int) -> str:
        normalized = self._normalize_audio(samples, sample_rate)
        if normalized.size < MIN_SAMPLES:
            return ""

        recognizer = self._get_recognizer()
        stream = recognizer.create_stream()
        stream.accept_waveform(SAMPLE_RATE, normalized)
        recognizer.decode_stream(stream)
        return stream.result.text.strip()

    def _normalize_audio(self, samples, sample_rate: int):
        import numpy as np

        normalized = np.asarray(samples, dtype=np.float32)
        if normalized.ndim > 1:
            normalized = normalized.mean(axis=1)

        if sample_rate == SAMPLE_RATE or normalized.size == 0:
            return normalized

        duration = normalized.size / float(sample_rate)
        target_size = max(1, int(duration * SAMPLE_RATE))
        source_positions = np.linspace(0.0, duration, num=normalized.size, endpoint=False)
        target_positions = np.linspace(0.0, duration, num=target_size, endpoint=False)
        return np.interp(target_positions, source_positions, normalized).astype(np.float32)

    def _required_paths(self) -> list[Path]:
        for layout in self.model_layouts:
            paths = [self.model_dir / filename for filename in layout]
            if all(path.exists() for path in paths):
                return paths

        return [self.model_dir / filename for filename in self.model_layouts[0]]

    def _model_paths(self) -> list[Path]:
        return self._required_paths()
