#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${OMNIVOICE_ENGINE_PORT:-8765}"
cd "${ROOT_DIR}/engine"

if [ ! -d ".venv" ]; then
  python3.12 -m venv .venv
fi

. .venv/bin/activate
if ! python -m pip --version >/dev/null 2>&1; then
  python -m ensurepip --upgrade
fi
python -m pip install -e ".[dev]"

if [ "${OMNIVOICE_INSTALL_ASR:-1}" = "1" ]; then
  python -m pip install -e ".[asr]"
fi

if [ "${OMNIVOICE_INSTALL_MLX_DIARIZATION:-0}" = "1" ]; then
  python -m pip install -e ".[mlx-diarization]" || echo "MLX diarization runtime install failed; continuing without it." >&2
fi

if [ "${OMNIVOICE_INSTALL_MLX_ASR:-0}" = "1" ]; then
  python -m pip install -e ".[mlx-asr]" || echo "MLX ASR runtime install failed; continuing without it." >&2
fi

export OMNIVOICE_MODEL_ROOT="${OMNIVOICE_MODEL_ROOT:-${ROOT_DIR}/models}"
export OMNIVOICE_PARAKEET_MODEL_DIR="${OMNIVOICE_PARAKEET_MODEL_DIR:-${OMNIVOICE_MODEL_ROOT}/parakeet-tdt}"
export OMNIVOICE_PARAKEET_MLX_MODEL_DIR="${OMNIVOICE_PARAKEET_MLX_MODEL_DIR:-${OMNIVOICE_MODEL_ROOT}/parakeet-tdt-mlx}"
export OMNIVOICE_CANARY_MODEL_DIR="${OMNIVOICE_CANARY_MODEL_DIR:-${OMNIVOICE_MODEL_ROOT}/canary-qwen-2.5b}"
export OMNIVOICE_MLX_SORTFORMER_FP16_DIR="${OMNIVOICE_MLX_SORTFORMER_FP16_DIR:-${OMNIVOICE_MODEL_ROOT}/mlx-sortformer-streaming-fp16}"
export OMNIVOICE_MLX_SORTFORMER_FP32_DIR="${OMNIVOICE_MLX_SORTFORMER_FP32_DIR:-${OMNIVOICE_MODEL_ROOT}/mlx-sortformer-streaming-fp32}"
export OMNIVOICE_ENGINE_DATA_DIR="${OMNIVOICE_ENGINE_DATA_DIR:-${ROOT_DIR}/dist/engine-data}"
exec uvicorn omnivoice_engine.main:app --host 127.0.0.1 --port "$PORT"
