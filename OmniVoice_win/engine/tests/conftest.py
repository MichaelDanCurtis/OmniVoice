from pathlib import Path

import pytest

from omnivoice_engine.runtime_store import RuntimeStore


@pytest.fixture(autouse=True)
def isolate_runtime_store(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.setattr("omnivoice_engine.main.runtime_store", RuntimeStore(tmp_path / "runtime"), raising=False)
