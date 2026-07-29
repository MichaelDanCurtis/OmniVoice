from fastapi.testclient import TestClient
from omnivoice_engine import main as engine_main
from omnivoice_engine.main import app
from omnivoice_engine.runtime_store import RuntimeStore
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


class ExplodingASRProvider:
    id = "exploding"
    label = "Exploding ASR"

    def info(self):
        from omnivoice_engine.schemas import ProviderInfo

        return ProviderInfo(id=self.id, label=self.label, available=True)

    def transcribe(self, audio_bytes: bytes):
        raise RuntimeError("decoder exploded")

    def transcribe_pcm_float32(self, pcm_bytes: bytes, sample_rate: int):
        raise RuntimeError("decoder exploded")


class ExplodingRegistry:
    def get(self, provider_id: str):
        return ExplodingASRProvider()


def test_health_endpoint():
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_dashboard_root_returns_engine_console():
    response = client.get("/")

    assert response.status_code == 200
    assert "OmniSpeak Engine" in response.text
    assert "/assets/dashboard.js" in response.text


def test_default_theme_endpoint_returns_css_variables():
    response = client.get("/api/theme/default")

    assert response.status_code == 200
    payload = response.json()
    assert payload["id"] == "auroraBlue"
    assert payload["name"] == "Aurora Blue"
    assert payload["css_variables"]["--ov-accent"] == "#38BDF8"
    assert payload["css_variables"]["--ov-accent-secondary"] == "#818CF8"
    assert payload["css_variables"]["--ov-bg"] == "#06121C"
    assert payload["css_variables"]["--ov-surface"] == "rgba(6, 18, 28, 0.36)"
    assert payload["css_variables"]["--ov-surface-strong"] == "rgba(6, 18, 28, 0.54)"
    assert payload["css_variables"]["--ov-text"] == "#F8FAFC"
    assert payload["css_variables"]["--ov-muted"] == "rgba(248, 250, 252, 0.64)"
    assert payload["css_variables"]["--ov-border"] == "rgba(56, 189, 248, 0.26)"
    assert payload["css_variables"]["--ov-glow"] == "rgba(56, 189, 248, 0.34)"
    assert payload["css_variables"]["--ov-caption-bg"] == "rgba(6, 18, 28, 0.14)"


def test_default_theme_returns_independent_css_mapping():
    payload = engine_main.default_theme()

    assert payload.css_variables == engine_main.DEFAULT_THEME_CSS_VARIABLES
    assert payload.css_variables is not engine_main.DEFAULT_THEME_CSS_VARIABLES


def test_status_endpoint_returns_operator_snapshot(monkeypatch, tmp_path):
    monkeypatch.setattr("omnivoice_engine.main.runtime_store", RuntimeStore(tmp_path), raising=False)
    monkeypatch.setattr("omnivoice_engine.main.model_manager", FakeModelManager(), raising=False)

    response = client.get("/api/status")

    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "ok"
    assert payload["providers"]
    assert payload["models"][0]["provider_id"] == "parakeet-tdt"
    assert payload["event_count"] >= 0
    assert payload["transcript_count"] >= 0
    assert payload["streaming"]["active_streams"] == 0
    assert payload["streaming"]["opened_streams"] == 0


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


def test_cleanup_endpoint_records_cleaned_transcript(monkeypatch, tmp_path):
    monkeypatch.setattr("omnivoice_engine.main.runtime_store", RuntimeStore(tmp_path), raising=False)

    response = client.post(
        "/cleanup",
        json={
            "raw_transcript": "Send it to Mark. Scratch that, send it to Sara.",
            "style": "neutral",
            "dictionary_terms": [],
        },
    )

    assert response.status_code == 200
    history = client.get("/api/transcripts").json()
    assert history[0]["source"] == "cleanup"
    assert history[0]["raw_text"] == "Send it to Mark. Scratch that, send it to Sara."
    assert history[0]["cleaned_text"] == "Send it to Sara."


