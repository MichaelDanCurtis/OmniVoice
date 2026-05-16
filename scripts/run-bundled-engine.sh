#!/usr/bin/env bash
set -euo pipefail

BUNDLED_ENGINE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_SUPPORT_DIR="${OMNIVOICE_APP_SUPPORT_DIR:-$HOME/Library/Application Support/OmniVoice}"
VENV_DIR="${OMNIVOICE_ENGINE_VENV:-$APP_SUPPORT_DIR/engine-venv}"
RUNTIME_ENGINE_ROOT="$APP_SUPPORT_DIR/engine-source"
PYTHON_BIN="${OMNIVOICE_PYTHON:-}"
PORT="${OMNIVOICE_ENGINE_PORT:-8765}"

if [[ -z "$PYTHON_BIN" ]]; then
  if command -v python3.12 >/dev/null 2>&1; then
    PYTHON_BIN="$(command -v python3.12)"
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="$(command -v python3)"
  else
    echo "Python 3.12 or newer is required to run the OmniVoice engine." >&2
    exit 127
  fi
fi

mkdir -p "$APP_SUPPORT_DIR"
rm -rf "$RUNTIME_ENGINE_ROOT"
mkdir -p "$RUNTIME_ENGINE_ROOT"
cp "$BUNDLED_ENGINE_ROOT/pyproject.toml" "$RUNTIME_ENGINE_ROOT/"
cp -R "$BUNDLED_ENGINE_ROOT/omnivoice_engine" "$RUNTIME_ENGINE_ROOT/"

if [[ ! -d "$VENV_DIR" ]]; then
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

. "$VENV_DIR/bin/activate"
python -m pip install --upgrade pip
python -m pip install "$RUNTIME_ENGINE_ROOT"

if [[ "${OMNIVOICE_INSTALL_ASR:-1}" = "1" ]]; then
  python -m pip install "$RUNTIME_ENGINE_ROOT[asr]"
fi

export OMNIVOICE_MODEL_ROOT="${OMNIVOICE_MODEL_ROOT:-$APP_SUPPORT_DIR/models}"
export OMNIVOICE_PARAKEET_MODEL_DIR="${OMNIVOICE_PARAKEET_MODEL_DIR:-$OMNIVOICE_MODEL_ROOT/parakeet-tdt}"
export OMNIVOICE_CANARY_MODEL_DIR="${OMNIVOICE_CANARY_MODEL_DIR:-$OMNIVOICE_MODEL_ROOT/canary-qwen-2.5b}"
export OMNIVOICE_ENGINE_DATA_DIR="${OMNIVOICE_ENGINE_DATA_DIR:-$APP_SUPPORT_DIR/engine-data}"

mkdir -p "$OMNIVOICE_MODEL_ROOT" "$OMNIVOICE_ENGINE_DATA_DIR"

exec uvicorn omnivoice_engine.main:app --host 127.0.0.1 --port "$PORT"
