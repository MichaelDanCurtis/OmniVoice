# OmniSpeak (Windows)

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

Runtime data is stored under `%LOCALAPPDATA%\OmniSpeak\`.

## Package as one executable

```powershell
.\scripts\package-windows.ps1
```

Produces `dist\OmniSpeak.exe` — a single self-contained file. It embeds the
PyInstaller-frozen Python engine (`omnispeak-engine.exe`); .NET extracts it next to
the app on first run and `EngineLauncherLocator` launches it directly — no Python,
no venv, no scripts on the user's machine. Speech models download to
`%LOCALAPPDATA%\OmniSpeak\models\` on first use (they are far too large to embed).

Notes:
- The packaged engine is the **CPU** build (Parakeet + Moonshine via sherpa-onnx).
  GPU (`[gpu]`), FunASR SenseVoice (`[sensevoice-asr]`) and diarization
  (`[whisperx-pyannote]`) remain dev-install extras; their providers report
  unavailable in a packaged install.
- CI builds the artifact on `windows-latest` (`.github/workflows/windows-package.yml`
  at the repo root) and uploads `OmniSpeak-win-x64`; the workflow also smoke-tests
  the frozen engine's `/health` and `/providers` before uploading.

## Speech models (CPU by default, NVIDIA optional)

Windows runs ASR through [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx). The same ONNX
model files run on CPU or on an NVIDIA GPU — only the onnxruntime *execution provider*
changes — so there is one engine and one set of models, not two builds.

| Provider id | Model | Languages | Best for |
| --- | --- | --- | --- |
| `parakeet-tdt` (default) | NVIDIA Parakeet-TDT 0.6B v3, INT8 | 25 European | Best accuracy; faster than real time on a normal CPU |
| `moonshine-base-en` | Moonshine Base, INT8 | English | Low-end CPUs and lowest latency; much smaller |
| `canary-qwen-2.5b` | Canary-Qwen 2.5B | multi | Not installed in this build |

Models download from Hugging Face into `%LOCALAPPDATA%\OmniSpeak\models\`.

### Choosing the execution device

Set **Settings → ASR device**, or the `OMNIVOICE_ASR_DEVICE` environment variable:

- `auto` (default) — use CUDA when onnxruntime reports it, otherwise CPU.
- `cpu` — always CPU, even with a GPU present.
- `cuda` — force the NVIDIA path.

`GET /providers` reports the device each provider actually ended up on, so the UI can show
"Parakeet TDT (cuda)".

### Enabling NVIDIA acceleration

```powershell
$env:OMNIVOICE_ASR_DEVICE = "cuda"   # also triggers the GPU install below
.\scripts\run-engine.ps1
```

That installs the `gpu` extra (`onnxruntime-gpu`) alongside sherpa-onnx. You also need the
NVIDIA **CUDA runtime + cuDNN** installed.

> **Version pinning is the usual failure.** sherpa-onnx links a specific onnxruntime: the
> CUDA 11.8 path expects `onnxruntime-gpu==1.17.1`, while newer sherpa releases ship a
> CUDA 12.x / cuDNN 9.x build. Mismatched versions throw at model-load time. When that
> happens the engine **logs the reason and silently falls back to CPU** rather than breaking
> dictation — check `engine.log`, or the `reason` field on `/providers`, to see whether you
> are actually on the GPU.

Non-NVIDIA GPUs and NPUs can be reached through onnxruntime's DirectML / Windows ML
providers; not wired up yet, but the device abstraction in `providers/device.py` is where
that would go.

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