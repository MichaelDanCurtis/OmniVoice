# Builds the single-file OmniSpeak.exe for Windows:
#   1. freezes the Python engine with PyInstaller -> dist/engine/omnispeak-engine.exe
#   2. publishes the WPF app self-contained single-file, embedding the engine exe
# Result: dist\OmniSpeak.exe — one executable; models still download on first use.
# Must run on Windows (PyInstaller cannot cross-compile).

$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$EngineDir = Join-Path $RootDir "engine"
$DistDir = Join-Path $RootDir "dist"
$EngineDistDir = Join-Path $DistDir "engine"

Write-Host "== [1/3] Freezing the Python engine =="
Set-Location $EngineDir
$venvPython = Join-Path $EngineDir ".venv\Scripts\python.exe"
if (-not (Test-Path $venvPython)) {
    py -3.12 -m venv .venv
}
& $venvPython -m pip install --upgrade pip | Out-Null
& $venvPython -m pip install -e ".[dev,asr]" | Out-Null
& $venvPython -m pip install "pyinstaller>=6.0" | Out-Null
& $venvPython -m PyInstaller --noconfirm --distpath (Join-Path $EngineDir "dist") packaging\omnispeak-engine.spec

$engineExe = Join-Path $EngineDir "dist\omnispeak-engine.exe"
if (-not (Test-Path $engineExe)) {
    throw "PyInstaller did not produce $engineExe"
}

Write-Host "== [2/3] Staging engine exe for embedding =="
New-Item -ItemType Directory -Force -Path $EngineDistDir | Out-Null
Copy-Item $engineExe (Join-Path $EngineDistDir "omnispeak-engine.exe") -Force

Write-Host "== [3/3] Publishing single-file OmniSpeak.exe =="
Set-Location $RootDir
dotnet publish src\OmniVoice.App\OmniVoice.App.csproj `
    -c Release `
    -r win-x64 `
    --self-contained `
    -p:PublishSingleFile=true `
    -p:IncludeAllContentForSelfExtract=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -o $DistDir

$appExe = Join-Path $DistDir "OmniSpeak.exe"
if (-not (Test-Path $appExe)) {
    throw "dotnet publish did not produce $appExe"
}

$appMb = [math]::Round((Get-Item $appExe).Length / 1MB, 1)
$engineMb = [math]::Round((Get-Item $engineExe).Length / 1MB, 1)
Write-Host ""
Write-Host "Packaged: $appExe ($appMb MB; embedded engine $engineMb MB)"
Write-Host "Ship that single file. Speech models download to %LOCALAPPDATA%\OmniSpeak on first use."
