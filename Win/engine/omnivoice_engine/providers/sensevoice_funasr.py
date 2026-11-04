from __future__ import annotations

import importlib.util
import os
import re
import struct
import sys
import tempfile
import threading
import wave
from pathlib import Path
from typing import Any

from omnivoice_engine.paths import default_model_root
from omnivoice_engine.schemas import ProviderInfo

from .base import ASRProvider


class SenseVoiceFunASRProvider(ASRProvider):
    id = "sensevoice-small-funasr"
    label = "SenseVoice Small FunASR"
    required_files = ("config.yaml", "model.pt", "am.mvn", "chn_jpn_yue_eng_ko_spectok.bpe.model")

    def __init__(self, model_dir: str | None = None) -> None:
        configured = model_dir or os.environ.get("OMNIVOICE_SENSEVOICE_MODEL_DIR")
        self.model_dir = Path(configured).expanduser() if configured else default_model_root(__file__) / self.id
        self._model = None
        self._model_lock = threading.Lock()

    def info(self) -> ProviderInfo:
        missing = [filename for filename in self.required_files if not (self.model_dir / filename).exists()]
        if missing:
            return ProviderInfo(
                id=self.id,
                label=self.label,
                available=False,
                reason=f"model files not found in {self.model_dir}: {', '.join(missing)}",
            )
        if not self._runtime_available("funasr"):
            return ProviderInfo(id=self.id, label=self.label, available=False, reason="FunASR runtime is not installed")
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
        info = self.info()
        if not info.available:
            raise RuntimeError(info.reason)
        if not pcm_bytes:
            return ""

        with tempfile.NamedTemporaryFile(suffix=".wav") as wav_file:
            self._write_pcm_float32_wav(wav_file.name, pcm_bytes, sample_rate)
            return self._transcribe_file(wav_file.name)

    def _transcribe_file(self, audio_path: str) -> str:
        result = self._get_model().generate(
            input=audio_path,
            cache={},
            language="auto",
            use_itn=True,
            batch_size_s=60,
        )
        return self._extract_text(result)

    def _get_model(self):
        if self._model is None:
            with self._model_lock:
                if self._model is None:
                    from funasr import AutoModel

                    self._model = AutoModel(
                        model=str(self.model_dir),
                        trust_remote_code=True,
                        vad_model=None,
                        punc_model=None,
                        device="cpu",
                    )
        return self._model

    @staticmethod
    def _runtime_available(module_name: str) -> bool:
        if module_name in sys.modules:
            return True
        try:
            return importlib.util.find_spec(module_name) is not None
        except (ModuleNotFoundError, ValueError):
            return False

    @staticmethod
    def _write_pcm_float32_wav(path: str, pcm_bytes: bytes, sample_rate: int) -> None:
        sample_count = len(pcm_bytes) // 4
        pcm16 = bytearray(sample_count * 2)
        for index in range(sample_count):
            sample = struct.unpack_from("<f", pcm_bytes, index * 4)[0]
            clipped = min(max(sample, -1.0), 1.0)
            value = int(clipped * 32767.0) if clipped >= 0 else int(clipped * 32768.0)
            struct.pack_into("<h", pcm16, index * 2, value)

        with wave.open(path, "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(sample_rate)
            wav.writeframes(bytes(pcm16))

    def _extract_text(self, result: object) -> str:
        text = self._raw_text(result)
        try:
            from funasr.utils.postprocess_utils import rich_transcription_postprocess

            processed = str(rich_transcription_postprocess(text))
            return re.sub(r"<\|[^|]+?\|>", "", processed).strip()
        except Exception:
            return re.sub(r"<\|[^|]+?\|>", "", text).strip()

    def _raw_text(self, result: object) -> str:
        if isinstance(result, str):
            return result
        if isinstance(result, dict):
            return str(result.get("text") or "")
        if isinstance(result, list):
            return " ".join(self._raw_text(item) for item in result).strip()
        value: Any = getattr(result, "text", "")
        return str(value or "")
