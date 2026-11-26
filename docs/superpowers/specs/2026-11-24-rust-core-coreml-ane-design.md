# OmniSpeak v4 Architecture — Shared Rust Core + CoreML ANE + Native UIs

Date: 2026-11-24

## Goal

Eliminate the ~300 MB bundled Python runtime, wheelhouse, first-run venv build, and diverging macOS/Windows engines while keeping 100% native desktop experiences (SwiftUI/AppKit on macOS, WPF/Win32 on Windows) and leveraging the Apple Neural Engine (ANE) for ultra-low-latency, cool, battery-friendly speech recognition and diarization.

## Architecture Split

```
┌──────────────────────────────────┐   ┌──────────────────────────────────┐
│  macOS Native Shell (Swift)      │   │  Windows Native Shell (C#/WPF)   │
│  • SwiftUI UI + NSPanel overlays │   │  • WPF UI + floating overlay     │
│  • Hotkeys · AX Insertion · Tray │   │  • Hotkeys · UIA · Tray · DPAPI  │
│  • CorrectionWatcher · Sparkle   │   │  • WASAPI Loopback               │
│  • ScreenCaptureKit              │   └────────────────┬─────────────────┘
│  • FluidAudio CoreML ANE:        │                    │
│    - Parakeet TDT v3 (ANE)       │                    │
│    - Qwen3-ASR (ANE)             │                    │
│    - Sortformer Diarizer (ANE)   │                    │
│  • Apple SpeechAnalyzer (macOS26)│                    │
└─────────────────┬────────────────┘                    │
                  │ HTTP/WS (drop-in) -> UniFFI (in-process)
┌─────────────────▼─────────────────────────────────────▼─────────────────┐
│  core-rs/ (Single Shared Rust Workspace — Zero Python)                  │
│  • omnivoice-core (lib):                                                │
│    - cleanup (rule-based + LLM cleanup prompt/sanitizer)                │
│    - dictionary & correction_classifier                                 │
│    - echo_suppression (two-track mic-vs-system)                         │
│    - security (X-OmniSpeak-Engine-Token, Host/Origin DNS-rebinding)     │
│    - store (SQLite transcripts, events, conversations)                  │
│    - llm (OpenAI-compatible / Ollama / Anthropic / OAuth clients)       │
│    - entitlement (offline-grace gate)                                   │
│  • omnivoice-engine (bin):                                              │
│    - Axum localhost HTTP + WS drop-in engine on 127.0.0.1:8765          │
│    - Optional native inference features (sherpa-onnx, llama.cpp)        │
└─────────────────────────────────────────────────────────────────────────┘
```

## Phased Rollout

1. **Phase 1 (This milestone — Foundation + macOS ANE):**
   - Create `core-rs/` Rust workspace (`omnivoice-core` library + `omnivoice-engine` axum server binary) with full unit tests and drop-in `/health`, `/cleanup`, `/api/transcripts`, `/api/events`, `/api/conversations`, `/api/status`, `/api/ai/handoff`, and localhost token/Host/Origin security.
   - Integrate `FluidAudio` into the macOS Swift package so **Parakeet TDT v3 CoreML (ANE)** and **Sortformer CoreML (ANE)** run natively on Apple Silicon without starting Python at all.
2. **Phase 2 (Local LLM + Cross-platform ONNX in Rust):**
   - Wire `llama-cpp-2` (Metal on macOS, CUDA/Vulkan/CPU on Windows) for on-device Qwen3 1.7B/4B cleanup & TranslateGemma GGUF, and `sherpa-onnx` for Windows/CPU/CUDA ASR (Parakeet TDT v3, Qwen3-ASR, Moonshine, SenseVoice).
3. **Phase 3 (Direct FFI + Thin Native UIs):**
   - Expose `omnivoice-core` via UniFFI (Swift & C#), split `AppModel.swift` / `SettingsView.swift` into focused view models, redesign the macOS & Windows UIs cleanly on top of the shared core, and retire `engine/` and `OmniVoice_win/engine/`.
