# PyInstaller spec for the frozen OmniSpeak engine (one-file exe, CPU ASR).
# Build on Windows:  pyinstaller packaging/omnispeak-engine.spec  (from engine/)
#
# The bundle includes FastAPI + uvicorn + sherpa-onnx (Parakeet/Moonshine, CPU
# execution provider). GPU (onnxruntime-gpu) and the optional FunASR/pyannote
# stacks are NOT frozen in — they stay dev-install extras; the corresponding
# providers simply report unavailable in a packaged install.

from pathlib import Path

from PyInstaller.utils.hooks import collect_all, collect_submodules

SPEC_DIR = Path(SPECPATH).resolve()
ENGINE_DIR = SPEC_DIR.parent

datas = [(str(ENGINE_DIR / "omnivoice_engine" / "static"), "omnivoice_engine/static")]
binaries = []
hiddenimports = collect_submodules("uvicorn")

for package in ("sherpa_onnx", "onnxruntime", "soundfile"):
    pkg_datas, pkg_binaries, pkg_hidden = collect_all(package)
    datas += pkg_datas
    binaries += pkg_binaries
    hiddenimports += pkg_hidden

a = Analysis(
    [str(SPEC_DIR / "engine_entry.py")],
    pathex=[str(ENGINE_DIR)],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    excludes=["torch", "torchaudio", "funasr", "whisperx", "pyannote"],
    noarchive=False,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    name="omnispeak-engine",
    console=False,
    upx=False,
)
