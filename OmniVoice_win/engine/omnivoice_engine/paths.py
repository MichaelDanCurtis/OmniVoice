from __future__ import annotations

import os
from pathlib import Path


def default_model_root(anchor_file: str | Path, cwd: Path | None = None) -> Path:
    configured = os.environ.get("OMNIVOICE_MODEL_ROOT")
    if configured:
        return Path(configured).expanduser()

    working_dir = cwd or Path.cwd()
    cwd_models = working_dir / "models"
    if cwd_models.exists():
        return cwd_models

    for parent in Path(anchor_file).resolve().parents:
        candidate = parent / "models"
        if candidate.exists():
            return candidate

    return Path("models")
