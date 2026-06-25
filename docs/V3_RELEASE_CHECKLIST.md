# OmniVoice V3 Release Checklist

## Required Before Tagging

- `swift test`
- `engine/.venv/bin/python -m pytest engine/tests`
- `git diff --check`
- `./script/build_and_run.sh --verify`
- `curl -fsS http://127.0.0.1:8765/health`

## Required For Local DMG

- `./script/build_and_run.sh --dmg`
- `/usr/bin/codesign --verify --deep --strict --verbose=2 dist/OmniVoice.app`
- `/usr/bin/hdiutil verify dist/OmniVoice.dmg`
- `/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' dist/OmniVoice.app/Contents/Info.plist`

## Required For Public Distribution

- Build with a Developer ID Application certificate through `OMNIVOICE_CODESIGN_IDENTITY`.
- Confirm hardened runtime and entitlement requirements.
- Submit the DMG to Apple notarization.
- Staple the notarization ticket.
- Re-run Gatekeeper validation on a clean machine.

## Local Runtime Packaging

The local DMG bundles the Swift app, engine source launcher, embedded Python runtime, and a Python wheelhouse for the normal core/ASR/MLX runtime packages. First launch creates the engine venv under `~/Library/Application Support/OmniVoice` from bundled resources.

Model weights are still external by design. Users download or select models through the app or engine dashboard.
