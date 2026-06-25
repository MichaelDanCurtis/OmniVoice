#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d -t omnivoice-bundled-engine-test.XXXXXX)"
SERVER_PID=""

cleanup() {
  if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

ENGINE_DIR="$TMP_DIR/Engine"
APP_SUPPORT_DIR="$TMP_DIR/App Support"
VENV_DIR="$APP_SUPPORT_DIR/engine-venv"
mkdir -p "$ENGINE_DIR" "$VENV_DIR/bin"

cp "$ROOT_DIR/scripts/run-bundled-engine.sh" "$ENGINE_DIR/run-engine-bundled.sh"
cp "$ROOT_DIR/engine/pyproject.toml" "$ENGINE_DIR/"
cp -R "$ROOT_DIR/engine/omnivoice_engine" "$ENGINE_DIR/"

cat >"$VENV_DIR/bin/activate" <<ACTIVATE
VIRTUAL_ENV="$VENV_DIR"
PATH="\$VIRTUAL_ENV/bin:\$PATH"
export VIRTUAL_ENV PATH
ACTIVATE
ln -s "/definitely/missing/python3.12" "$VENV_DIR/bin/python3.12"
ln -s "python3.12" "$VENV_DIR/bin/python3"
ln -s "python3.12" "$VENV_DIR/bin/python"
cat >"$VENV_DIR/pyvenv.cfg" <<CFG
home = /definitely/missing
include-system-site-packages = false
version = 3.12.0
CFG

PORT="$(python3 - <<'PY'
import socket

with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
)"

OMNIVOICE_APP_SUPPORT_DIR="$APP_SUPPORT_DIR" \
OMNIVOICE_INSTALL_ASR=0 \
OMNIVOICE_ENGINE_PORT="$PORT" \
  "$ENGINE_DIR/run-engine-bundled.sh" >"$TMP_DIR/engine.log" 2>&1 &
SERVER_PID="$!"

for _ in {1..160}; do
  if curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
    "$VENV_DIR/bin/python" - <<'PY'
import sys

assert sys.version_info >= (3, 12), sys.version
PY
    exit 0
  fi

  if ! kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    echo "bundled engine exited before becoming healthy" >&2
    cat "$TMP_DIR/engine.log" >&2
    exit 1
  fi

  sleep 0.25
done

echo "bundled engine did not become healthy" >&2
cat "$TMP_DIR/engine.log" >&2
exit 1
