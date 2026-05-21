#!/usr/bin/env bash
set -euo pipefail

BUNDLED_ENGINE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_SUPPORT_DIR="${OMNIVOICE_APP_SUPPORT_DIR:-$HOME/Library/Application Support/OmniVoice}"
VENV_DIR="${OMNIVOICE_ENGINE_VENV:-$APP_SUPPORT_DIR/engine-venv}"
RUNTIME_ENGINE_ROOT="$APP_SUPPORT_DIR/engine-source"
PYTHON_BIN="${OMNIVOICE_PYTHON:-}"
PORT="${OMNIVOICE_ENGINE_PORT:-8765}"

python_is_supported() {
  "$1" - "$2" <<'PY' >/dev/null 2>&1
import pathlib
import sys

minimum = tuple(int(part) for part in sys.argv[1].split("."))
raise SystemExit(0 if sys.version_info[:2] >= minimum and pathlib.Path(sys.executable).exists() else 1)
PY
}

python_version_label() {
  "$1" <<'PY' 2>/dev/null || true
import sys
print(".".join(str(part) for part in sys.version_info[:3]))
PY
}

resolve_python() {
  local minimum_version="3.12"
  local candidates=()
  local candidate

  if [[ -n "$PYTHON_BIN" ]]; then
    candidates+=("$PYTHON_BIN")
  fi

  for candidate in \
    python3.13 \
    python3.12 \
    /opt/homebrew/bin/python3.13 \
    /opt/homebrew/bin/python3.12 \
    /opt/homebrew/opt/python@3.13/bin/python3.13 \
    /opt/homebrew/opt/python@3.12/bin/python3.12 \
    /usr/local/bin/python3.13 \
    /usr/local/bin/python3.12 \
    /usr/local/opt/python@3.13/bin/python3.13 \
    /usr/local/opt/python@3.12/bin/python3.12 \
    python3; do
    if [[ "$candidate" == */* ]]; then
      [[ -x "$candidate" ]] && candidates+=("$candidate")
    elif command -v "$candidate" >/dev/null 2>&1; then
      candidates+=("$(command -v "$candidate")")
    fi
  done

  local seen=":"
  for candidate in "${candidates[@]}"; do
    [[ -n "$candidate" ]] || continue
    [[ "$seen" == *":$candidate:"* ]] && continue
    seen="$seen$candidate:"
    if python_is_supported "$candidate" "$minimum_version"; then
      PYTHON_BIN="$candidate"
      return 0
    fi
  done

  echo "Python 3.12 or newer is required to run the OmniVoice engine." >&2
  echo "Install it with Homebrew, or set OMNIVOICE_PYTHON to a Python 3.12+ executable." >&2
  exit 127
}

resolve_python

mkdir -p "$APP_SUPPORT_DIR"
rm -rf "$RUNTIME_ENGINE_ROOT"
mkdir -p "$RUNTIME_ENGINE_ROOT"
cp "$BUNDLED_ENGINE_ROOT/pyproject.toml" "$RUNTIME_ENGINE_ROOT/"
cp -R "$BUNDLED_ENGINE_ROOT/omnivoice_engine" "$RUNTIME_ENGINE_ROOT/"

if [[ -x "$VENV_DIR/bin/python" ]] && ! python_is_supported "$VENV_DIR/bin/python" "3.12"; then
  echo "Existing OmniVoice engine venv uses Python $(python_version_label "$VENV_DIR/bin/python"); rebuilding with $PYTHON_BIN." >&2
  rm -rf "$VENV_DIR"
fi

if [[ ! -d "$VENV_DIR" ]]; then
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

. "$VENV_DIR/bin/activate"
if ! python_is_supported "$(command -v python)" "3.12"; then
  echo "OmniVoice engine venv is not using Python 3.12 or newer after creation." >&2
  exit 1
fi
python -m ensurepip --upgrade >/dev/null 2>&1 || true
python -m pip install --upgrade pip
python -m pip install "$RUNTIME_ENGINE_ROOT"

if [[ "${OMNIVOICE_INSTALL_ASR:-1}" = "1" ]]; then
  python -m pip install "$RUNTIME_ENGINE_ROOT[asr]"
fi

if [[ "${OMNIVOICE_INSTALL_MLX_DIARIZATION:-0}" = "1" ]]; then
  python -m pip install "$RUNTIME_ENGINE_ROOT[mlx-diarization]" || echo "MLX diarization runtime install failed; continuing without it." >&2
fi

if [[ "${OMNIVOICE_INSTALL_MLX_ASR:-0}" = "1" ]]; then
  python -m pip install "$RUNTIME_ENGINE_ROOT[mlx-asr]" || echo "MLX ASR runtime install failed; continuing without it." >&2
fi

export OMNIVOICE_MODEL_ROOT="${OMNIVOICE_MODEL_ROOT:-$APP_SUPPORT_DIR/models}"
export OMNIVOICE_PARAKEET_MODEL_DIR="${OMNIVOICE_PARAKEET_MODEL_DIR:-$OMNIVOICE_MODEL_ROOT/parakeet-tdt}"
export OMNIVOICE_PARAKEET_MLX_MODEL_DIR="${OMNIVOICE_PARAKEET_MLX_MODEL_DIR:-$OMNIVOICE_MODEL_ROOT/parakeet-tdt-mlx}"
export OMNIVOICE_CANARY_MODEL_DIR="${OMNIVOICE_CANARY_MODEL_DIR:-$OMNIVOICE_MODEL_ROOT/canary-qwen-2.5b}"
export OMNIVOICE_MLX_SORTFORMER_FP16_DIR="${OMNIVOICE_MLX_SORTFORMER_FP16_DIR:-$OMNIVOICE_MODEL_ROOT/mlx-sortformer-streaming-fp16}"
export OMNIVOICE_MLX_SORTFORMER_FP32_DIR="${OMNIVOICE_MLX_SORTFORMER_FP32_DIR:-$OMNIVOICE_MODEL_ROOT/mlx-sortformer-streaming-fp32}"
export OMNIVOICE_ENGINE_DATA_DIR="${OMNIVOICE_ENGINE_DATA_DIR:-$APP_SUPPORT_DIR/engine-data}"

mkdir -p "$OMNIVOICE_MODEL_ROOT" "$OMNIVOICE_ENGINE_DATA_DIR"

exec uvicorn omnivoice_engine.main:app --host 127.0.0.1 --port "$PORT"
