"""Verify offline installation without borrowing the build machine's packages."""
from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile


def verify(python: str, engine: str) -> None:
    engine_root = Path(engine).resolve()
    wheelhouse = engine_root / "wheelhouse"
    with tempfile.TemporaryDirectory(prefix="omnivoice-runtime-check-") as scratch:
        # setuptools writes build/ and egg-info next to its input. Never let the
        # verification touch sealed resources in an existing signed app bundle.
        source = Path(scratch) / "engine"
        source.mkdir()
        shutil.copy2(engine_root / "pyproject.toml", source)
        shutil.copytree(engine_root / "omnivoice_engine", source / "omnivoice_engine")
        env = dict(os.environ)
        for key in ("PYTHONPATH", "PYTHONHOME", "VIRTUAL_ENV"):
            env.pop(key, None)
        env.update(PYTHONNOUSERSITE="1", PYTHONDONTWRITEBYTECODE="1",
                   PYTHONPYCACHEPREFIX=str(Path(scratch) / "cache"))

        def run(*args: str) -> None:
            subprocess.run(args, check=True, env=env, cwd=scratch)

        run(python, "-m", "venv", str(Path(scratch) / "venv"))
        isolated_python = str(Path(scratch) / "venv/bin/python")
        pip = (isolated_python, "-m", "pip", "install", "--no-index",
               "--find-links", str(wheelhouse))
        run(*pip, "setuptools>=69", "wheel>=0.43")
        run(*pip, "--no-build-isolation", f"{source}[asr,mlx-asr,mlx-diarization]")
        run(isolated_python, "-c", "import omnivoice_engine.main; import sherpa_onnx; "
            "import parakeet_mlx; import mlx_audio.stt; import mlx.core; "
            "import soundfile; import librosa; print('Offline runtime verification passed')")


if __name__ == "__main__":
    verify(sys.argv[1], sys.argv[2])
