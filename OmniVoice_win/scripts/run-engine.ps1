$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$EngineDir = Join-Path $RootDir "engine"
$Port = if ($env:OMNIVOICE_ENGINE_PORT) { $env:OMNIVOICE_ENGINE_PORT } else { "8765" }

Set-Location $EngineDir

$venvPython = Join-Path $EngineDir ".venv\Scripts\python.exe"
if (-not (Test-Path $venvPython)) {
    py -3.12 -m venv .venv
}

& $venvPython -m pip install -e ".[dev]" | Out-Null
$installAsr = if ($env:OMNIVOICE_INSTALL_ASR) { $env:OMNIVOICE_INSTALL_ASR } else { "1" }
if ($installAsr -eq "1") {
    & $venvPython -m pip install -e ".[asr]" | Out-Null
}

if (-not $env:OMNIVOICE_MODEL_ROOT) {
    $env:OMNIVOICE_MODEL_ROOT = Join-Path $RootDir "models"
}
if (-not $env:OMNIVOICE_PARAKEET_MODEL_DIR) {
    $env:OMNIVOICE_PARAKEET_MODEL_DIR = Join-Path $env:OMNIVOICE_MODEL_ROOT "parakeet-tdt"
}
if (-not $env:OMNIVOICE_CANARY_MODEL_DIR) {
    $env:OMNIVOICE_CANARY_MODEL_DIR = Join-Path $env:OMNIVOICE_MODEL_ROOT "canary-qwen-2.5b"
}
if (-not $env:OMNIVOICE_ENGINE_DATA_DIR) {
    $env:OMNIVOICE_ENGINE_DATA_DIR = Join-Path $RootDir "dist\engine-data"
}

& $venvPython -m uvicorn omnivoice_engine.main:app --host 127.0.0.1 --port $Port