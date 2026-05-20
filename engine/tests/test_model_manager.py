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
        self.requested_tokens: list[str | None] = []

    def model_info(self, repo_id: str, token: str | None = None) -> FakeModelInfo:
        self.requested_repo_ids.append(repo_id)
        self.requested_tokens.append(token)
        return FakeModelInfo(self.sha)

    def whoami(self, token: str | None = None) -> dict:
        return {"name": "test-user"}


class GatedHubApi:
    def model_info(self, repo_id: str, token: str | None = None) -> FakeModelInfo:
        raise RuntimeError(f"403 Client Error: gated repo: {repo_id}")


class FakeSnapshotDownloader:
    def __init__(self) -> None:
        self.calls: list[dict] = []

    def __call__(self, **kwargs) -> str:
        self.calls.append(kwargs)
        local_dir = Path(kwargs["local_dir"])
        local_dir.mkdir(parents=True, exist_ok=True)
        for filename in kwargs["allow_patterns"]:
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


def test_model_manager_reports_mlx_parakeet_hugging_face_source(tmp_path: Path) -> None:
    manager = ModelManager(model_root=tmp_path, hub_api=FakeHubApi(), snapshot_downloader=FakeSnapshotDownloader())

    status = manager.status("parakeet-tdt-mlx")

    assert status.provider_id == "parakeet-tdt-mlx"
    assert status.repo_id == "mlx-community/parakeet-tdt-0.6b-v3"
    assert status.local_path == str(tmp_path / "parakeet-tdt-mlx")
    assert status.installed is False
    assert status.missing_files == ["config.json", "model.safetensors"]


def test_model_manager_reports_translategemma_mlx_hugging_face_source(tmp_path: Path) -> None:
    manager = ModelManager(model_root=tmp_path, hub_api=FakeHubApi(), snapshot_downloader=FakeSnapshotDownloader())

    status = manager.status("translategemma-mlx")

    assert status.provider_id == "translategemma-mlx"
    assert status.repo_id == "mlx-community/translategemma-4b-it-4bit"
    assert status.local_path == str(tmp_path / "translategemma-mlx")
    assert status.installed is False
    assert status.missing_files == ["config.json", "model.safetensors", "tokenizer.json"]
    assert status.category == "translation"
    assert status.recommendation == "Fast / Recommended"
    assert status.size == "2.18 GB"
    assert status.precision == "4-bit"
    assert status.requires_hf_auth is True
    assert status.agreement_url == "https://huggingface.co/google/translategemma-4b-it"


def test_model_manager_reports_curated_translation_model_recommendations(tmp_path: Path) -> None:
    manager = ModelManager(model_root=tmp_path, hub_api=FakeHubApi(), snapshot_downloader=FakeSnapshotDownloader())

    translation_models = [status for status in manager.list_statuses() if status.category == "translation"]

    assert [status.provider_id for status in translation_models] == [
        "translategemma-mlx",
        "translategemma-mlx-4b-8bit",
        "translategemma-mlx-12b-4bit",
        "sarvam-translate-mlx-4bit",
        "plamo-2-translate-mlx",
    ]
    assert [status.recommendation for status in translation_models] == [
        "Fast / Recommended",
        "Balanced Quality",
        "Quality / High-End Mac",
        "Indic Languages",
        "Japanese / English Specialist",
    ]


def test_model_manager_reports_mlx_sortformer_fp16_hugging_face_source(tmp_path: Path) -> None:
    manager = ModelManager(model_root=tmp_path, hub_api=FakeHubApi(), snapshot_downloader=FakeSnapshotDownloader())

    status = manager.status("mlx-sortformer-streaming-fp16")

    assert status.provider_id == "mlx-sortformer-streaming-fp16"
    assert status.repo_id == "mlx-community/diar_streaming_sortformer_4spk-v2.1-fp16"
    assert status.local_path == str(tmp_path / "mlx-sortformer-streaming-fp16")
    assert status.installed is False
    assert status.missing_files == ["config.json", "model.safetensors"]


def test_model_manager_reports_mlx_sortformer_fp32_hugging_face_source(tmp_path: Path) -> None:
    manager = ModelManager(model_root=tmp_path, hub_api=FakeHubApi(), snapshot_downloader=FakeSnapshotDownloader())

    status = manager.status("mlx-sortformer-streaming-fp32")

    assert status.provider_id == "mlx-sortformer-streaming-fp32"
    assert status.repo_id == "mlx-community/diar_streaming_sortformer_4spk-v2.1-fp32"
    assert status.local_path == str(tmp_path / "mlx-sortformer-streaming-fp32")
    assert status.installed is False
    assert status.missing_files == ["config.json", "model.safetensors"]


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


def test_model_manager_downloads_mlx_sortformer_model(tmp_path: Path) -> None:
    hub_api = FakeHubApi(sha="sortformer-sha")
    downloader = FakeSnapshotDownloader()
    manager = ModelManager(model_root=tmp_path, hub_api=hub_api, snapshot_downloader=downloader)

    status = manager.download("mlx-sortformer-streaming-fp16")

    assert status.state == "completed"
    assert status.revision == "sortformer-sha"
    assert status.local_path == str(tmp_path / "mlx-sortformer-streaming-fp16")
    assert downloader.calls[0]["repo_id"] == "mlx-community/diar_streaming_sortformer_4spk-v2.1-fp16"
    assert downloader.calls[0]["allow_patterns"] == ["config.json", "model.safetensors", "README.md"]
    assert manager.status("mlx-sortformer-streaming-fp16").installed is True


