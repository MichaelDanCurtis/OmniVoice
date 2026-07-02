#!/usr/bin/env bash
set -euo pipefail

BUNDLED_ENGINE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_RESOURCES_DIR="$(cd "$BUNDLED_ENGINE_ROOT/.." && pwd)"
BUNDLED_PYTHON_BIN="$APP_RESOURCES_DIR/Python/bin/python3.12"
BUNDLED_PYTHON_FALLBACK_BIN="$APP_RESOURCES_DIR/Python/bin/python3"
BUNDLED_WHEELHOUSE_DIR="$BUNDLED_ENGINE_ROOT/wheelhouse"
APP_SUPPORT_DIR="${OMNIVOICE_APP_SUPPORT_DIR:-$HOME/Library/Application Support/OmniSpeak}"
VENV_DIR="${OMNIVOICE_ENGINE_VENV:-$APP_SUPPORT_DIR/engine-venv}"
RUNTIME_ENGINE_ROOT="$APP_SUPPORT_DIR/engine-source"
PYTHON_BIN="${OMNIVOICE_PYTHON:-}"
PORT="${OMNIVOICE_ENGINE_PORT:-8765}"
ALLOW_SYSTEM_PYTHON_FALLBACK="${OMNIVOICE_ALLOW_SYSTEM_PYTHON_FALLBACK:-0}"
USE_BUNDLED_WHEELHOUSE="${OMNIVOICE_USE_BUNDLED_WHEELHOUSE:-1}"

# The bundled Python runtime lives inside the signed app bundle, so it must not
# write __pycache__ files into Contents/Resources at launch time.
export PYTHONDONTWRITEBYTECODE="${PYTHONDONTWRITEBYTECODE:-1}"
export PYTHONPYCACHEPREFIX="${PYTHONPYCACHEPREFIX:-$APP_SUPPORT_DIR/python-cache}"

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

python_base_prefix() {
  "$1" <<'PY' 2>/dev/null || true
import sys
print(sys.base_prefix)
PY
}

resolve_python() {
  local minimum_version="3.12"
  local candidates=()
  local candidate

  if [[ -n "$PYTHON_BIN" ]]; then
    candidates+=("$PYTHON_BIN")
  fi

  if [[ -x "$BUNDLED_PYTHON_BIN" ]]; then
    candidates+=("$BUNDLED_PYTHON_BIN")
  elif [[ -x "$BUNDLED_PYTHON_FALLBACK_BIN" ]]; then
    candidates+=("$BUNDLED_PYTHON_FALLBACK_BIN")
  else
    echo "Bundled Python runtime is missing at $APP_RESOURCES_DIR/Python; trying fallback candidates." >&2
  fi

  if [[ "$ALLOW_SYSTEM_PYTHON_FALLBACK" = "1" ]]; then
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
  fi

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

  echo "OmniSpeak could not find a usable bundled Python 3.12+ runtime." >&2
  echo "Reinstall OmniSpeak, or set OMNIVOICE_PYTHON to a Python 3.12+ executable." >&2
  exit 127
}

resolve_python

mkdir -p "$APP_SUPPORT_DIR"
rm -rf "$RUNTIME_ENGINE_ROOT"
mkdir -p "$RUNTIME_ENGINE_ROOT"
cp "$BUNDLED_ENGINE_ROOT/pyproject.toml" "$RUNTIME_ENGINE_ROOT/"
cp -R "$BUNDLED_ENGINE_ROOT/omnivoice_engine" "$RUNTIME_ENGINE_ROOT/"

if [[ -x "$VENV_DIR/bin/python" ]]; then
  if ! python_is_supported "$VENV_DIR/bin/python" "3.12"; then
    echo "Existing OmniSpeak engine venv uses Python $(python_version_label "$VENV_DIR/bin/python"); rebuilding with $PYTHON_BIN." >&2
    rm -rf "$VENV_DIR"
  else
    selected_base_prefix="$(python_base_prefix "$PYTHON_BIN")"
    existing_base_prefix="$(python_base_prefix "$VENV_DIR/bin/python")"
    if [[ -n "$selected_base_prefix" && -n "$existing_base_prefix" && "$selected_base_prefix" != "$existing_base_prefix" ]]; then
      echo "Existing OmniSpeak engine venv uses $existing_base_prefix; rebuilding with bundled Python at $selected_base_prefix." >&2
      rm -rf "$VENV_DIR"
    fi
  fi
fi

if [[ ! -d "$VENV_DIR" ]]; then
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

. "$VENV_DIR/bin/activate"
if ! python_is_supported "$(command -v python)" "3.12"; then
  echo "OmniSpeak engine venv is not using Python 3.12 or newer after creation." >&2
  exit 1
fi

python_module_available() {
  python - "$1" <<'PY' >/dev/null 2>&1
import importlib.util
import sys

try:
    available = importlib.util.find_spec(sys.argv[1]) is not None
except (ImportError, ModuleNotFoundError, ValueError):
    available = False
raise SystemExit(0 if available else 1)
PY
}

