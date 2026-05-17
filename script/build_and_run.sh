#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="OmniVoiceApp"
APP_DISPLAY_NAME="OmniVoice"
BUNDLE_ID="com.omnivoice.OmniVoiceApp"
MIN_SYSTEM_VERSION="14.0"
APP_VERSION="${OMNIVOICE_APP_VERSION:-0.1.0}"
APP_BUILD="${OMNIVOICE_APP_BUILD:-1}"
DMG_VOLUME_NAME="${OMNIVOICE_DMG_VOLUME_NAME:-OmniVoice}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_DISPLAY_NAME.app"
LEGACY_APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
ENGINE_BUNDLE_DIR="$APP_RESOURCES/Engine"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_SOURCE="$ROOT_DIR/Assets/AppIcon/OmniVoiceIcon.svg"
ICONSET_DIR="$DIST_DIR/OmniVoice.iconset"
ICON_DIST_FILE="$DIST_DIR/OmniVoice.icns"
ICON_BUNDLE_FILE="$APP_RESOURCES/OmniVoice.icns"
DMG_STAGING="$DIST_DIR/dmg-staging"
DMG_PATH="$DIST_DIR/OmniVoice.dmg"
ENGINE_PID_FILE="$DIST_DIR/engine.pid"
LOCAL_CODESIGN_NAME="OmniVoice Local Development"
LOCAL_CODESIGN_DIR="$DIST_DIR/codesign"
LOCAL_CODESIGN_KEYCHAIN="$LOCAL_CODESIGN_DIR/OmniVoiceLocal.keychain-db"
LOCAL_CODESIGN_P12_PASSWORD="omnivoice-local"
CODESIGN_IDENTITY=""

cd "$ROOT_DIR"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

