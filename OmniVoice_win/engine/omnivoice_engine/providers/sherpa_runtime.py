"""Shared runtime helpers for the sherpa-onnx providers."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable

from .device import CPU


@dataclass(frozen=True)
class RecognizerBuild:
    """A built recognizer plus the device it actually ended up on."""

    recognizer: Any
    device: str
    fallback_reason: str | None = None


def build_recognizer(build: Callable[[str], Any], device: str) -> RecognizerBuild:
    """Builds a recognizer on `device`, degrading to CPU rather than failing.

    Getting CUDA working on Windows requires onnxruntime-gpu, the CUDA runtime
    and cuDNN to all agree on versions; when they don't, construction throws.
    Dictation should keep working in that case, so a failed GPU build retries on
    CPU and records why — the caller surfaces that through `ProviderInfo`.

    A CPU failure is a genuine problem (missing/corrupt models) and propagates.
    """
    try:
        return RecognizerBuild(recognizer=build(device), device=device)
    except Exception as exc:
        if device == CPU:
            raise
        reason = f"{device} unavailable, using CPU instead: {exc}"
        return RecognizerBuild(recognizer=build(CPU), device=CPU, fallback_reason=reason)