def test_ai_handoff_endpoint_posts_openai_compatible_request(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)
    captured: dict[str, object] = {}

    def fake_chat_completion(*, base_url, api_key, model, messages, timeout):
        captured["base_url"] = base_url
        captured["api_key"] = api_key
        captured["model"] = model
        captured["messages"] = messages
        captured["timeout"] = timeout
        return "Hi Jane, there are about 375,000 airline passengers per day in the United States."

    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    monkeypatch.setattr(engine_main, "openai_compatible_chat_completion", fake_chat_completion, raising=False)

    response = client.post(
        "/api/ai/handoff",
        json={
            "prompt": "write a quick reply to Jane",
            "provider": "claude",
            "base_url": "https://openrouter.ai/api/v1",
            "model": "anthropic/claude-sonnet",
            "api_key": "test-key",
            "context": "Jane asked how many people fly in the US.",
        },
    )

    assert response.status_code == 200
    assert response.json() == {
        "text": "Hi Jane, there are about 375,000 airline passengers per day in the United States.",
        "provider": "claude",
        "model": "anthropic/claude-sonnet",
    }
    assert captured["base_url"] == "https://openrouter.ai/api/v1"
    assert captured["api_key"] == "test-key"
    assert captured["model"] == "anthropic/claude-sonnet"
    assert captured["messages"][0]["role"] == "system"
    assert "Return only the text to insert" in captured["messages"][0]["content"]
    assert "write a quick reply to Jane" in captured["messages"][1]["content"]
    assert "Jane asked how many people fly in the US." in captured["messages"][1]["content"]
    assert any(event.kind == "ai_handoff.completed" for event in store.recent_events(5))


def test_ai_handoff_endpoint_requires_base_url_and_model():
    response = client.post(
        "/api/ai/handoff",
        json={
            "prompt": "write a quick reply",
            "provider": "custom",
            "base_url": "",
            "model": "",
        },
    )

    assert response.status_code == 400
    assert response.json()["detail"] == "AI endpoint and model are required"


def test_ai_handoff_endpoint_reports_upstream_failure(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)

    def fake_chat_completion(**_kwargs):
        raise RuntimeError("upstream timed out")

    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    monkeypatch.setattr(engine_main, "openai_compatible_chat_completion", fake_chat_completion, raising=False)

    response = client.post(
        "/api/ai/handoff",
        json={
            "prompt": "write a quick reply",
            "provider": "custom",
            "base_url": "http://127.0.0.1:11434/v1",
            "model": "local-qwen",
        },
    )

    assert response.status_code == 502
    assert response.json()["detail"] == "AI handoff failed: upstream timed out"
    assert any(event.kind == "ai_handoff.failed" for event in store.recent_events(5))


def test_translate_endpoint_posts_openai_compatible_request(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)
    captured: dict[str, object] = {}

    def fake_chat_completion(*, base_url, api_key, model, messages, timeout):
        captured["base_url"] = base_url
        captured["api_key"] = api_key
        captured["model"] = model
        captured["messages"] = messages
        captured["timeout"] = timeout
        return "Hola Jane, no vamos a venir."

    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    monkeypatch.setattr(engine_main, "openai_compatible_chat_completion", fake_chat_completion, raising=False)

    response = client.post(
        "/api/translate",
        json={
            "text": "Hi Jane, we will not be coming.",
            "source_language": "en",
            "target_language": "es",
            "provider": "openrouter",
            "base_url": "https://openrouter.ai/api/v1",
            "model": "openai/gpt-4.1-mini",
            "api_key": "test-key",
        },
    )

    assert response.status_code == 200
    assert response.json() == {
        "text": "Hola Jane, no vamos a venir.",
        "provider": "openrouter",
        "model": "openai/gpt-4.1-mini",
        "source_language": "en",
        "target_language": "es",
    }
    assert captured["base_url"] == "https://openrouter.ai/api/v1"
    assert captured["api_key"] == "test-key"
    assert captured["model"] == "openai/gpt-4.1-mini"
    assert captured["timeout"] == 45.0
    assert captured["messages"][0]["role"] == "system"
    assert "Return only the translated text" in captured["messages"][0]["content"]
    assert "Source language: en" in captured["messages"][1]["content"]
    assert "Target language: es" in captured["messages"][1]["content"]
    assert "Hi Jane, we will not be coming." in captured["messages"][1]["content"]
    assert any(event.kind == "translation.completed" for event in store.recent_events(5))


def test_translate_endpoint_requires_base_url_and_model():
    response = client.post(
        "/api/translate",
        json={
            "text": "Translate me.",
            "source_language": "auto",
            "target_language": "es",
            "provider": "custom",
            "base_url": "",
            "model": "",
        },
    )

    assert response.status_code == 400
    assert response.json()["detail"] == "Translation endpoint and model are required"


def test_translate_endpoint_reports_upstream_failure(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)

    def fake_chat_completion(**_kwargs):
        raise RuntimeError("upstream timed out")

    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    monkeypatch.setattr(engine_main, "openai_compatible_chat_completion", fake_chat_completion, raising=False)

    response = client.post(
        "/api/translate",
        json={
            "text": "Translate me.",
            "source_language": "auto",
            "target_language": "es",
            "provider": "custom",
            "base_url": "http://127.0.0.1:11434/v1",
            "model": "local-qwen",
        },
    )

    assert response.status_code == 502
    assert response.json()["detail"] == "Translation failed: upstream timed out"
    assert any(event.kind == "translation.failed" for event in store.recent_events(5))


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


