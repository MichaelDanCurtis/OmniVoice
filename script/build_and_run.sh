#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="OmniVoiceApp"
APP_DISPLAY_NAME="OmniVoice"
BUNDLE_ID="com.omnivoice.OmniVoiceApp"
MIN_SYSTEM_VERSION="14.0"
APP_VERSION="${OMNIVOICE_APP_VERSION:-3.0.0}"
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
ENGINE_WHEELHOUSE_DIR="$ENGINE_BUNDLE_DIR/wheelhouse"
PYTHON_RUNTIME_DIR="$APP_RESOURCES/Python"
PYTHON_RUNTIME_VERSION="${OMNIVOICE_PYTHON_RUNTIME_VERSION:-3.12}"
INFO_PLIST="$APP_CONTENTS/Info.plist"
RUN_APP_BUNDLE="${OMNIVOICE_RUN_APP_BUNDLE:-$HOME/Applications/$APP_DISPLAY_NAME.app}"
ICON_SOURCE="$ROOT_DIR/Assets/AppIcon/OmniVoiceIcon.svg"
ICONSET_DIR="$DIST_DIR/OmniVoice.iconset"
ICON_DIST_FILE="$DIST_DIR/OmniVoice.icns"
ICON_BUNDLE_FILE="$APP_RESOURCES/OmniVoice.icns"
DOCS_BUNDLE_DIR="$APP_RESOURCES/Docs"
INTEGRATIONS_BUNDLE_DIR="$APP_RESOURCES/Integrations"
DMG_STAGING="$DIST_DIR/dmg-staging"
DMG_PATH="$DIST_DIR/OmniVoice.dmg"
ENGINE_PID_FILE="$DIST_DIR/engine.pid"
ENGINE_APP_PATH_FILE="$DIST_DIR/engine-app-path"
LOCAL_CODESIGN_NAME="OmniVoice Local Development"
LOCAL_CODESIGN_DIR="$DIST_DIR/codesign"
LOCAL_CODESIGN_KEYCHAIN="$LOCAL_CODESIGN_DIR/OmniVoiceLocal.keychain-db"
LOCAL_CODESIGN_P12_PASSWORD="omnivoice-local"
LOCAL_CODESIGN_TIMEOUT_SECONDS="${OMNIVOICE_CODESIGN_TIMEOUT_SECONDS:-20}"
CODESIGN_IDENTITY=""
CODESIGN_IDENTITY_SOURCE=""
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

cd "$ROOT_DIR"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

add_local_keychain_to_search_list() {
  # Set the user keychain search list to exactly [local-codesign, login],
  # rebuilt from scratch each call. The previous implementation prepended the
  # local keychain to whatever `security list-keychains` returned and re-fed it;
  # with a repo path containing a space ("Main External") and concurrent builds
  # from multiple worktrees, that accumulated/garbled entries and could bury the
  # real login keychain — hiding the Developer ID certificate from codesign.
  # An explicit, fixed two-entry list is idempotent and corruption-proof.
  /usr/bin/security list-keychains -d user -s \
    "$LOCAL_CODESIGN_KEYCHAIN" \
    "$HOME/Library/Keychains/login.keychain-db"
}

run_with_timeout() {
  local timeout_seconds="$1"
  shift

  "$@" &
  local command_pid=$!
  local elapsed=0

  while kill -0 "$command_pid" >/dev/null 2>&1; do
    if [[ "$elapsed" -ge "$timeout_seconds" ]]; then
      kill "$command_pid" >/dev/null 2>&1 || true
      sleep 1
      kill -9 "$command_pid" >/dev/null 2>&1 || true
      wait "$command_pid" >/dev/null 2>&1 || true
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  wait "$command_pid"
}

reset_app_signature_artifacts() {
  rm -rf "$APP_BUNDLE/Contents/_CodeSignature"
  find "$APP_BUNDLE" -name "*.cstemp" -type f -delete 2>/dev/null || true
}

make_bundle_writable_for_rebuild() {
  local bundle="$1"
  if [[ -d "$bundle" ]]; then
    chmod -R u+w "$bundle" >/dev/null 2>&1 || true
  fi
}

engine_session_matches_root() {
  command -v tmux >/dev/null 2>&1 || return 1
  local pane_path
  pane_path="$(tmux display-message -p -t omnivoice-engine:0.0 '#{pane_current_path}' 2>/dev/null || true)"
  [[ "$pane_path" == "$ROOT_DIR" || "$pane_path" == "$ROOT_DIR/engine" ]]
}

