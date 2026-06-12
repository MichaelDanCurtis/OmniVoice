# OmniVoice (Windows)

Local-first Windows dictation app — hold a hotkey, speak, release to insert cleaned text at the cursor.

This project is **fully self-contained** under `OmniVoice_win/`. The sibling `OmniVoice_mac/` folder in the workspace is reference-only and is not required at runtime.

## Architecture

| Layer | Technology |
|-------|------------|
| Desktop shell | C# / .NET 10 + WPF (system tray, overlay, global hotkeys, UI Automation insertion) |
| Speech engine | Python FastAPI (`engine/`) — reused from the macOS version, runs on `http://127.0.0.1:8765` |

## Requirements

- Windows 10/11
- .NET 10 SDK (to build)
- Python 3.12+ (for the local ASR engine)
- Microphone access

## Default hotkeys

- **Dictation:** hold `Ctrl+Alt+Space`
- **Cycle style:** `Ctrl+Alt+S`

## Build

```powershell
cd OmniVoice_win
dotnet build
dotnet test
```

Publish a standalone app:

```powershell
dotnet publish src/OmniVoice.App/OmniVoice.App.csproj -c Release -r win-x64 --self-contained
```

## Run the engine (development)

```powershell
.\scripts\run-engine.ps1
```

Runtime data is stored under `%LOCALAPPDATA%\OmniVoice\`.

## Features ported

- Push-to-talk dictation with live caption overlay
- Local FastAPI engine with streaming ASR WebSocket
- Grammar cleanup, personal dictionary, style profiles
- Context-aware cleanup (terminal/code → raw, Outlook → professional, etc.)
- Command mode (`Command, open …`, `Ask Claude, …`) with Windows app resolution
- Selection rewrite MVP
- Live translation on insert (OpenAI-compatible endpoint)
- AI handoff with pending-retry UI, secure API key storage (DPAPI on Windows)
- Engine dashboard at `http://127.0.0.1:8765`
- Model download controls (Parakeet TDT, Canary Qwen)

## Project layout

```
OmniVoice_win/
  engine/                 Python ASR + cleanup engine
  scripts/                Windows engine launcher
  src/
    OmniVoice.Core/       Shared models + engine client
    OmniVoice.App/        WPF tray application
  tests/
```