def test_model_manager_downloads_mlx_parakeet_model(tmp_path: Path) -> None:
    hub_api = FakeHubApi(sha="mlx-parakeet-sha")
    downloader = FakeSnapshotDownloader()
    manager = ModelManager(model_root=tmp_path, hub_api=hub_api, snapshot_downloader=downloader)

    status = manager.download("parakeet-tdt-mlx")

    assert status.state == "completed"
    assert status.revision == "mlx-parakeet-sha"
    assert status.local_path == str(tmp_path / "parakeet-tdt-mlx")
    assert downloader.calls[0]["repo_id"] == "mlx-community/parakeet-tdt-0.6b-v3"
    assert downloader.calls[0]["allow_patterns"] == ["config.json", "model.safetensors", "README.md"]
    assert manager.status("parakeet-tdt-mlx").installed is True


def test_model_manager_downloads_translategemma_mlx_model(tmp_path: Path) -> None:
    hub_api = FakeHubApi(sha="translate-sha")
    downloader = FakeSnapshotDownloader()
    manager = ModelManager(model_root=tmp_path, hub_api=hub_api, snapshot_downloader=downloader)

    status = manager.download("translategemma-mlx")

    assert status.state == "completed"
    assert status.revision == "translate-sha"
    assert status.local_path == str(tmp_path / "translategemma-mlx")
    assert downloader.calls[0]["repo_id"] == "mlx-community/translategemma-4b-it-4bit"
    assert downloader.calls[0]["allow_patterns"] == [
        "config.json",
        "generation_config.json",
        "model.safetensors",
        "model.safetensors.index.json",
        "tokenizer.json",
        "tokenizer.model",
        "tokenizer_config.json",
        "special_tokens_map.json",
        "added_tokens.json",
        "chat_template.jinja",
        "README.md",
    ]
    assert manager.status("translategemma-mlx").installed is True


def test_model_manager_deletes_downloaded_model_directory_and_metadata(tmp_path: Path) -> None:
    hub_api = FakeHubApi(sha="delete-sha")
    downloader = FakeSnapshotDownloader()
    manager = ModelManager(model_root=tmp_path, hub_api=hub_api, snapshot_downloader=downloader)
    manager.download("parakeet-tdt-mlx")
    model_dir = tmp_path / "parakeet-tdt-mlx"

    status = manager.delete("parakeet-tdt-mlx")

    assert status.provider_id == "parakeet-tdt-mlx"
    assert status.installed is False
    assert status.missing_files == ["config.json", "model.safetensors"]
    assert model_dir.exists() is False
    assert status.installed_revision is None


def test_model_manager_refuses_to_delete_model_while_download_is_active(tmp_path: Path) -> None:
    manager = ModelManager(model_root=tmp_path, hub_api=FakeHubApi(), snapshot_downloader=FakeSnapshotDownloader())
    manager.start_download("parakeet-tdt")

    with pytest.raises(RuntimeError, match="download is in progress"):
        manager.delete("parakeet-tdt")


def test_model_manager_uses_hugging_face_token_for_update_and_download(tmp_path: Path) -> None:
    hub_api = FakeHubApi(sha="translate-sha")
    downloader = FakeSnapshotDownloader()
    manager = ModelManager(model_root=tmp_path, hub_api=hub_api, snapshot_downloader=downloader)

    update = manager.check_update("translategemma-mlx", token="hf_test")
    status = manager.download("translategemma-mlx", token="hf_test")

    assert update.remote_revision == "translate-sha"
    assert status.state == "completed"
    assert hub_api.requested_tokens == ["hf_test", "hf_test"]
    assert downloader.calls[0]["token"] == "hf_test"


def test_model_manager_validates_hugging_face_model_access(tmp_path: Path) -> None:
    manager = ModelManager(model_root=tmp_path, hub_api=FakeHubApi(), snapshot_downloader=FakeSnapshotDownloader())

    validation = manager.validate_huggingface_access("translategemma-mlx", token="hf_test")

    assert validation.connected is True
    assert validation.username == "test-user"
    assert validation.provider_id == "translategemma-mlx"
    assert validation.repo_id == "mlx-community/translategemma-4b-it-4bit"
    assert validation.access_granted is True
    assert validation.source == "app-keychain"


def test_model_manager_explains_translategemma_hugging_face_authorization(tmp_path: Path) -> None:
    manager = ModelManager(model_root=tmp_path, hub_api=GatedHubApi(), snapshot_downloader=FakeSnapshotDownloader())

    with pytest.raises(RuntimeError, match="requires Hugging Face authorization"):
        manager.download("translategemma-mlx")

    state = manager.download_state("translategemma-mlx")
    assert state.state == "failed"
    assert "Accept the model agreement" in (state.message or "")
    assert "huggingface.co/mlx-community/translategemma-4b-it-4bit" in (state.message or "")


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