PIP_INSTALL_ARGS=()

configure_pip_install_args() {
  if [[ "$USE_BUNDLED_WHEELHOUSE" != "1" ]]; then
    return
  fi

  if [[ ! -d "$BUNDLED_WHEELHOUSE_DIR" ]] || ! find "$BUNDLED_WHEELHOUSE_DIR" -type f \( -name "*.whl" -o -name "*.tar.gz" -o -name "*.zip" \) -print -quit | grep -q .; then
    echo "Bundled OmniSpeak Python wheelhouse is missing at $BUNDLED_WHEELHOUSE_DIR." >&2
    echo "Reinstall OmniSpeak, or set OMNIVOICE_USE_BUNDLED_WHEELHOUSE=0 to allow network package installation." >&2
    exit 127
  fi

  PIP_INSTALL_ARGS=(--no-index --find-links "$BUNDLED_WHEELHOUSE_DIR")
}

pip_install() {
  python -m pip install "${PIP_INSTALL_ARGS[@]}" "$@"
}

configure_pip_install_args

python -m ensurepip --upgrade >/dev/null 2>&1 || true
pip_install --upgrade setuptools wheel
pip_install --no-build-isolation "$RUNTIME_ENGINE_ROOT"

if [[ "${OMNIVOICE_INSTALL_ASR:-1}" = "1" ]]; then
  pip_install --no-build-isolation "$RUNTIME_ENGINE_ROOT[asr]"
fi

if [[ "${OMNIVOICE_INSTALL_MLX_DIARIZATION:-0}" = "1" ]]; then
  pip_install --no-build-isolation "$RUNTIME_ENGINE_ROOT[mlx-diarization]" || echo "MLX diarization runtime install failed; continuing without it." >&2
fi

if [[ "${OMNIVOICE_INSTALL_MLX_ASR:-0}" = "1" ]]; then
  pip_install --no-build-isolation "$RUNTIME_ENGINE_ROOT[mlx-asr]" || echo "MLX ASR runtime install failed; continuing without it." >&2
fi

if [[ "${OMNIVOICE_INSTALL_CANARY_ASR:-0}" = "1" ]]; then
  if ! python_module_available "nemo.collections.speechlm2.models"; then
    if ! pip_install --no-build-isolation "$RUNTIME_ENGINE_ROOT[canary-asr]"; then
      if [[ "$USE_BUNDLED_WHEELHOUSE" = "1" ]]; then
        echo "Canary-Qwen runtime is not part of the bundled wheelhouse; retrying with network package installation." >&2
        python -m pip install --no-build-isolation "$RUNTIME_ENGINE_ROOT[canary-asr]" || echo "Canary-Qwen runtime install failed; continuing without it." >&2
      else
        echo "Canary-Qwen runtime install failed; continuing without it." >&2
      fi
    fi
  fi
fi

export OMNIVOICE_MODEL_ROOT="${OMNIVOICE_MODEL_ROOT:-$APP_SUPPORT_DIR/models}"
export OMNIVOICE_PARAKEET_MODEL_DIR="${OMNIVOICE_PARAKEET_MODEL_DIR:-$OMNIVOICE_MODEL_ROOT/parakeet-tdt}"
export OMNIVOICE_PARAKEET_MLX_MODEL_DIR="${OMNIVOICE_PARAKEET_MLX_MODEL_DIR:-$OMNIVOICE_MODEL_ROOT/parakeet-tdt-mlx}"
export OMNIVOICE_WHISPER_MLX_MODEL_DIR="${OMNIVOICE_WHISPER_MLX_MODEL_DIR:-$OMNIVOICE_MODEL_ROOT/whisper-large-v3-turbo-mlx-6bit}"
export OMNIVOICE_CANARY_MODEL_DIR="${OMNIVOICE_CANARY_MODEL_DIR:-$OMNIVOICE_MODEL_ROOT/canary-qwen-2.5b}"
export OMNIVOICE_MLX_SORTFORMER_FP16_DIR="${OMNIVOICE_MLX_SORTFORMER_FP16_DIR:-$OMNIVOICE_MODEL_ROOT/mlx-sortformer-streaming-fp16}"
export OMNIVOICE_MLX_SORTFORMER_FP32_DIR="${OMNIVOICE_MLX_SORTFORMER_FP32_DIR:-$OMNIVOICE_MODEL_ROOT/mlx-sortformer-streaming-fp32}"
export OMNIVOICE_ENGINE_DATA_DIR="${OMNIVOICE_ENGINE_DATA_DIR:-$APP_SUPPORT_DIR/engine-data}"

mkdir -p "$OMNIVOICE_MODEL_ROOT" "$OMNIVOICE_ENGINE_DATA_DIR"

exec uvicorn omnivoice_engine.main:app --host 127.0.0.1 --port "$PORT"
