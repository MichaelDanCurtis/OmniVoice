from fastapi.testclient import TestClient
from omnivoice_engine.main import app
from omnivoice_engine.schemas import ModelDownloadStatus, ModelStatus, ModelUpdateInfo


client = TestClient(app)


class FakeModelManager:
    def list_statuses(self):
        return [
            ModelStatus(
                provider_id="parakeet-tdt",
                label="Parakeet TDT",
                repo_id="csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8",
                local_path="/models/parakeet-tdt",
                installed=False,
                missing_files=["encoder.int8.onnx"],
            )
        ]

    def check_update(self, provider_id: str):
        return ModelUpdateInfo(
            provider_id=provider_id,
            repo_id="csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8",
            installed_revision="old-sha",
            remote_revision="new-sha",
            update_available=True,
        )

    def start_download(self, provider_id: str):
        return ModelDownloadStatus(
            provider_id=provider_id,
            state="queued",
            message="Download queued",
            local_path="/models/parakeet-tdt",
        )

    def download_state(self, provider_id: str):
        return ModelDownloadStatus(
            provider_id=provider_id,
            state="queued",
            message="Download queued",
            local_path="/models/parakeet-tdt",
        )

    def download(self, provider_id: str):
        return self.download_state(provider_id)


def test_health_endpoint():
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_cleanup_endpoint():
    response = client.post(
        "/cleanup",
        json={
            "raw_transcript": "Schedule it for Monday, actually Tuesday.",
            "style": "neutral",
            "dictionary_terms": [],
        },
    )

    assert response.status_code == 200
    assert response.json() == {
        "text": "Schedule it for Tuesday.",
        "cleanup_applied": True,
    }


def test_providers_endpoint_includes_fake():
    response = client.get("/providers")

    assert response.status_code == 200
    assert {"id": "fake", "label": "Fake ASR", "available": True, "reason": None} in response.json()


def test_models_endpoint_lists_hugging_face_model_status(monkeypatch):
    monkeypatch.setattr("omnivoice_engine.main.model_manager", FakeModelManager(), raising=False)

    response = client.get("/models")

    assert response.status_code == 200
    assert response.json()[0]["repo_id"] == "csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8"
    assert response.json()[0]["missing_files"] == ["encoder.int8.onnx"]


def test_model_update_endpoint_checks_remote_revision(monkeypatch):
    monkeypatch.setattr("omnivoice_engine.main.model_manager", FakeModelManager(), raising=False)

    response = client.get("/models/parakeet-tdt/update")

    assert response.status_code == 200
    assert response.json()["installed_revision"] == "old-sha"
    assert response.json()["remote_revision"] == "new-sha"
    assert response.json()["update_available"] is True


def test_model_download_endpoint_queues_background_download(monkeypatch):
    monkeypatch.setattr("omnivoice_engine.main.model_manager", FakeModelManager(), raising=False)

    response = client.post("/models/parakeet-tdt/download")

    assert response.status_code == 200
    assert response.json()["state"] == "queued"
    assert response.json()["message"] == "Download queued"


def test_model_download_status_endpoint_reports_current_state(monkeypatch):
    monkeypatch.setattr("omnivoice_engine.main.model_manager", FakeModelManager(), raising=False)

    response = client.get("/models/parakeet-tdt/download")

    assert response.status_code == 200
    assert response.json()["state"] == "queued"


def test_transcribe_endpoint_uses_fake_provider():
    response = client.post("/transcribe?provider=fake", content=b"audio-bytes")

    assert response.status_code == 200
    assert response.json() == {"text": "fake transcript", "provider": "fake"}


def test_stream_endpoint_emits_partial_and_final_caption():
    with client.websocket_connect("/stream?provider=fake&sample_rate=16000") as websocket:
        assert websocket.receive_json() == {"type": "partial", "text": "listening"}

        websocket.send_bytes(b"0" * 4096)
        assert websocket.receive_json() == {"type": "partial", "text": "fake transcript"}

        websocket.send_text("__finish__")
        assert websocket.receive_json() == {"type": "final", "text": "fake transcript"}
