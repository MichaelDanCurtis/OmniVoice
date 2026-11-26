from __future__ import annotations

import importlib.util
import os
import platform
import re
import threading
from dataclasses import dataclass
from pathlib import Path

from .paths import default_model_root
from .schemas import ProviderInfo


THINK_BLOCK_PATTERN = re.compile(r"<think>.*?</think>", re.DOTALL | re.IGNORECASE)


@dataclass(frozen=True)
class LocalCleanupModelSpec:
    id: str
    label: str
    env_var: str
    default_subdir: str
    required_files: tuple[str, ...] = ("config.json", "model.safetensors", "tokenizer.json")


LOCAL_CLEANUP_MODELS: dict[str, LocalCleanupModelSpec] = {
    "qwen3-1.7b-mlx-4bit": LocalCleanupModelSpec(
        id="qwen3-1.7b-mlx-4bit",
        label="Qwen3 1.7B MLX 4-bit",
        env_var="OMNIVOICE_CLEANUP_QWEN3_1_7B_DIR",
        default_subdir="qwen3-1.7b-mlx-4bit",
    ),
    "qwen3-4b-instruct-mlx-4bit": LocalCleanupModelSpec(
        id="qwen3-4b-instruct-mlx-4bit",
        label="Qwen3 4B Instruct MLX 4-bit",
        env_var="OMNIVOICE_CLEANUP_QWEN3_4B_DIR",
        default_subdir="qwen3-4b-instruct-mlx-4bit",
    ),
}
DEFAULT_LOCAL_CLEANUP_MODEL_ID = "qwen3-1.7b-mlx-4bit"


def strip_thinking_blocks(text: str) -> str:
    cleaned = THINK_BLOCK_PATTERN.sub("", text)
    if "<think>" in cleaned.lower():
        cleaned = re.split(r"<think>", cleaned, maxsplit=1, flags=re.IGNORECASE)[0]
    return cleaned.strip()


class LocalMLXCleanupEngine:
    """In-process Apple Silicon MLX text cleanup runner backed by `mlx-lm`.

    Loads one quantized local cleanup model at a time and caches it across
    dictations for sub-second semantic cleanup without requiring Ollama or a
    cloud API key.
    """

    def __init__(self, model_root: str | Path | None = None) -> None:
        self._model_root = Path(model_root).expanduser() if model_root is not None else None
        self._lock = threading.Lock()
        self._loaded_path: str | None = None
        self._model = None
        self._tokenizer = None

    def list_providers(self) -> list[ProviderInfo]:
        return [self.info(model_id) for model_id in LOCAL_CLEANUP_MODELS]

    def resolve_model_dir(self, model_id: str = DEFAULT_LOCAL_CLEANUP_MODEL_ID, model_path: str = "") -> Path:
        explicit = model_path.strip()
        if explicit:
            return Path(explicit).expanduser()
        spec = LOCAL_CLEANUP_MODELS.get(model_id) or LOCAL_CLEANUP_MODELS[DEFAULT_LOCAL_CLEANUP_MODEL_ID]
        configured = os.environ.get(spec.env_var, "").strip()
        if configured:
            return Path(configured).expanduser()
        root = self._model_root if self._model_root is not None else default_model_root(__file__)
        return root / spec.default_subdir

    def info(self, model_id: str = DEFAULT_LOCAL_CLEANUP_MODEL_ID, model_path: str = "") -> ProviderInfo:
        spec = LOCAL_CLEANUP_MODELS.get(model_id)
        label = spec.label if spec else (model_id or DEFAULT_LOCAL_CLEANUP_MODEL_ID)
        provider_id = spec.id if spec else (model_id or DEFAULT_LOCAL_CLEANUP_MODEL_ID)

        if not self._is_apple_silicon_macos():
            return ProviderInfo(
                id=provider_id,
                label=label,
                available=False,
                reason="Local MLX cleanup requires Apple Silicon macOS",
            )

        directory = self.resolve_model_dir(provider_id, model_path=model_path)
        required = spec.required_files if spec else ("config.json", "tokenizer.json")
        missing = [filename for filename in required if not (directory / filename).exists()]
        if missing:
            return ProviderInfo(
                id=provider_id,
                label=label,
                available=False,
                reason=f"model files not found in {directory}: {', '.join(missing)}",
            )

        if importlib.util.find_spec("mlx_lm") is None:
            return ProviderInfo(
                id=provider_id,
                label=label,
                available=False,
                reason="mlx-lm runtime is not installed",
            )

        return ProviderInfo(id=provider_id, label=label, available=True)

    def cleanup(
        self,
        *,
        messages: list[dict[str, str]],
        model_id: str = DEFAULT_LOCAL_CLEANUP_MODEL_ID,
        model_path: str = "",
        max_tokens: int = 384,
    ) -> str:
        info = self.info(model_id=model_id, model_path=model_path)
        if not info.available:
            raise RuntimeError(info.reason or "local MLX cleanup unavailable")

        directory = str(self.resolve_model_dir(model_id=model_id, model_path=model_path))
        with self._lock:
            model, tokenizer = self._load(directory)
            prompt = self._format_prompt(tokenizer, messages)
            from mlx_lm import generate

            raw = generate(
                model,
                tokenizer,
                prompt=prompt,
                max_tokens=max_tokens,
                verbose=False,
            )
        return strip_thinking_blocks(str(raw or ""))

    def _load(self, directory: str):
        if self._model is not None and self._tokenizer is not None and self._loaded_path == directory:
            return self._model, self._tokenizer

        from mlx_lm import load

        self._model, self._tokenizer = load(directory)
        self._loaded_path = directory
        return self._model, self._tokenizer

    @staticmethod
    def _format_prompt(tokenizer, messages: list[dict[str, str]]) -> str:
        apply_template = getattr(tokenizer, "apply_chat_template", None)
        if callable(apply_template):
            try:
                return apply_template(
                    messages,
                    tokenize=False,
                    add_generation_prompt=True,
                    enable_thinking=False,
                )
            except TypeError:
                return apply_template(
                    messages,
                    tokenize=False,
                    add_generation_prompt=True,
                )
        return "\n\n".join(f"{m['role'].upper()}: {m['content']}" for m in messages) + "\n\nASSISTANT:"

    @staticmethod
    def _is_apple_silicon_macos() -> bool:
        return platform.system() == "Darwin" and platform.machine() in {"arm64", "aarch64"}
