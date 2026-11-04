from __future__ import annotations

import ast
import importlib.util
import os
import re
import tempfile
import threading
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

    def warm_up(self) -> None:
        info = self.info()
        if not info.available:
            raise RuntimeError(info.reason)
        self._get_model()

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
            max_new_tokens=128,
        )
        first_answer = answer_ids[0] if isinstance(answer_ids, (list, tuple)) else answer_ids
        if hasattr(first_answer, "cpu"):
            first_answer = first_answer.cpu()
        tokenizer = getattr(model, "tokenizer", None)
        if tokenizer is not None:
            return self._clean_text(self._decode_answer(tokenizer, first_answer))
        return self._clean_text(str(first_answer))

    def _get_model(self):
        if self._model is None:
            with self._model_lock:
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
        cleaned = self._unwrap_text_payload(text.strip())
        normalized = cleaned.replace("\r\n", "\n")

        for marker in ("<|im_start|>assistant", "\nassistant\n", "\nassistant:", "assistant\n", "assistant:"):
            index = normalized.lower().rfind(marker)
            if index >= 0:
                normalized = normalized[index + len(marker):]
                break

        prompt_index = normalized.lower().rfind("transcribe the following:")
        if prompt_index >= 0:
            normalized = normalized[prompt_index + len("transcribe the following:"):]

        normalized = re.sub(r"<\|[^|]+?\|>", " ", normalized)
        normalized = normalized.replace("</s>", " ").replace("<s>", " ")
        lines = [
            line.strip()
            for line in normalized.splitlines()
            if line.strip().lower() not in {"user", "assistant", "system"}
        ]
        return re.sub(r"\s+", " ", " ".join(lines)).strip()

    def _unwrap_text_payload(self, text: str) -> str:
        try:
            payload = ast.literal_eval(text)
        except (SyntaxError, ValueError):
            return text

        if isinstance(payload, str):
            return payload
        if isinstance(payload, (list, tuple)) and all(isinstance(item, str) for item in payload):
            return " ".join(item.strip() for item in payload if item.strip())
        return text

    def _decode_answer(self, tokenizer, token_ids) -> str:
        decode_ids = token_ids.tolist() if hasattr(token_ids, "tolist") else token_ids

        if hasattr(tokenizer, "decode"):
            try:
                return str(tokenizer.decode(decode_ids, skip_special_tokens=True))
            except TypeError:
                return str(tokenizer.decode(decode_ids))

        if hasattr(tokenizer, "ids_to_text"):
            return str(tokenizer.ids_to_text(token_ids))

        return str(token_ids)