add_local_keychain_to_search_list() {
  local current_keychains=()
  local keychain
  while IFS= read -r keychain; do
    keychain="${keychain#"${keychain%%[![:space:]]*}"}"
    keychain="${keychain%"${keychain##*[![:space:]]}"}"
    keychain="${keychain//\"/}"
    [[ "$keychain" == /* ]] && current_keychains+=("$keychain")
  done < <(/usr/bin/security list-keychains -d user)

  for keychain in "${current_keychains[@]}"; do
    [[ "$keychain" == "$LOCAL_CODESIGN_KEYCHAIN" ]] && return
  done

  /usr/bin/security list-keychains -d user -s "$LOCAL_CODESIGN_KEYCHAIN" "${current_keychains[@]}"
}

engine_session_matches_root() {
  command -v tmux >/dev/null 2>&1 || return 1
  local pane_path
  pane_path="$(tmux display-message -p -t omnivoice-engine:0.0 '#{pane_current_path}' 2>/dev/null || true)"
  [[ "$pane_path" == "$ROOT_DIR" || "$pane_path" == "$ROOT_DIR/engine" ]]
}

ensure_local_codesign_identity() {
  mkdir -p "$LOCAL_CODESIGN_DIR"

  if /usr/bin/security find-identity -v -p codesigning "$LOCAL_CODESIGN_KEYCHAIN" 2>/dev/null | grep -q "$LOCAL_CODESIGN_NAME"; then
    /usr/bin/security unlock-keychain -p "" "$LOCAL_CODESIGN_KEYCHAIN"
    add_local_keychain_to_search_list
    return
  fi

  /usr/bin/security delete-keychain "$LOCAL_CODESIGN_KEYCHAIN" >/dev/null 2>&1 || true
  rm -f \
    "$LOCAL_CODESIGN_KEYCHAIN" \
    "$LOCAL_CODESIGN_DIR/omnivoice.key" \
    "$LOCAL_CODESIGN_DIR/omnivoice.crt" \
    "$LOCAL_CODESIGN_DIR/omnivoice.p12"

  /usr/bin/security create-keychain -p "" "$LOCAL_CODESIGN_KEYCHAIN"
  /usr/bin/security unlock-keychain -p "" "$LOCAL_CODESIGN_KEYCHAIN"
  /usr/bin/security set-keychain-settings -lut 21600 "$LOCAL_CODESIGN_KEYCHAIN"

  /usr/bin/openssl req \
    -newkey rsa:2048 \
    -nodes \
    -x509 \
    -days 3650 \
    -subj "/CN=$LOCAL_CODESIGN_NAME/" \
    -keyout "$LOCAL_CODESIGN_DIR/omnivoice.key" \
    -out "$LOCAL_CODESIGN_DIR/omnivoice.crt" \
    -addext "keyUsage=digitalSignature" \
    -addext "extendedKeyUsage=codeSigning" >/dev/null 2>&1

  /usr/bin/openssl pkcs12 \
    -export \
    -out "$LOCAL_CODESIGN_DIR/omnivoice.p12" \
    -inkey "$LOCAL_CODESIGN_DIR/omnivoice.key" \
    -in "$LOCAL_CODESIGN_DIR/omnivoice.crt" \
    -passout "pass:$LOCAL_CODESIGN_P12_PASSWORD" >/dev/null 2>&1

  /usr/bin/security import \
    "$LOCAL_CODESIGN_DIR/omnivoice.p12" \
    -k "$LOCAL_CODESIGN_KEYCHAIN" \
    -P "$LOCAL_CODESIGN_P12_PASSWORD" \
    -T /usr/bin/codesign >/dev/null
  /usr/bin/security add-trusted-cert \
    -r trustRoot \
    -p codeSign \
    -k "$LOCAL_CODESIGN_KEYCHAIN" \
    "$LOCAL_CODESIGN_DIR/omnivoice.crt" >/dev/null
  /usr/bin/security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "" \
    "$LOCAL_CODESIGN_KEYCHAIN" >/dev/null 2>&1 || true

  add_local_keychain_to_search_list
}

ensure_engine() {
  if curl -fsS http://127.0.0.1:8765/health >/dev/null 2>&1 && engine_session_matches_root; then
    return
  fi

  mkdir -p "$DIST_DIR"
  if command -v tmux >/dev/null 2>&1; then
    tmux kill-session -t omnivoice-engine >/dev/null 2>&1 || true
    tmux new-session -d -s omnivoice-engine "cd \"$ROOT_DIR\" && OMNIVOICE_DESKTOP_APP_PATH=\"$APP_BUNDLE\" OMNIVOICE_MODEL_ROOT=\"${OMNIVOICE_MODEL_ROOT:-$ROOT_DIR/models}\" OMNIVOICE_INSTALL_ASR=\"${OMNIVOICE_INSTALL_ASR:-1}\" scripts/run-engine.sh >>\"$DIST_DIR/engine.log\" 2>&1"
    echo "tmux:omnivoice-engine" >"$ENGINE_PID_FILE"
  else
    nohup env OMNIVOICE_DESKTOP_APP_PATH="$APP_BUNDLE" OMNIVOICE_MODEL_ROOT="${OMNIVOICE_MODEL_ROOT:-$ROOT_DIR/models}" OMNIVOICE_INSTALL_ASR="${OMNIVOICE_INSTALL_ASR:-1}" "$ROOT_DIR/scripts/run-engine.sh" >"$DIST_DIR/engine.log" 2>&1 &
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

build_icon() {
  if [[ ! -f "$ICON_SOURCE" ]]; then
    echo "icon source missing: $ICON_SOURCE" >&2
    return 1
  fi

  local svg_converter
  svg_converter="$(command -v rsvg-convert || true)"
  if [[ -z "$svg_converter" ]]; then
    echo "rsvg-convert is required to build the app icon. Install it with: brew install librsvg" >&2
    return 1
  fi

  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR" "$APP_RESOURCES"

  local icon_entries=(
    "icon_16x16.png:16"
    "icon_16x16@2x.png:32"
    "icon_32x32.png:32"
    "icon_32x32@2x.png:64"
    "icon_128x128.png:128"
    "icon_128x128@2x.png:256"
    "icon_256x256.png:256"
    "icon_256x256@2x.png:512"
    "icon_512x512.png:512"
    "icon_512x512@2x.png:1024"
  )

  local entry
  for entry in "${icon_entries[@]}"; do
    local filename="${entry%%:*}"
    local pixels="${entry##*:}"
    "$svg_converter" -w "$pixels" -h "$pixels" "$ICON_SOURCE" -o "$ICONSET_DIR/$filename"
  done

  /usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$ICON_DIST_FILE"
  cp "$ICON_DIST_FILE" "$ICON_BUNDLE_FILE"
}

bundle_engine() {
  rm -rf "$ENGINE_BUNDLE_DIR"
  mkdir -p "$ENGINE_BUNDLE_DIR"

  cp "$ROOT_DIR/engine/pyproject.toml" "$ENGINE_BUNDLE_DIR/"
  cp -R "$ROOT_DIR/engine/omnivoice_engine" "$ENGINE_BUNDLE_DIR/"
  cp "$ROOT_DIR/scripts/run-bundled-engine.sh" "$ENGINE_BUNDLE_DIR/run-engine-bundled.sh"
  chmod +x "$ENGINE_BUNDLE_DIR/run-engine-bundled.sh"

  find "$ENGINE_BUNDLE_DIR" -name "__pycache__" -type d -prune -exec rm -rf {} +
  find "$ENGINE_BUNDLE_DIR" -name "*.pyc" -type f -delete
  find "$ENGINE_BUNDLE_DIR" -name "*.pyo" -type f -delete
}

resolve_codesign_identity() {
  if [[ -n "${OMNIVOICE_CODESIGN_IDENTITY:-}" ]]; then
    CODESIGN_IDENTITY="$OMNIVOICE_CODESIGN_IDENTITY"
  else
    ensure_local_codesign_identity
    CODESIGN_IDENTITY="$(
      /usr/bin/security find-identity -v -p codesigning "$LOCAL_CODESIGN_KEYCHAIN" \
        | /usr/bin/awk -v name="$LOCAL_CODESIGN_NAME" '$0 ~ name { print $2; exit }'
    )"
    if [[ -z "$CODESIGN_IDENTITY" ]]; then
      echo "local codesign identity was not found in $LOCAL_CODESIGN_KEYCHAIN" >&2
      return 1
    fi
  fi
}

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
if [[ "$LEGACY_APP_BUNDLE" != "$APP_BUNDLE" ]]; then
  rm -rf "$LEGACY_APP_BUNDLE"
fi
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleIconFile</key>
  <string>OmniVoice</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <false/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>OmniVoice uses the microphone for push-to-talk dictation.</string>
</dict>
</plist>
PLIST

build_icon
bundle_engine

xattr -dr com.apple.quarantine "$APP_BUNDLE" >/dev/null 2>&1 || true
resolve_codesign_identity
/usr/bin/codesign --force --deep --sign "$CODESIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP_BUNDLE"

open_app() {
  ensure_engine
  /usr/bin/open -n "$APP_BUNDLE"
}

create_dmg() {
  rm -rf "$DMG_STAGING" "$DMG_PATH"
  mkdir -p "$DMG_STAGING"

  cp -R "$APP_BUNDLE" "$DMG_STAGING/"
  ln -s /Applications "$DMG_STAGING/Applications"

  cat >"$DMG_STAGING/README.txt" <<README
OmniVoice local build

Drag OmniVoice.app to Applications.

This package contains the desktop app and the OmniVoice engine source bundle.

On first launch, the app checks http://127.0.0.1:8765. If the engine is not already running, it starts the bundled engine and creates its Python virtual environment under:

~/Library/Application Support/OmniVoice

Python 3.12 or newer is required. ASR dependencies and Hugging Face models are installed/downloaded locally, not bundled into this DMG.

This build is locally signed for development. Public distribution still needs Developer ID signing and notarization.
README

  /usr/bin/hdiutil create \
    -volname "$DMG_VOLUME_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

  if /usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" "$DMG_PATH"; then
    /usr/bin/codesign --verify --verbose=2 "$DMG_PATH"
  else
    echo "warning: DMG signing failed; app bundle signing still completed" >&2
  fi

  /usr/bin/hdiutil verify "$DMG_PATH"
  echo "created $DMG_PATH"
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
  --dmg|dmg)
    create_dmg
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--dmg]" >&2
    exit 2
    ;;
esac
