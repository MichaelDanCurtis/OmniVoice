# OmniVoice

OmniVoice is a local-first macOS dictation app inspired by the push-to-talk workflow of Wispr Flow.

Hold a configured hotkey, speak, see live captions while the app listens, then release the hotkey to insert cleaned text wherever the cursor was active.

## v2 Scope

- Native macOS menu bar app
- Configurable push-to-talk, style, and hot-menu hotkeys
- Microphone picker
- Draggable liquid-glass caption overlay
- Local FastAPI engine
- Parakeet TDT MLX provider support
- Whisper Large v3 Turbo MLX 6-bit multilingual ASR support
- Canary-Qwen-2.5B advanced English ASR provider support when the optional NeMo runtime is installed
- Hugging Face model download, update, and delete controls
- Hugging Face token validation for gated model access
- Grammar cleanup, correction handling, quote handling, and punctuation
- Personal dictionary casing preservation
- Command mode for safe app-opening commands
- Live translation with local translation model configuration
- Conversation recording with local diarization support
- Conversation library, archive sync, transcript export, and conversation-to-editor/AI handoff
- Editor and Ask AI workspaces with provider/model session settings
- Configurable text LLM providers, custom headers, web-search toggle, and MCP server configuration
- Liquid-glass themes, custom accent color, waveform modes, and Help capability demos
- Engine dashboard with health, logs, transcripts, model controls, and export links
- Raycast script-command integration
- Local development DMG build

## Planned Next

The next major track is deeper V3 automation: broader multilingual polish, stronger local diarization options, richer MCP-backed Ask AI actions, memory, and production signing/notarization.

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

The current DMG is locally signed for development. Public distribution still requires Developer ID signing, hardened-runtime review, Apple notarization, and stapling.

See [docs/LOCAL_DISTRIBUTION.md](docs/LOCAL_DISTRIBUTION.md) for details.
