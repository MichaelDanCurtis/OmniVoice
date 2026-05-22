from __future__ import annotations

import importlib.util
import os
import tempfile
import wave
from pathlib import Path

from omnivoice_engine.paths import default_model_root
from omnivoice_engine.schemas import ProviderInfo

from .base import ASRProvider, ASRTranscript


class CanaryQwenProvider(ASRProvider):
    id = "canary-qwen-2.5b"
    label = "Canary-Qwen-2.5B"
    required_files = ("config.json", "model.safetensors")

    def __init__(self, model_dir: str | None = None) -> None:
        configured = model_dir or os.environ.get("OMNIVOICE_CANARY_MODEL_DIR")
        self.model_dir = Path(configured).expanduser() if configured else default_model_root(__file__) / self.id
        self._model = None

    def info(self) -> ProviderInfo:
        missing = [filename for filename in self.required_files if not (self.model_dir / filename).exists()]
        if missing:
            return ProviderInfo(
                id=self.id,
                label=self.label,
                available=False,
                reason=f"model files not found in {self.model_dir}: {', '.join(missing)}",
            )

        if not self._has_nemo_runtime():
            return ProviderInfo(
                id=self.id,
                label=self.label,
                available=False,
                reason="NVIDIA NeMo speechlm2 runtime is not installed",
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
            return ASRTranscript(text=self._transcribe_file(wav_file.name))

    def _transcribe_file(self, audio_path: str) -> str:
        model = self._get_model()
        audio_locator = getattr(model, "audio_locator_tag", "<|audioplaceholder|>")
        answer_ids = model.generate(
            prompts=[
                [
                    {
                        "role": "user",
                        "content": f"Transcribe the following: {audio_locator}",
                        "audio": [audio_path],
                    }
                ]
            ],
            max_new_tokens=256,
        )
        first_answer = answer_ids[0] if isinstance(answer_ids, (list, tuple)) else answer_ids
        if hasattr(first_answer, "cpu"):
            first_answer = first_answer.cpu()
        tokenizer = getattr(model, "tokenizer", None)
        if tokenizer is not None and hasattr(tokenizer, "ids_to_text"):
            return self._clean_text(str(tokenizer.ids_to_text(first_answer)))
        return self._clean_text(str(first_answer))

    def _get_model(self):
        if self._model is None:
            from nemo.collections.speechlm2.models import SALM

            self._model = SALM.from_pretrained(str(self.model_dir))
        return self._model

    def _has_nemo_runtime(self) -> bool:
        try:
            return importlib.util.find_spec("nemo.collections.speechlm2.models") is not None
        except (ImportError, ModuleNotFoundError, ValueError):
            return False

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

    def _clean_text(self, text: str) -> str:
        cleaned = text.strip()
        for marker in ["<|endoftext|>", "<|im_end|>", "</s>"]:
            cleaned = cleaned.replace(marker, "")
        return cleaned.strip()
