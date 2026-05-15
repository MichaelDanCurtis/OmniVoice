from __future__ import annotations

import os
from pathlib import Path

from omnivoice_engine.schemas import ProviderInfo

from .base import ASRProvider


class ParakeetSherpaProvider(ASRProvider):
    id = "parakeet-tdt"
    label = "Parakeet TDT"
    model_layouts = [
        ("encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"),
        ("encoder.onnx", "decoder.onnx", "joiner.onnx", "tokens.txt"),
    ]

    def __init__(self, model_dir: str | None = None) -> None:
        configured = model_dir or os.environ.get("OMNIVOICE_PARAKEET_MODEL_DIR")
        self.model_dir = Path(configured or "models/parakeet-tdt").expanduser()
        self._recognizer = None

    def info(self) -> ProviderInfo:
        missing = [path.name for path in self._required_paths() if not path.exists()]
        if missing:
            return ProviderInfo(
                id=self.id,
                label=self.label,
                available=False,
                reason=f"model files not found in {self.model_dir}: {', '.join(missing)}",
            )

        try:
            import sherpa_onnx  # noqa: F401
        except Exception as exc:
            return ProviderInfo(
                id=self.id,
                label=self.label,
                available=False,
                reason=f"sherpa-onnx import failed: {exc}",
            )

        return ProviderInfo(id=self.id, label=self.label, available=True)

    def transcribe(self, audio_bytes: bytes) -> str:
        info = self.info()
        if not info.available:
            raise RuntimeError(info.reason)

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
        recognizer = self._get_recognizer()
        stream = recognizer.create_stream()
        stream.accept_waveform(16000, normalized)
        recognizer.decode_stream(stream)
        return stream.result.text.strip()

    def _get_recognizer(self):
        import sherpa_onnx

        if self._recognizer is None:
            model_files = self._model_files()
            self._recognizer = sherpa_onnx.OfflineRecognizer.from_transducer(
                encoder=str(model_files["encoder"]),
                decoder=str(model_files["decoder"]),
                joiner=str(model_files["joiner"]),
                tokens=str(model_files["tokens"]),
                num_threads=4,
                sample_rate=16000,
                feature_dim=128,
                decoding_method="greedy_search",
            )
        return self._recognizer

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
