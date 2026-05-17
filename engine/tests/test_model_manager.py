from pathlib import Path

import pytest

from omnivoice_engine.model_manager import ModelManager


class FakeModelInfo:
    def __init__(self, sha: str) -> None:
        self.sha = sha


class FakeHubApi:
    def __init__(self, sha: str = "remote-sha") -> None:
        self.sha = sha
        self.requested_repo_ids: list[str] = []

    def model_info(self, repo_id: str) -> FakeModelInfo:
        self.requested_repo_ids.append(repo_id)
        return FakeModelInfo(self.sha)


class FakeSnapshotDownloader:
    def __init__(self) -> None:
        self.calls: list[dict] = []

    def __call__(self, **kwargs) -> str:
        self.calls.append(kwargs)
        local_dir = Path(kwargs["local_dir"])
        local_dir.mkdir(parents=True, exist_ok=True)
        for filename in ["encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"]:
            (local_dir / filename).write_text("model")
        return str(local_dir)


def test_model_manager_reports_parakeet_hugging_face_source(tmp_path: Path) -> None:
    manager = ModelManager(model_root=tmp_path, hub_api=FakeHubApi(), snapshot_downloader=FakeSnapshotDownloader())

    status = manager.status("parakeet-tdt")

    assert status.provider_id == "parakeet-tdt"
    assert status.repo_id == "csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8"
    assert status.local_path == str(tmp_path / "parakeet-tdt")
    assert status.installed is False
    assert status.missing_files == ["encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"]


def test_model_manager_default_root_uses_project_models_when_started_from_engine_dir(tmp_path: Path, monkeypatch) -> None:
    project_root = tmp_path / "OmniVoice"
    package_dir = project_root / "engine" / "omnivoice_engine"
    package_dir.mkdir(parents=True)
    model_root = project_root / "models"
    parakeet_dir = model_root / "parakeet-tdt"
    parakeet_dir.mkdir(parents=True)

    monkeypatch.chdir(project_root / "engine")
    monkeypatch.delenv("OMNIVOICE_MODEL_ROOT", raising=False)
    monkeypatch.delenv("OMNIVOICE_PARAKEET_MODEL_DIR", raising=False)
    monkeypatch.setattr("omnivoice_engine.model_manager.__file__", str(package_dir / "model_manager.py"))

    manager = ModelManager(hub_api=FakeHubApi(), snapshot_downloader=FakeSnapshotDownloader())

    assert manager.status("parakeet-tdt").local_path == str(parakeet_dir)


def test_model_manager_downloads_snapshot_and_writes_revision_metadata(tmp_path: Path) -> None:
    hub_api = FakeHubApi(sha="new-sha")
    downloader = FakeSnapshotDownloader()
    manager = ModelManager(model_root=tmp_path, hub_api=hub_api, snapshot_downloader=downloader)

    status = manager.download("parakeet-tdt")

    assert status.state == "completed"
    assert status.revision == "new-sha"
    assert status.local_path == str(tmp_path / "parakeet-tdt")
    assert downloader.calls[0]["repo_id"] == "csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8"
    assert downloader.calls[0]["allow_patterns"] == ["encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"]
    assert manager.status("parakeet-tdt").installed_revision == "new-sha"


def test_model_manager_detects_remote_updates(tmp_path: Path) -> None:
    manager = ModelManager(model_root=tmp_path, hub_api=FakeHubApi(sha="installed-sha"), snapshot_downloader=FakeSnapshotDownloader())
    manager.download("parakeet-tdt")
    manager.hub_api = FakeHubApi(sha="remote-sha")

    update = manager.check_update("parakeet-tdt")

    assert update.installed_revision == "installed-sha"
    assert update.remote_revision == "remote-sha"
    assert update.update_available is True


def test_model_manager_rejects_unknown_provider(tmp_path: Path) -> None:
    manager = ModelManager(model_root=tmp_path, hub_api=FakeHubApi(), snapshot_downloader=FakeSnapshotDownloader())

    with pytest.raises(KeyError):
        manager.status("fake")
