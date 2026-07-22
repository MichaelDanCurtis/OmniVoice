"""Execution-device selection for the sherpa-onnx ASR providers.

Windows ships CPU-only by default. When the user installs `onnxruntime-gpu`
alongside a CUDA runtime, the very same ONNX model files can run on an NVIDIA
GPU — only the onnxruntime *execution provider* changes. This module decides
which one to ask for; `sherpa_runtime` handles the case where that request
turns out to be unusable at runtime.
"""

from __future__ import annotations

from typing import Mapping

CPU = "cpu"
CUDA = "cuda"

DEVICE_ENV_VAR = "OMNIVOICE_ASR_DEVICE"

_CUDA_ALIASES = {"cuda", "gpu", "nvidia"}
_CPU_ALIASES = {"cpu"}
_AUTO_ALIASES = {"auto", "default"}

CUDA_EXECUTION_PROVIDER = "CUDAExecutionProvider"


def requested_device_from_env(environ: Mapping[str, str]) -> str | None:
    """Reads the device override from the environment; None means 'not set'."""
    value = (environ.get(DEVICE_ENV_VAR) or "").strip()
    return value or None


def available_onnx_providers() -> list[str]:
    """Execution providers onnxruntime reports, or [] when it isn't importable.

    An empty list is not proof that CUDA is unusable — sherpa-onnx may link its
    own onnxruntime — so it only steers the `auto` decision, never overrides an
    explicit request.
    """
    try:
        import onnxruntime
    except Exception:
        return []

    try:
        return list(onnxruntime.get_available_providers())
    except Exception:
        return []


def resolve_device(requested: str | None, available_providers: list[str]) -> str:
    """Maps a requested device (or 'auto') onto a sherpa `provider` string.

    - `auto`/unset: use CUDA only when onnxruntime reports it, else CPU.
    - explicit `cuda`/`gpu`/`nvidia`: honored even if detection found nothing.
    - explicit `cpu`: always CPU, even when a GPU is present.
    - anything unrecognized: CPU (safest default).
    """
    normalized = (requested or "").strip().lower()

    if normalized in _CUDA_ALIASES:
        return CUDA
    if normalized in _CPU_ALIASES:
        return CPU
    if normalized and normalized not in _AUTO_ALIASES:
        return CPU

    return CUDA if CUDA_EXECUTION_PROVIDER in (available_providers or []) else CPU


def resolve_device_from_env(environ: Mapping[str, str]) -> str:
    """Convenience: env override + live onnxruntime detection."""
    return resolve_device(requested_device_from_env(environ), available_onnx_providers())