engine_session_matches_runtime() {
  engine_session_matches_root || return 1
  [[ "$(cat "$ENGINE_APP_PATH_FILE" 2>/dev/null || true)" == "$RUN_APP_BUNDLE" ]]
}

stop_engine() {
  if command -v tmux >/dev/null 2>&1; then
    tmux kill-session -t omnivoice-engine >/dev/null 2>&1 || true
  fi

  local engine_pid
  engine_pid="$(cat "$ENGINE_PID_FILE" 2>/dev/null || true)"
  if [[ "$engine_pid" =~ ^[0-9]+$ ]]; then
    kill "$engine_pid" >/dev/null 2>&1 || true
  fi

  pkill -f "$ROOT_DIR/engine/.venv/bin/uvicorn omnivoice_engine.main:app --host 127.0.0.1 --port 8765" >/dev/null 2>&1 || true
  pkill -f "Application Support/OmniVoice/engine-venv/bin/uvicorn omnivoice_engine.main:app --host 127.0.0.1 --port 8765" >/dev/null 2>&1 || true
  pkill -f "$ROOT_DIR/scripts/run-engine.sh" >/dev/null 2>&1 || true
  rm -f "$ENGINE_PID_FILE" "$ENGINE_APP_PATH_FILE"
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
  if curl -fsS http://127.0.0.1:8765/health >/dev/null 2>&1 && engine_session_matches_runtime; then
    return
  fi

  mkdir -p "$DIST_DIR"
  if command -v tmux >/dev/null 2>&1; then
    tmux kill-session -t omnivoice-engine >/dev/null 2>&1 || true
    tmux new-session -d -s omnivoice-engine "cd \"$ROOT_DIR\" && OMNIVOICE_DESKTOP_APP_PATH=\"$RUN_APP_BUNDLE\" OMNIVOICE_MODEL_ROOT=\"${OMNIVOICE_MODEL_ROOT:-$ROOT_DIR/models}\" OMNIVOICE_INSTALL_ASR=\"${OMNIVOICE_INSTALL_ASR:-1}\" OMNIVOICE_INSTALL_MLX_DIARIZATION=\"${OMNIVOICE_INSTALL_MLX_DIARIZATION:-1}\" OMNIVOICE_INSTALL_MLX_ASR=\"${OMNIVOICE_INSTALL_MLX_ASR:-1}\" scripts/run-engine.sh >>\"$DIST_DIR/engine.log\" 2>&1"
    echo "tmux:omnivoice-engine" >"$ENGINE_PID_FILE"
  else
    nohup env OMNIVOICE_DESKTOP_APP_PATH="$RUN_APP_BUNDLE" OMNIVOICE_MODEL_ROOT="${OMNIVOICE_MODEL_ROOT:-$ROOT_DIR/models}" OMNIVOICE_INSTALL_ASR="${OMNIVOICE_INSTALL_ASR:-1}" OMNIVOICE_INSTALL_MLX_DIARIZATION="${OMNIVOICE_INSTALL_MLX_DIARIZATION:-1}" OMNIVOICE_INSTALL_MLX_ASR="${OMNIVOICE_INSTALL_MLX_ASR:-1}" "$ROOT_DIR/scripts/run-engine.sh" >"$DIST_DIR/engine.log" 2>&1 &
    echo "$!" >"$ENGINE_PID_FILE"
  fi
  echo "$RUN_APP_BUNDLE" >"$ENGINE_APP_PATH_FILE"

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

python_runtime_source_from_executable() {
  "$1" <<'PY'
import sys
print(sys.base_prefix)
PY
}

python_runtime_bin() {
  local runtime_root="$1"
  if [[ -x "$runtime_root/bin/python$PYTHON_RUNTIME_VERSION" ]]; then
    echo "$runtime_root/bin/python$PYTHON_RUNTIME_VERSION"
    return
  fi
  if [[ -x "$runtime_root/bin/python3" ]]; then
    echo "$runtime_root/bin/python3"
    return
  fi
  if [[ -x "$runtime_root/bin/python" ]]; then
    echo "$runtime_root/bin/python"
  fi
}

python_runtime_is_usable() {
  local runtime_root="$1"
  local python_bin
  python_bin="$(python_runtime_bin "$runtime_root")"
  [[ -n "$python_bin" ]] || return 1
  "$python_bin" - "$PYTHON_RUNTIME_VERSION" <<'PY' >/dev/null 2>&1
import pathlib
import sys

minimum = tuple(int(part) for part in sys.argv[1].split("."))
raise SystemExit(0 if sys.version_info[:2] >= minimum and pathlib.Path(sys.executable).exists() else 1)
PY
}

resolve_python_runtime_source() {
  local source="${OMNIVOICE_PYTHON_RUNTIME_SOURCE:-}"
  local python_bin

  if [[ -n "$source" ]]; then
    source="${source/#\~/$HOME}"
    if python_runtime_is_usable "$source"; then
      echo "$source"
      return
    fi
    echo "OMNIVOICE_PYTHON_RUNTIME_SOURCE is not a usable Python $PYTHON_RUNTIME_VERSION runtime: $source" >&2
    return 1
  fi

  if command -v uv >/dev/null 2>&1; then
    uv python install "$PYTHON_RUNTIME_VERSION" >/dev/null
    python_bin="$(uv python find "$PYTHON_RUNTIME_VERSION")"
    source="$(python_runtime_source_from_executable "$python_bin")"
    if python_runtime_is_usable "$source"; then
      echo "$source"
      return
    fi
  fi

  for python_bin in \
    "$ROOT_DIR/engine/.venv/bin/python" \
    python3.12 \
    /opt/homebrew/bin/python3.12 \
    /opt/homebrew/opt/python@3.12/bin/python3.12 \
    /usr/local/bin/python3.12 \
    /usr/local/opt/python@3.12/bin/python3.12; do
    if [[ "$python_bin" == */* ]]; then
      [[ -x "$python_bin" ]] || continue
    elif command -v "$python_bin" >/dev/null 2>&1; then
      python_bin="$(command -v "$python_bin")"
    else
      continue
    fi

    source="$(python_runtime_source_from_executable "$python_bin")"
    if python_runtime_is_usable "$source"; then
      echo "$source"
      return
    fi
  done

  echo "Could not find a Python $PYTHON_RUNTIME_VERSION runtime to embed. Install uv or set OMNIVOICE_PYTHON_RUNTIME_SOURCE." >&2
  return 1
}

bundle_python_runtime() {
  local source
  source="$(resolve_python_runtime_source)"

  rm -rf "$PYTHON_RUNTIME_DIR"
  mkdir -p "$PYTHON_RUNTIME_DIR"

  /usr/bin/rsync -a --delete \
    --exclude "__pycache__" \
    --exclude "*.pyc" \
    --exclude "*.pyo" \
    --exclude "test" \
    --exclude "tests" \
    "$source/" "$PYTHON_RUNTIME_DIR/"

  local bundled_python
  bundled_python="$(python_runtime_bin "$PYTHON_RUNTIME_DIR")"
  if [[ -z "$bundled_python" ]]; then
    echo "Embedded Python runtime copy did not produce an executable in $PYTHON_RUNTIME_DIR/bin" >&2
    return 1
  fi

  xattr -dr com.apple.quarantine "$PYTHON_RUNTIME_DIR" >/dev/null 2>&1 || true
  local pycache_dir
  pycache_dir="$(mktemp -d /tmp/omnivoice-python-cache.XXXXXX)"
  PYTHONDONTWRITEBYTECODE=1 PYTHONPYCACHEPREFIX="$pycache_dir" "$bundled_python" - <<'PY'
import sys
raise SystemExit(0 if sys.version_info[:2] >= (3, 12) else 1)
PY
  rm -rf "$pycache_dir"
  find "$PYTHON_RUNTIME_DIR" -name "__pycache__" -type d -prune -exec rm -rf {} +
}

protect_python_runtime() {
  find "$PYTHON_RUNTIME_DIR" -name "__pycache__" -type d -prune -exec rm -rf {} +
  chmod -R a-w "$PYTHON_RUNTIME_DIR"
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

bundle_engine_wheelhouse() {
  local bundled_python
  bundled_python="$(python_runtime_bin "$PYTHON_RUNTIME_DIR")"
  if [[ -z "$bundled_python" ]]; then
    echo "Cannot bundle engine wheelhouse without embedded Python." >&2
    return 1
  fi

  rm -rf "$ENGINE_WHEELHOUSE_DIR"
  mkdir -p "$ENGINE_WHEELHOUSE_DIR"

  local requirements_file
  requirements_file="$(mktemp /tmp/omnivoice-engine-requirements.XXXXXX)"
  "$bundled_python" - "$ROOT_DIR/engine/pyproject.toml" "$requirements_file" <<'PY'
import pathlib
import sys
import tomllib

pyproject_path = pathlib.Path(sys.argv[1])
requirements_path = pathlib.Path(sys.argv[2])
project = tomllib.loads(pyproject_path.read_text())
dependencies = [
    "setuptools>=69",
    "wheel>=0.43",
    *project["project"].get("dependencies", []),
]
optional = project["project"].get("optional-dependencies", {})
for extra in ("asr", "mlx-asr", "mlx-diarization"):
    dependencies.extend(optional.get(extra, []))

seen: set[str] = set()
deduped: list[str] = []
for dependency in dependencies:
    if dependency not in seen:
        seen.add(dependency)
        deduped.append(dependency)

requirements_path.write_text("\n".join(deduped) + "\n")
PY

  "$bundled_python" -m ensurepip --upgrade >/dev/null 2>&1 || true
  "$bundled_python" -m pip download --prefer-binary --dest "$ENGINE_WHEELHOUSE_DIR" --requirement "$requirements_file"
  rm -f "$requirements_file"

  find "$ENGINE_WHEELHOUSE_DIR" -name "__pycache__" -type d -prune -exec rm -rf {} +
  find "$ENGINE_WHEELHOUSE_DIR" -name "*.pyc" -type f -delete
  find "$ENGINE_WHEELHOUSE_DIR" -name "*.pyo" -type f -delete
}

bundle_support_files() {
  rm -rf "$DOCS_BUNDLE_DIR" "$INTEGRATIONS_BUNDLE_DIR"
  mkdir -p "$DOCS_BUNDLE_DIR" "$INTEGRATIONS_BUNDLE_DIR"

  cp "$ROOT_DIR/README.md" "$DOCS_BUNDLE_DIR/"
  cp "$ROOT_DIR/docs/LOCAL_DISTRIBUTION.md" "$DOCS_BUNDLE_DIR/"
  cp "$ROOT_DIR/docs/OMNIVOICE_QUICK_REFERENCE.md" "$DOCS_BUNDLE_DIR/"
  cp "$ROOT_DIR/docs/INTEGRATIONS.md" "$DOCS_BUNDLE_DIR/"

  if [[ -d "$ROOT_DIR/integrations/raycast" ]]; then
    mkdir -p "$INTEGRATIONS_BUNDLE_DIR/raycast"
    /usr/bin/rsync -a --delete \
      --exclude ".DS_Store" \
      "$ROOT_DIR/integrations/raycast/" "$INTEGRATIONS_BUNDLE_DIR/raycast/"
  fi
}

resolve_codesign_identity() {
  if [[ -n "${OMNIVOICE_CODESIGN_IDENTITY:-}" ]]; then
    CODESIGN_IDENTITY="$OMNIVOICE_CODESIGN_IDENTITY"
    CODESIGN_IDENTITY_SOURCE="env"
    return
  fi

  resolve_local_codesign_identity
}

resolve_local_codesign_identity() {
  ensure_local_codesign_identity
  CODESIGN_IDENTITY="$(
    /usr/bin/security find-identity -v -p codesigning "$LOCAL_CODESIGN_KEYCHAIN" \
      | /usr/bin/awk -v name="$LOCAL_CODESIGN_NAME" '$0 ~ name { print $2; exit }'
  )"
  if [[ -z "$CODESIGN_IDENTITY" ]]; then
    echo "local codesign identity was not found in $LOCAL_CODESIGN_KEYCHAIN" >&2
    return 1
  fi
  CODESIGN_IDENTITY_SOURCE="local"
}

sign_app_bundle() {
  resolve_codesign_identity

  reset_app_signature_artifacts
  if run_with_timeout "$LOCAL_CODESIGN_TIMEOUT_SECONDS" /usr/bin/codesign --force --deep --sign "$CODESIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP_BUNDLE"; then
    return
  fi

  if [[ -n "${OMNIVOICE_CODESIGN_IDENTITY:-}" ]]; then
    echo "codesign failed for OMNIVOICE_CODESIGN_IDENTITY=$OMNIVOICE_CODESIGN_IDENTITY" >&2
    return 1
  fi

  echo "codesign failed with project-local identity $CODESIGN_IDENTITY" >&2
  return 1
}

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

make_bundle_writable_for_rebuild "$APP_BUNDLE"
rm -rf "$APP_BUNDLE"
if [[ "$LEGACY_APP_BUNDLE" != "$APP_BUNDLE" ]]; then
  make_bundle_writable_for_rebuild "$LEGACY_APP_BUNDLE"
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
  <key>SUFeedURL</key>
  <string>https://github.com/MichaelDanCurtis/OmniVoice/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key>
  <string>weUAjU02WUhH7OGMPaQTT1Nwn4s+2cA496LzavhpTiE=</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUScheduledCheckInterval</key>
  <integer>86400</integer>
</dict>
</plist>
PLIST

bundle_sparkle() {
  # Embed Sparkle.framework (auto-updater) into the app bundle and make the
  # executable resolve it at @executable_path/../Frameworks. Required on EVERY
  # build — without it dyld can't satisfy @rpath/Sparkle.framework and the app
  # crashes on launch.
  local src
  src="$(swift build --show-bin-path)/Sparkle.framework"
  if [[ ! -d "$src" ]]; then
    echo "Sparkle.framework not found at $src; build the package first." >&2
    return 1
  fi
  mkdir -p "$APP_CONTENTS/Frameworks"
  rm -rf "$APP_CONTENTS/Frameworks/Sparkle.framework"
  cp -R "$src" "$APP_CONTENTS/Frameworks/Sparkle.framework"
  # SwiftPM links with @loader_path only; add the Frameworks rpath if absent.
  if ! /usr/bin/otool -l "$APP_BINARY" | grep -q "@executable_path/../Frameworks"; then
    /usr/bin/install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY" 2>/dev/null || true
  fi
}

build_icon
bundle_python_runtime
bundle_engine
bundle_engine_wheelhouse
bundle_support_files
bundle_sparkle

xattr -dr com.apple.quarantine "$APP_BUNDLE" >/dev/null 2>&1 || true
protect_python_runtime
sign_app_bundle
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

unregister_stale_launch_services() {
  local stale_bundle
  for stale_bundle in "$APP_BUNDLE" "$LEGACY_APP_BUNDLE" "$DMG_STAGING/$APP_DISPLAY_NAME.app"; do
    if [[ "$stale_bundle" != "$RUN_APP_BUNDLE" ]]; then
      "$LSREGISTER" -u "$stale_bundle" >/dev/null 2>&1 || true
    fi
  done
}

register_launch_services() {
  [[ -x "$LSREGISTER" ]] || return

  unregister_stale_launch_services
  "$LSREGISTER" -f "$RUN_APP_BUNDLE" >/dev/null 2>&1 || true
  unregister_stale_launch_services
  "$LSREGISTER" -f "$RUN_APP_BUNDLE" >/dev/null 2>&1 || true
}

install_run_bundle() {
  if [[ "$RUN_APP_BUNDLE" != "$APP_BUNDLE" ]]; then
    mkdir -p "$(dirname "$RUN_APP_BUNDLE")"
    make_bundle_writable_for_rebuild "$RUN_APP_BUNDLE"
    rm -rf "$RUN_APP_BUNDLE"
    cp -R "$APP_BUNDLE" "$RUN_APP_BUNDLE"
    make_bundle_writable_for_rebuild "$APP_BUNDLE"
    rm -rf "$APP_BUNDLE"
  fi

  xattr -dr com.apple.quarantine "$RUN_APP_BUNDLE" >/dev/null 2>&1 || true
  /usr/bin/codesign --verify --deep --strict "$RUN_APP_BUNDLE"
  register_launch_services
}

open_app() {
  install_run_bundle
  if [[ "${OMNIVOICE_RESTART_ENGINE:-1}" != "0" ]]; then
    stop_engine
  fi
  ensure_engine
  /usr/bin/open -n "$RUN_APP_BUNDLE"
}

create_dmg() {
  make_bundle_writable_for_rebuild "$DMG_STAGING/$APP_DISPLAY_NAME.app"
  chmod -R u+w "$DMG_STAGING" >/dev/null 2>&1 || true
  rm -rf "$DMG_STAGING" "$DMG_PATH"
  mkdir -p "$DMG_STAGING"

  cp -R "$APP_BUNDLE" "$DMG_STAGING/"
  ln -s /Applications "$DMG_STAGING/Applications"

  cat >"$DMG_STAGING/README.txt" <<README
OmniVoice local build

Drag OmniVoice.app to Applications.

This package contains the desktop app, the OmniVoice engine source bundle, and an embedded Python runtime.

On first launch, the app checks http://127.0.0.1:8765. If the engine is not already running, it starts the bundled engine and creates its Python virtual environment under:

~/Library/Application Support/OmniVoice

OmniVoice includes its own Python runtime and a bundled Python wheelhouse for normal engine dependencies. Hugging Face model weights are downloaded locally and are not bundled into this DMG.

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
