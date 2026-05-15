#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}/engine"

if [ ! -d ".venv" ]; then
  python3.12 -m venv .venv
fi

. .venv/bin/activate
python -m pip install -e ".[dev]"

if [ "${OMNIVOICE_INSTALL_ASR:-1}" = "1" ]; then
  python -m pip install -e ".[asr]"
fi

export OMNIVOICE_MODEL_ROOT="${ROOT_DIR}/models"
export OMNIVOICE_PARAKEET_MODEL_DIR="${ROOT_DIR}/models/parakeet-tdt"
export OMNIVOICE_CANARY_MODEL_DIR="${ROOT_DIR}/models/canary-qwen-2.5b"
exec uvicorn omnivoice_engine.main:app --host 127.0.0.1 --port 8765
