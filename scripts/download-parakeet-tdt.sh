#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}/engine"

if [ ! -d ".venv" ]; then
  python3.12 -m venv .venv
fi

. .venv/bin/activate
python -m pip install -e .

OMNIVOICE_MODEL_ROOT="${ROOT_DIR}/models" python - <<'PY'
from omnivoice_engine.model_manager import ModelManager

status = ModelManager().download("parakeet-tdt")
print(f"Parakeet TDT model ready at {status.local_path}")
print(f"Revision: {status.revision}")
PY
