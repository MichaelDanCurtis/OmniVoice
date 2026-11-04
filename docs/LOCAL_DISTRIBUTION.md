# OmniSpeak Local Distribution

## Build

Create the V3 local DMG:

```bash
./script/build_and_run.sh --dmg
```

The output is:

- `dist/OmniSpeak.app`
- `dist/OmniSpeak.dmg`

## What Is Bundled

The app bundle includes:

- the Swift macOS app
- the app icon
- the local FastAPI engine source
- a bundled engine launcher at `Contents/Resources/Engine/run-engine-bundled.sh`
- a bundled Python runtime at `Contents/Resources/Python`
- a bundled Python wheelhouse for core, ASR, Parakeet MLX, Whisper MLX, and MLX diarization runtime packages
- lightweight support docs and Raycast script-command integration files

On first launch, if no engine is already running at `http://127.0.0.1:8765`, the app starts the bundled launcher. That launcher creates a virtual environment and installs the engine under:

`~/Library/Application Support/OmniSpeak`

Pre-rename OmniVoice installs keep using `~/Library/Application Support/OmniVoice` when that folder already exists.

The launcher installs normal runtime packages from the bundled wheelhouse by default, so users do not need a system Python installation for the packaged app.

Models are not bundled. They are downloaded locally from Hugging Face through the app settings or engine dashboard and stored under Application Support by default.

Canary-Qwen remains an advanced optional runtime because its NeMo dependency is sourced separately from NVIDIA. The normal packaged runtime includes the local engine, Parakeet MLX, Whisper MLX, translation support plumbing, and MLX diarization package dependencies; Canary can still be enabled from the app when that runtime is available.

## Requirements

- macOS 14+
- Network access for Hugging Face model downloads
- Microphone permission
- Accessibility permission for inserting text into other apps

## Signing Status

The current DMG is locally signed for development with the generated local development identity. That is enough for local testing on this machine and for handoff to trusted testers who explicitly accept the local build.

Public distribution still requires:

- Developer ID Application signing
- hardened runtime review
- notarization with Apple
- stapling the notarization ticket to the DMG

Set `OMNIVOICE_CODESIGN_IDENTITY` to a Developer ID Application identity before building a public distribution candidate.

## Verification

Run:

```bash
swift test
engine/.venv/bin/python -m pytest engine/tests
./script/build_and_run.sh --dmg
./script/build_and_run.sh --verify
/usr/bin/codesign --verify --deep --strict --verbose=2 dist/OmniSpeak.app
/usr/bin/hdiutil verify dist/OmniSpeak.dmg
```

For V3 release candidates, also verify the app version in the bundle:

```bash
/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' dist/OmniSpeak.app/Contents/Info.plist
```
