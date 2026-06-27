#!/usr/bin/env bash
#
# Sign OmniVoice.app with a Developer ID Application certificate under the
# hardened runtime, then notarize and staple it (and the DMG) for distribution
# outside the Mac App Store.
#
# OmniVoice cannot ship on the Mac App Store: its core (Accessibility text
# insertion into other apps, global push-to-talk hotkeys, a spawned bundled
# Python engine) is incompatible with the App Sandbox. Developer ID +
# notarization is the correct distribution path.
#
# One-time prerequisites (only the account holder can do these):
#
#   1. Create a "Developer ID Application" certificate in your login keychain:
#        Xcode > Settings > Accounts > (your team) > Manage Certificates >
#        "+" > Developer ID Application
#      Verify:
#        security find-identity -v -p codesigning ~/Library/Keychains/login.keychain-db \
#          | grep "Developer ID Application"
#
#   2. Store notarization credentials as a notarytool keychain profile
#      (using an app-specific password from appleid.apple.com, or an
#      App Store Connect API key):
#        xcrun notarytool store-credentials omnivoice-notary \
#          --apple-id "michaeldancurtis@gmail.com" \
#          --team-id P7R2A675CN \
#          --password "<app-specific-password>"
#
# Usage:
#   script/sign_and_notarize.sh [path/to/OmniVoice.app] [path/to/OmniVoice.dmg]
#
# Env overrides:
#   OMNIVOICE_SIGN_IDENTITY   full identity string (default: auto-detected)
#   OMNIVOICE_NOTARY_PROFILE  notarytool keychain profile (default: omnivoice-notary)
#   OMNIVOICE_TEAM_ID         Apple Team ID (default: P7R2A675CN)
#   OMNIVOICE_SKIP_NOTARIZE   set to 1 to sign + verify only (no upload)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT_DIR/dist/OmniVoice.app}"
DMG="${2:-$ROOT_DIR/dist/OmniVoice.dmg}"
ENTITLEMENTS="$ROOT_DIR/script/OmniVoice.entitlements"
BUNDLE_ID="com.omnivoice.OmniVoiceApp"
TEAM_ID="${OMNIVOICE_TEAM_ID:-P7R2A675CN}"
NOTARY_PROFILE="${OMNIVOICE_NOTARY_PROFILE:-omnivoice-notary}"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[[ -d "$APP" ]] || fail "app bundle not found: $APP (build it first, e.g. ./script/build_and_run.sh --dmg)"
[[ -f "$ENTITLEMENTS" ]] || fail "entitlements not found: $ENTITLEMENTS"

# --- Resolve the Developer ID Application identity -------------------------
# Search the login keychain directly so a corrupted user search list (which
# build_and_run.sh has historically produced) can't hide the certificate.
IDENTITY="${OMNIVOICE_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning "$LOGIN_KEYCHAIN" 2>/dev/null \
    | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
fi
[[ -n "$IDENTITY" ]] || fail "No 'Developer ID Application' identity in $LOGIN_KEYCHAIN.
Create one: Xcode > Settings > Accounts > Manage Certificates > + Developer ID Application."
log "Signing identity: $IDENTITY"

# --- 1. Sign every nested Mach-O, inside-out -------------------------------
log "Signing nested libraries (.dylib/.so)..."
while IFS= read -r lib; do
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$lib"
done < <(find "$APP/Contents" -type f \( -name "*.dylib" -o -name "*.so" \) | sort -r)

log "Signing nested executables (e.g. bundled python3.12) with entitlements..."
while IFS= read -r exe; do
  case "$exe" in "$APP/Contents/MacOS/"*) continue ;; esac   # main exe signed via bundle
  if file "$exe" 2>/dev/null | grep -q "Mach-O"; then
    codesign --force --options runtime --timestamp \
      --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$exe"
  fi
done < <(find "$APP/Contents" -type f -perm +111 ! -name "*.dylib" ! -name "*.so")

# --- 2. Sign the app bundle (main executable) ------------------------------
log "Signing app bundle..."
codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --identifier "$BUNDLE_ID" \
  --sign "$IDENTITY" "$APP"

# --- 3. Verify -------------------------------------------------------------
log "Verifying signature..."
codesign --verify --strict --deep --verbose=2 "$APP"
log "Pre-notarization Gatekeeper check (expect 'rejected' until notarized):"
spctl -a -vvv -t exec "$APP" 2>&1 || true

if [[ "${OMNIVOICE_SKIP_NOTARIZE:-0}" == "1" ]]; then
  log "OMNIVOICE_SKIP_NOTARIZE=1 — signed only, skipping notarization."
  exit 0
fi

# --- 4. Notarize + staple --------------------------------------------------
notarize() {
  local artifact="$1"
  log "Submitting $(basename "$artifact") to Apple notary service (a few minutes)..."
  xcrun notarytool submit "$artifact" --keychain-profile "$NOTARY_PROFILE" --wait
}

# Notarize the app (via zip), then staple the .app itself.
APP_ZIP="$(dirname "$APP")/$(basename "$APP" .app)-notarize.zip"
/usr/bin/ditto -c -k --keepParent "$APP" "$APP_ZIP"
notarize "$APP_ZIP"
log "Stapling app..."
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
rm -f "$APP_ZIP"

# Build the DMG *from the now-stapled app* (correct order), then sign +
# notarize + staple the DMG itself.
log "Building DMG from the notarized app..."
DMG_STAGE_PARENT="$(mktemp -d)"
DMG_STAGE="$DMG_STAGE_PARENT/OmniVoice"
mkdir -p "$DMG_STAGE"
cp -R "$APP" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
mkdir -p "$(dirname "$DMG")"
rm -f "$DMG"
hdiutil create -volname "OmniVoice" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$DMG_STAGE_PARENT"

log "Signing DMG..."
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
notarize "$DMG"
log "Stapling DMG..."
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

log "Done. Final Gatekeeper assessment:"
spctl -a -vvv -t exec "$APP" 2>&1 || true
log "Distribute: $DMG (notarized + stapled)."
