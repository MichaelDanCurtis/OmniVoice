# OmniSpeak

OmniSpeak is a local-first macOS dictation app inspired by the push-to-talk workflow of Wispr Flow.

Hold a configured hotkey, speak, see live captions while the app listens, then release the hotkey to insert cleaned text wherever the cursor was active.

## v3 Scope

- Native macOS menu bar app
- Configurable keyboard and mouse push-to-talk shortcuts, including alternate dictation triggers
- Transcript cache picker with keyboard and mouse shortcuts
- Selectable recording start/stop cue sounds
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
- Local development DMG with embedded Python runtime, bundled engine source, and bundled Python wheelhouse

## Planned Next

The next major track is production distribution polish: Developer ID signing, notarization, a cleaner first-run installer experience, richer MCP-backed Ask AI actions, and long-term memory.

## Repository Layout

The macOS app remains at the repository root. The Windows port lives under [`Win/`](Win/), with its own `.NET/WPF` app, C# core tests, PowerShell engine launcher, and copied Python engine.

## Requirements

- macOS 14+
- Microphone permission
- Accessibility permission
- Network access for Hugging Face model downloads

## Build

```bash
swift test
engine/.venv/bin/python -m pytest engine/tests
./script/build_and_run.sh --dmg
```

The local DMG is written to:

`dist/OmniSpeak.dmg`

## Engine

The desktop app expects the local engine at:

`http://127.0.0.1:8765`

If the engine is offline, the app starts the bundled engine launcher and creates runtime files under:

`~/Library/Application Support/OmniSpeak`

Pre-rename OmniVoice installs continue to use `~/Library/Application Support/OmniVoice` when that folder already exists, so downloaded models and settings stay available.

The distributable app includes a bundled Python runtime, the local engine source, and a bundled Python wheelhouse for the core/ASR/MLX runtime packages. Model weights are not bundled; they are downloaded or selected through the app and stored under Application Support by default.

For development, run the engine directly:

```bash
scripts/run-engine.sh
```

## Distribution Status

The current DMG is locally signed for development. Public distribution still requires Developer ID signing, hardened-runtime review, Apple notarization, and stapling.

See [docs/LOCAL_DISTRIBUTION.md](docs/LOCAL_DISTRIBUTION.md) and [docs/V3_RELEASE_NOTES.md](docs/V3_RELEASE_NOTES.md) for details.