def test_desktop_app_launch_endpoint_opens_configured_app(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)
    app_bundle = tmp_path / "OmniVoiceApp.app"
    app_bundle.mkdir()
    launched: list[str] = []

    def fake_launch(app_path):
        launched.append(str(app_path))

    monkeypatch.setenv("OMNIVOICE_DESKTOP_APP_PATH", str(app_bundle))
    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    monkeypatch.setattr(engine_main, "launch_desktop_app", fake_launch, raising=False)

    response = client.post("/api/desktop-app/start")

    assert response.status_code == 200
    assert response.json() == {
        "status": "started",
        "message": "Desktop app launch requested",
        "app_path": str(app_bundle),
    }
    assert launched == [str(app_bundle)]
    assert store.recent_events(1)[0].kind == "desktop_app.start"


def test_desktop_app_launch_endpoint_reports_missing_bundle(monkeypatch, tmp_path):
    missing_bundle = tmp_path / "Missing.app"

    monkeypatch.setenv("OMNIVOICE_DESKTOP_APP_PATH", str(missing_bundle))

    response = client.post("/api/desktop-app/start")

    assert response.status_code == 404
    assert response.json()["detail"] == f"desktop app bundle not found: {missing_bundle}"


def test_transcribe_endpoint_uses_fake_provider():
    response = client.post("/transcribe?provider=fake", content=b"audio-bytes")

    assert response.status_code == 200
    assert response.json() == {"text": "fake transcript", "provider": "fake"}


def test_transcribe_endpoint_records_raw_transcript(monkeypatch, tmp_path):
    monkeypatch.setattr("omnivoice_engine.main.runtime_store", RuntimeStore(tmp_path), raising=False)

    response = client.post("/transcribe?provider=fake", content=b"audio-bytes")

    assert response.status_code == 200
    history = client.get("/api/transcripts").json()
    assert history[0]["source"] == "transcribe"
    assert history[0]["provider"] == "fake"
    assert history[0]["raw_text"] == "fake transcript"
    assert history[0]["audio_bytes"] == len(b"audio-bytes")


def test_event_export_returns_jsonl(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)
    store.record_event("test.event", "Recorded test event")
    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)

    response = client.get("/api/events/export")

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("application/x-ndjson")
    assert "test.event" in response.text


def test_transcribe_endpoint_reports_provider_failure(monkeypatch):
    monkeypatch.setattr("omnivoice_engine.main.registry", ExplodingRegistry(), raising=False)

    response = client.post("/transcribe?provider=exploding", content=b"audio-bytes")

    assert response.status_code == 502
    assert response.json()["detail"] == "transcription failed: decoder exploded"


def test_stream_endpoint_emits_partial_and_final_caption(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)
    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    with client.websocket_connect("/stream?provider=fake&sample_rate=16000") as websocket:
        assert websocket.receive_json() == {"type": "partial", "text": "listening"}

        websocket.send_bytes(b"0" * 64_000)
        assert websocket.receive_json() == {"type": "partial", "text": "fake transcript"}

        websocket.send_text("__finish__")
        assert websocket.receive_json() == {"type": "final", "text": "fake transcript"}

    status = client.get("/api/status").json()
    assert status["streaming"]["opened_streams"] == 1
    assert status["streaming"]["completed_streams"] == 1
    assert status["streaming"]["active_streams"] == 0
    assert status["streaming"]["total_chunks"] == 1
    assert status["streaming"]["total_audio_bytes"] == 64_000
    assert status["streaming"]["total_partials"] == 1
    assert status["streaming"]["last_provider"] == "fake"
    assert status["streaming"]["last_partial_text"] == "fake transcript"

    events = client.get("/api/events").json()
    completed = next(event for event in events if event["kind"] == "stream.completed")
    assert completed["detail"]["chunk_count"] == 1
    assert completed["detail"]["partial_count"] == 1


def test_stream_endpoint_reports_provider_failure(monkeypatch):
    monkeypatch.setattr("omnivoice_engine.main.registry", ExplodingRegistry(), raising=False)

    with client.websocket_connect("/stream?provider=exploding&sample_rate=16000") as websocket:
        assert websocket.receive_json() == {"type": "partial", "text": "listening"}

        websocket.send_bytes(b"0" * 64_000)

        assert websocket.receive_json() == {
            "type": "error",
            "text": "transcription failed: decoder exploded",
        }
