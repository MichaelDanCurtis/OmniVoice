"""PyInstaller entry point for the frozen OmniSpeak engine.

Importing the app object directly (rather than uvicorn's "module:attr" string
loading) keeps module resolution simple inside the frozen bundle.
"""

from __future__ import annotations

import multiprocessing
import os


def main() -> None:
    # PyInstaller on Windows: child processes re-run the entry point unless
    # freeze_support is called first (huggingface_hub and torch use them).
    multiprocessing.freeze_support()

    import uvicorn

    from omnivoice_engine.main import app

    port = int(os.environ.get("OMNIVOICE_ENGINE_PORT", "8765"))
    uvicorn.run(app, host="127.0.0.1", port=port, log_level="info")


if __name__ == "__main__":
    main()
