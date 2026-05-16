# OmniVoice

OmniVoice is a local-first macOS dictation app inspired by the push-to-talk workflow of Wispr Flow.

Hold a configured hotkey, speak, see live captions while the app listens, then release the hotkey to insert cleaned text wherever the cursor was active.

## v1 Scope

- Native macOS menu bar app
- Configurable push-to-talk and style hotkeys
- Microphone picker
- Draggable live caption overlay
- Local FastAPI engine
- Parakeet TDT provider support
- Canary-Qwen-2.5B provider slot
- Hugging Face model download and update checks
- Grammar cleanup, correction handling, quote handling, and punctuation
- Personal dictionary casing preservation
- Command mode for safe app-opening commands
- Selection rewrite MVP
- Engine dashboard with health, logs, transcripts, model controls, and export links
- Raycast script-command integration
- Local development DMG build

## Planned Next

The next major feature is live page streaming: while the user speaks, OmniVoice will insert a provisional transcript into the active text field, replace that provisional draft as ASR hypotheses improve, then swap it for the cleaned final text on hotkey release.

## Requirements

- macOS 14+
- Python 3.12 or newer
- Microphone permission
- Accessibility permission
- Network access for first-run dependency installation and Hugging Face model downloads

## Build

```bash
swift test
engine/.venv/bin/python -m pytest engine/tests
./script/build_and_run.sh --dmg
```

The local DMG is written to:

`dist/OmniVoice.dmg`

## Engine

The desktop app expects the local engine at:

`http://127.0.0.1:8765`

If the engine is offline, the app starts the bundled engine launcher and creates runtime files under:

`~/Library/Application Support/OmniVoice`

For development, run the engine directly:

```bash
scripts/run-engine.sh
```

## Distribution Status

The current DMG is locally signed for development. Public distribution still requires Developer ID signing and Apple notarization.

See [docs/LOCAL_DISTRIBUTION.md](docs/LOCAL_DISTRIBUTION.md) for details.
