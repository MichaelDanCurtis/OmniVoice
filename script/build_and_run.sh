#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="OmniVoiceApp"
BUNDLE_ID="com.omnivoice.OmniVoiceApp"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENGINE_PID_FILE="$DIST_DIR/engine.pid"

cd "$ROOT_DIR"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

ensure_engine() {
  if curl -fsS http://127.0.0.1:8765/health >/dev/null 2>&1; then
    return
  fi

  mkdir -p "$DIST_DIR"
  if command -v tmux >/dev/null 2>&1; then
    tmux kill-session -t omnivoice-engine >/dev/null 2>&1 || true
    tmux new-session -d -s omnivoice-engine "cd \"$ROOT_DIR\" && OMNIVOICE_INSTALL_ASR=\"${OMNIVOICE_INSTALL_ASR:-1}\" scripts/run-engine.sh >>\"$DIST_DIR/engine.log\" 2>&1"
    echo "tmux:omnivoice-engine" >"$ENGINE_PID_FILE"
  else
    nohup env OMNIVOICE_INSTALL_ASR="${OMNIVOICE_INSTALL_ASR:-1}" "$ROOT_DIR/scripts/run-engine.sh" >"$DIST_DIR/engine.log" 2>&1 &
    echo "$!" >"$ENGINE_PID_FILE"
  fi

  for _ in {1..120}; do
    if curl -fsS http://127.0.0.1:8765/health >/dev/null 2>&1; then
      return
    fi
    sleep 0.5
  done

  echo "local engine did not become ready; see $DIST_DIR/engine.log" >&2
  return 1
}

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>OmniVoice</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>OmniVoice uses the microphone for push-to-talk dictation.</string>
</dict>
</plist>
PLIST

open_app() {
  ensure_engine
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
