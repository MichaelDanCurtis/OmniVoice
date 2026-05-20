# OmniVoice Local Distribution

## Build

Create the V2 local DMG:

```bash
./script/build_and_run.sh --dmg
```

The output is:

- `dist/OmniVoice.app`
- `dist/OmniVoice.dmg`

## What Is Bundled

The app bundle includes:

- the Swift macOS app
- the app icon
- the local FastAPI engine source
- a bundled engine launcher at `Contents/Resources/Engine/run-engine-bundled.sh`

The DMG does not bundle Python, ASR dependencies, or model files. On first launch, if no engine is already running at `http://127.0.0.1:8765`, the app starts the bundled launcher. That launcher creates a virtual environment and installs the engine under:

`~/Library/Application Support/OmniVoice`

Models are downloaded locally from Hugging Face through the app settings or engine dashboard.

## Requirements

- macOS 14+
- Python 3.12 or newer
- Network access for first-run dependency installation and Hugging Face model downloads
- Microphone permission
- Accessibility permission for inserting text into other apps

## Signing Status

The current DMG is locally signed for development with the generated `OmniVoice Local Development` identity. That is enough for local testing on this machine and for handoff to trusted testers who explicitly accept the local build.

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
/usr/bin/codesign --verify --deep --strict --verbose=2 dist/OmniVoice.app
/usr/bin/hdiutil verify dist/OmniVoice.dmg
```

For V2 release candidates, also verify the app version in the bundle:

```bash
/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' dist/OmniVoice.app/Contents/Info.plist
```
