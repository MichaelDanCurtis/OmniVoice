#!/usr/bin/env bash
set -euo pipefail

BUNDLED_ENGINE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_SUPPORT_DIR="${OMNIVOICE_APP_SUPPORT_DIR:-$HOME/Library/Application Support/OmniVoice}"
VENV_DIR="${OMNIVOICE_ENGINE_VENV:-$APP_SUPPORT_DIR/engine-venv}"
RUNTIME_ENGINE_ROOT="$APP_SUPPORT_DIR/engine-source"
PYTHON_BIN="${OMNIVOICE_PYTHON:-}"
PORT="${OMNIVOICE_ENGINE_PORT:-8765}"

python_supports_engine() {
  "$1" - <<'PY' >/dev/null 2>&1
import sys

raise SystemExit(0 if sys.version_info >= (3, 12) else 1)
PY
}

python_can_create_venv() {
  local check_dir
  check_dir="$(mktemp -d "$APP_SUPPORT_DIR/.python-venv-check.XXXXXX")" || return 1
  "$1" -m venv "$check_dir/venv" >/dev/null 2>&1
  local status=$?
  rm -rf "$check_dir"
  return "$status"
}

candidate_python_bins() {
  if [[ -n "$PYTHON_BIN" ]]; then
    printf '%s\n' "$PYTHON_BIN"
    return
  fi

  local seen=""
  local candidate
  local names=("python3.12" "/opt/homebrew/bin/python3.12" "/usr/local/bin/python3.12" "python3")
  local name
  for name in "${names[@]}"; do
    if [[ "$name" = /* ]]; then
      [[ -x "$name" ]] || continue
      candidate="$name"
    else
      candidate="$(command -v "$name" 2>/dev/null || true)"
      [[ -n "$candidate" ]] || continue
    fi

    case " $seen " in
      *" $candidate "*) continue ;;
    esac
    seen="$seen $candidate"
    printf '%s\n' "$candidate"
  done
}

resolve_python_bin_for_venv() {
  local candidate
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    if python_supports_engine "$candidate" && python_can_create_venv "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(candidate_python_bins)
  return 1
}

venv_supports_engine() {
  [[ -x "$VENV_DIR/bin/python" ]] || return 1
  python_supports_engine "$VENV_DIR/bin/python"
}

mkdir -p "$APP_SUPPORT_DIR"
rm -rf "$RUNTIME_ENGINE_ROOT"
mkdir -p "$RUNTIME_ENGINE_ROOT"
cp "$BUNDLED_ENGINE_ROOT/pyproject.toml" "$RUNTIME_ENGINE_ROOT/"
cp -R "$BUNDLED_ENGINE_ROOT/omnivoice_engine" "$RUNTIME_ENGINE_ROOT/"

if [[ -d "$VENV_DIR" ]] && ! venv_supports_engine; then
  echo "Existing OmniVoice engine venv is invalid; recreating it." >&2
  rm -rf "$VENV_DIR"
fi

if [[ ! -d "$VENV_DIR" ]]; then
  if ! PYTHON_BIN="$(resolve_python_bin_for_venv)"; then
    echo "Python 3.12 or newer with venv support is required to run the OmniVoice engine." >&2
    exit 127
  fi
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

if ! venv_supports_engine; then
  echo "OmniVoice engine venv is not using Python 3.12 or newer after creation." >&2
  exit 1
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
