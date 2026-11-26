# OmniSpeak

OmniSpeak is a local-first macOS & Windows dictation app built as a private, extensible alternative to Wispr Flow.

Hold a configured hotkey, speak, see live captions while the app listens, then release the hotkey to insert cleaned text wherever the cursor was active. Local dictation is always free and stays on-device.

## Current Scope

- **Native desktop apps**: Swift/SwiftUI macOS menu bar app (`Sources/`) + C#/.NET 10 WPF Windows port (`OmniVoice_win/`)
- **Multi-backend local ASR**:
  - **Parakeet TDT MLX** (`mlx-community/parakeet-tdt-0.6b-v3`) — fast default for English & European languages on Apple Silicon (in-memory PCM decoding, no FFmpeg required)
  - **Qwen3-ASR 1.7B MLX 4-bit** (`mlx-community/Qwen3-ASR-1.7B-4bit`) — high-accuracy multilingual & dialect ASR via `mlx-audio`
  - **Whisper Large v3 Turbo MLX 6-bit** (`mlx-community/whisper-large-v3-turbo-asr-6bit`) — 99-language multilingual ASR
  - **Apple Speech (`SpeechAnalyzer`)** — zero-download built-in native dictation on macOS 26+
  - **Canary-Qwen-2.5B** — optional NVIDIA NeMo high-accuracy English ASR
  - **Windows ONNX/CUDA** — Parakeet TDT, Moonshine Base, and SenseVoice via `sherpa-onnx` (CPU or NVIDIA CUDA)
- **Smart Dictation Cleanup**:
  - Fast rule-based cleanup with `Neutral`, `Concise`, `Professional`, and `Raw` styles, app-context style mapping, spoken punctuation/quotes, and inline self-correction handling
  - Optional **Smart AI Cleanup (LLM)** supporting both **built-in on-device MLX 4-bit models** (`Qwen3 1.7B MLX 4-bit` and `Qwen3 4B Instruct MLX 4-bit` via `mlx-lm`) and any configured Text LLM provider (Ollama, LM Studio, OpenAI, Anthropic, Codex/Copilot OAuth), with automatic fallback to deterministic cleanup
- **Auto-learning Personal Dictionary**: watches post-insertion edits via Accessibility and learns proper nouns, brands, and technical vocabulary automatically with an undoable toast
- **Input & Insertion**:
  - Configurable keyboard and mouse push-to-talk shortcuts, alternate dictation triggers, and transcript cache picker
  - Direct Accessibility insertion with live draft streaming, undo, transient clipboard marking (`org.nspasteboard.TransientType`), and pasteboard restoration for rich composers
  - Selectable recording start/stop cue sounds, microphone picker, and draggable liquid-glass caption overlay
- **Conversation Mode & Diarization**:
  - Two-track mic + system-audio capture for free "Me / Them" diarization with text-based echo suppression
  - Local MLX Sortformer diarization, conversation library, archive sync, transcript export, and handoff to Editor / Ask AI
- **Voice AI & Workspaces**:
  - Spoken keyword bindings (`Ask Claude …`, `Ask Gemini …`, `Ask AI …`) routing to local CLI agents or configured Text LLM providers with streaming overlay bubble (`Insert` / `Copy` / `Dismiss`)
  - Live translation with local TranslateGemma MLX models
  - Editor & Ask AI workspaces, Raycast script-command integration, and local engine dashboard
- **Security & Distribution**:
  - Per-launch 256-bit localhost engine auth token (`X-OmniSpeak-Engine-Token`) plus `Host` / `Origin` guards on HTTP and WebSockets
  - Sparkle auto-update plumbing, Cloudflare Worker entitlement/billing backend (`worker/`), macOS DMG packaging with a bundled Python runtime & wheelhouse, and Windows single-executable packaging

## Requirements

- macOS 14+ (macOS 26+ for native Apple Speech) or Windows 10/11
- Microphone permission
- Accessibility permission (macOS) for direct text insertion and auto-learning corrections
- Network access for Hugging Face model downloads

## Build & Test

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

If the engine is offline, the app starts the bundled engine launcher with a fresh per-launch `OMNIVOICE_ENGINE_TOKEN` and creates runtime files under:

`~/Library/Application Support/OmniSpeak`

Model weights are not bundled; they are downloaded or selected through the app and stored under Application Support by default.

For development, run the engine directly:

```bash
scripts/run-engine.sh
```

## Distribution Status

The current DMG is locally signed for development. Public distribution requires Developer ID signing, hardened-runtime review, Apple notarization, and stapling via `script/sign_and_notarize.sh`.

See [docs/LOCAL_DISTRIBUTION.md](docs/LOCAL_DISTRIBUTION.md) and [docs/V3_RELEASE_CHECKLIST.md](docs/V3_RELEASE_CHECKLIST.md) for details.
