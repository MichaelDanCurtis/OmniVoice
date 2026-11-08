import io
import json
import time
import urllib.error

from fastapi.testclient import TestClient
from omnivoice_engine import main as engine_main
from omnivoice_engine.main import app
from omnivoice_engine.runtime_store import RuntimeStore
from omnivoice_engine.schemas import HuggingFaceAuthStatus, ModelDownloadStatus, ModelStatus, ModelUpdateInfo, ProviderInfo


client = TestClient(app)


class FakeModelManager:
    def __init__(self):
        self.download_tokens: list[str | None] = []
        self.update_tokens: list[str | None] = []

    def list_statuses(self):
        return [
            ModelStatus(
                provider_id="parakeet-tdt",
                label="Parakeet TDT",
                repo_id="csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8",
                local_path="/models/parakeet-tdt",
                installed=False,
                missing_files=["encoder.int8.onnx"],
            ),
            ModelStatus(
                provider_id="parakeet-tdt-mlx",
                label="Parakeet TDT MLX",
                repo_id="mlx-community/parakeet-tdt-0.6b-v3",
                local_path="/models/parakeet-tdt-mlx",
                installed=False,
                missing_files=["config.json", "model.safetensors"],
            ),
            ModelStatus(
                provider_id="whisper-large-v3-turbo-mlx-6bit",
                label="Whisper Large v3 Turbo MLX 6-bit",
                repo_id="mlx-community/whisper-large-v3-turbo-asr-6bit",
                local_path="/models/whisper-large-v3-turbo-mlx-6bit",
                installed=False,
                missing_files=["config.json", "model.safetensors", "tokenizer.json", "preprocessor_config.json"],
                recommendation="Multilingual",
                size="664 MB",
                precision="6-bit",
            ),
            ModelStatus(
                provider_id="canary-qwen-2.5b",
                label="Canary-Qwen-2.5B",
                repo_id="nvidia/canary-qwen-2.5b",
                local_path="/models/canary-qwen-2.5b",
                installed=False,
                missing_files=["config.json", "model.safetensors"],
                recommendation="English Accuracy",
                size="5.1 GB",
                precision="BF16",
            ),
            ModelStatus(
                provider_id="translategemma-mlx",
                label="TranslateGemma MLX",
                repo_id="mlx-community/translategemma-4b-it-4bit",
                local_path="/models/translategemma-mlx",
                installed=False,
                missing_files=["config.json", "model.safetensors", "tokenizer.json"],
                category="translation",
                recommendation="Fast / Recommended",
                size="2.18 GB",
                precision="4-bit",
                requires_hf_auth=True,
                agreement_url="https://huggingface.co/google/translategemma-4b-it",
            ),
            ModelStatus(
                provider_id="mlx-sortformer-streaming-fp16",
                label="MLX Sortformer Streaming FP16",
                repo_id="mlx-community/diar_streaming_sortformer_4spk-v2.1-fp16",
                local_path="/models/mlx-sortformer-streaming-fp16",
                installed=False,
                missing_files=["config.json", "model.safetensors"],
            )
        ]

    def check_update(self, provider_id: str, token: str | None = None):
        self.update_tokens.append(token)
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

    def download(self, provider_id: str, token: str | None = None):
        self.download_tokens.append(token)
        return self.download_state(provider_id)

    def delete(self, provider_id: str):
        return ModelStatus(
            provider_id=provider_id,
            label="Parakeet TDT",
            repo_id="csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8",
            local_path="/models/parakeet-tdt",
            installed=False,
            missing_files=["encoder.int8.onnx"],
        )

    def validate_huggingface_access(self, provider_id: str, token: str = ""):
        return HuggingFaceAuthStatus(
            connected=True,
            source="app-keychain",
            username="test-user",
            provider_id=provider_id,
            repo_id="mlx-community/translategemma-4b-it-4bit",
            access_granted=True,
            message="Access granted",
        )


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
    assert payload["css_variables"]["--ov-accent-text"] == "#38BDF8"
    assert payload["css_variables"]["--ov-accent-secondary"] == "#818CF8"
    assert payload["css_variables"]["--ov-accent-secondary-text"] == "#818CF8"
    assert payload["css_variables"]["--ov-bg"] == "#06121C"
    assert payload["css_variables"]["--ov-surface"] == "rgba(6, 18, 28, 0.36)"
    assert payload["css_variables"]["--ov-surface-strong"] == "rgba(6, 18, 28, 0.54)"
    assert payload["css_variables"]["--ov-text"] == "#F8FAFC"
    assert payload["css_variables"]["--ov-muted"] == "rgba(248, 250, 252, 0.64)"
    assert payload["css_variables"]["--ov-on-accent"] == "#06121C"
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


def test_diarization_providers_endpoint_lists_local_backends():
    response = client.get("/diarization/providers")

    assert response.status_code == 200
    payload = response.json()
    assert any(provider["id"] == "none" and provider["available"] for provider in payload)
    assert any(provider["id"] == "mlx-sortformer-streaming-fp16" for provider in payload)
    assert any(provider["id"] == "mlx-sortformer-streaming-fp32" for provider in payload)
    assert any(provider["id"] == "local-heuristic" and provider["available"] for provider in payload)


def test_translation_providers_endpoint_lists_local_backends():
    response = client.get("/translation/providers")

    assert response.status_code == 200
    payload = response.json()
    assert any(provider["id"] == "fake" and provider["available"] for provider in payload)
    assert any(provider["id"] == "translategemma-mlx" for provider in payload)
    assert any(provider["id"] == "nllb-200-distilled-600m" for provider in payload)


def test_translation_capabilities_endpoint_lists_target_languages_from_model_template(tmp_path):
    model_dir = tmp_path / "translategemma"
    model_dir.mkdir()
    (model_dir / "chat_template.jinja").write_text(
        """
        {%- set languages = {
            "en": "English",
            "en-US": "English",
            "es": "Spanish",
            "fr": "French"
        } -%}
        """,
        encoding="utf-8",
    )

    response = client.get(
        "/translation/capabilities",
        params={
            "provider_id": "translategemma-mlx",
            "model_provider_id": "translategemma-mlx",
            "model_path": str(model_dir),
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["provider_id"] == "translategemma-mlx"
    assert payload["model_provider_id"] == "translategemma-mlx"
    assert payload["source_language_locked"] is True
    assert payload["source_languages"] == [{"code": "en", "name": "English", "is_default": True}]
    assert payload["target_languages"] == [
        {"code": "en", "name": "English", "is_default": False},
        {"code": "fr", "name": "French", "is_default": False},
        {"code": "es", "name": "Spanish", "is_default": False},
    ]
    assert payload["capability_source"] == "model-template"


def test_translation_capabilities_endpoint_uses_asr_provider_for_source_languages(tmp_path):
    model_dir = tmp_path / "translategemma"
    model_dir.mkdir()
    (model_dir / "chat_template.jinja").write_text(
        """
        {%- set languages = {
            "en": "English",
            "es": "Spanish",
            "zh": "Chinese"
        } -%}
        """,
        encoding="utf-8",
    )

    response = client.get(
        "/translation/capabilities",
        params={
            "provider_id": "translategemma-mlx",
            "model_provider_id": "translategemma-mlx",
            "model_path": str(model_dir),
            "asr_provider": "whisper-large-v3-turbo-mlx-6bit",
        },
    )

    assert response.status_code == 200
    payload = response.json()
    source_codes = [language["code"] for language in payload["source_languages"]]
    target_codes = [language["code"] for language in payload["target_languages"]]

    assert payload["source_language_locked"] is False
    assert source_codes == ["auto", "en", "es", "zh"]
    assert target_codes == ["zh", "en", "es"]


def test_translate_endpoint_returns_detected_language_and_target_text(monkeypatch, tmp_path):
    monkeypatch.setattr("omnivoice_engine.main.runtime_store", RuntimeStore(tmp_path), raising=False)

    response = client.post(
        "/translate",
        json={
            "text": "Hola, gracias por venir.",
            "provider": "fake",
            "source_language": "auto",
            "target_language": "en",
            "context": ["meeting greeting"],
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload == {
        "text": "[en] Hola, gracias por venir.",
        "provider": "fake",
        "source_language": "auto",
        "detected_language": "es",
        "target_language": "en",
        "confidence": 0.74,
        "is_final": True,
    }
    events = client.get("/api/events").json()
    assert any(event["kind"] == "translation.completed" for event in events)


def test_translation_validation_endpoint_reports_language_diagnostics():
    response = client.post(
        "/translation/validate",
        json={
            "text": "Hello",
            "provider": "fake",
            "source_language": "en",
            "target_languages": ["zh"],
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["provider"] == "fake"
    assert payload["tested"] == 1
    assert payload["items"][0]["code"] == "zh"
    assert payload["items"][0]["name"] == "Chinese"
    assert payload["items"][0]["expected_scripts"] == ["Han"]
    assert payload["items"][0]["status"] == "fail"


def test_translate_endpoint_rejects_unavailable_backend(monkeypatch, tmp_path):
    monkeypatch.setenv("OMNIVOICE_TRANSLATEGEMMA_MLX_MODEL_DIR", str(tmp_path / "missing-translategemma"))

    response = client.post(
        "/translate",
        json={
            "text": "Bonjour",
            "provider": "translategemma-mlx",
            "source_language": "fr",
            "target_language": "en",
        },
    )

    assert response.status_code == 503
    assert "provider unavailable" in response.json()["detail"]


def test_translation_stream_websocket_returns_partial_and_final_translation():
    with client.websocket_connect("/translation/stream?provider=fake&target_language=es") as websocket:
        websocket.send_json({"type": "partial", "text": "hello there"})
        partial = websocket.receive_json()
        websocket.send_json({"type": "final", "text": "hello there"})
        final = websocket.receive_json()
        websocket.send_json({"type": "finish"})

    assert partial["type"] == "partial_translation"
    assert partial["text"] == "[es] hello there"
    assert partial["is_final"] is False
    assert final["type"] == "final_translation"
    assert final["text"] == "[es] hello there"
    assert final["is_final"] is True


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

    def fake_chat_completion(*, base_url, api_key, oauth_access_token="", headers=None, model, messages, timeout):
        captured["base_url"] = base_url
        captured["api_key"] = api_key
        captured["headers"] = headers
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
            "transport": "openai_compatible",
            "headers": {" X-Kimi ": " enabled "},
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
    assert captured["headers"] == {"X-Kimi": "enabled"}
    assert captured["model"] == "anthropic/claude-sonnet"
    assert captured["messages"][0]["role"] == "system"
    assert "Return only the text to insert" in captured["messages"][0]["content"]
    assert "write a quick reply to Jane" in captured["messages"][1]["content"]
    assert "Jane asked how many people fly in the US." in captured["messages"][1]["content"]
    assert any(event.kind == "ai_handoff.completed" for event in store.recent_events(5))


def test_ai_chat_endpoint_posts_history_and_context_attachments(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)
    captured: dict[str, object] = {}

    def fake_chat_completion(*, base_url, api_key, oauth_access_token="", headers=None, model, messages, timeout):
        captured["base_url"] = base_url
        captured["api_key"] = api_key
        captured["headers"] = headers
        captured["model"] = model
        captured["messages"] = messages
        captured["timeout"] = timeout
        return "Use the repair notes and ask the mechanic to inspect the belts."

    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    monkeypatch.setattr(engine_main, "openai_compatible_chat_completion", fake_chat_completion, raising=False)

    response = client.post(
        "/api/ai/chat",
        json={
            "provider": "custom",
            "base_url": "http://127.0.0.1:11434/v1",
            "model": "local-qwen",
            "api_key": "test-key",
            "transport": "openai_compatible",
            "headers": {" X-Kimi ": " enabled "},
            "messages": [
                {"role": "user", "content": "Help me write to the mechanic."},
            ],
            "attachments": [
                {"kind": "file", "title": "repair.pdf", "text": "Replace belts and inspect mounts."},
                {"kind": "subject", "title": "Fixing the new car", "text": "Saturday appointment."},
            ],
        },
    )

    assert response.status_code == 200
    assert response.json() == {
        "text": "Use the repair notes and ask the mechanic to inspect the belts.",
        "provider": "custom",
        "model": "local-qwen",
    }
    assert captured["base_url"] == "http://127.0.0.1:11434/v1"
    assert captured["api_key"] == "test-key"
    assert captured["headers"] == {"X-Kimi": "enabled"}
    assert captured["messages"][0]["role"] == "system"
    assert "OmniSpeak Ask AI" in captured["messages"][0]["content"]
    assert "Return only the text to insert" not in captured["messages"][0]["content"]
    assert captured["messages"][1]["role"] == "user"
    assert "Help me write to the mechanic." in captured["messages"][1]["content"]
    assert "repair.pdf" in captured["messages"][1]["content"]
    assert "Replace belts and inspect mounts." in captured["messages"][1]["content"]
    assert "Saturday appointment." in captured["messages"][1]["content"]
    assert any(event.kind == "ai_chat.completed" for event in store.recent_events(5))


def test_ai_chat_endpoint_includes_web_search_context_when_enabled(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)
    captured: dict[str, object] = {}

    def fake_chat_completion(*, base_url, api_key, oauth_access_token="", headers=None, model, messages, timeout):
        captured["messages"] = messages
        return "The current result points to OmniSpeak release notes."

    def fake_web_search(query: str, limit: int = 5):
        captured["query"] = query
        return [
            engine_main.WebSearchResult(
                title="OmniSpeak release notes",
                url="https://example.com/omnivoice-release",
                snippet="OmniSpeak added Ask AI web search.",
            )
        ]

    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    monkeypatch.setattr(engine_main, "openai_compatible_chat_completion", fake_chat_completion, raising=False)
    monkeypatch.setattr(engine_main, "web_search_handler", fake_web_search, raising=False)

    response = client.post(
        "/api/ai/chat",
        json={
            "provider": "custom",
            "base_url": "http://127.0.0.1:11434/v1",
            "model": "local-qwen",
            "messages": [{"role": "user", "content": "What changed in OmniSpeak?"}],
            "web_search_enabled": True,
        },
    )

    assert response.status_code == 200
    assert captured["query"] == "What changed in OmniSpeak?"
    assert "Web search results" in captured["messages"][1]["content"]
    assert "https://example.com/omnivoice-release" in captured["messages"][1]["content"]
    assert "OmniSpeak added Ask AI web search." in captured["messages"][1]["content"]
    assert any(event.kind == "ai_chat.web_search.completed" for event in store.recent_events(10))


def test_ai_chat_endpoint_sends_openai_image_parts(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)
    captured: dict[str, object] = {}

    def fake_chat_completion(*, base_url, api_key, oauth_access_token="", headers=None, model, messages, timeout):
        captured["messages"] = messages
        return "The image appears to be a dashboard screenshot."

    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    monkeypatch.setattr(engine_main, "openai_compatible_chat_completion", fake_chat_completion, raising=False)

    response = client.post(
        "/api/ai/chat",
        json={
            "provider": "custom",
            "base_url": "http://127.0.0.1:11434/v1",
            "model": "vision-model",
            "messages": [{"role": "user", "content": "What is in this image?"}],
            "attachments": [
                {
                    "kind": "image",
                    "title": "dashboard.png",
                    "text": "Screenshot from OmniSpeak.",
                    "mime_type": "image/png",
                    "data_url": "data:image/png;base64,iVBORw0KGgo=",
                }
            ],
        },
    )

    assert response.status_code == 200
    content = captured["messages"][1]["content"]
    assert isinstance(content, list)
    assert content[0]["type"] == "text"
    assert "dashboard.png" in content[0]["text"]
    assert content[1] == {
        "type": "image_url",
        "image_url": {"url": "data:image/png;base64,iVBORw0KGgo="},
    }


def test_ai_handoff_endpoint_posts_anthropic_request(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)
    captured: dict[str, object] = {}

    def fake_chat_completion(*, base_url, api_key, oauth_access_token="", headers=None, model, messages, timeout):
        captured["base_url"] = base_url
        captured["api_key"] = api_key
        captured["model"] = model
        captured["messages"] = messages
        captured["timeout"] = timeout
        return "Hi Jane, here is the Spanish reply."

    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    monkeypatch.setattr(engine_main, "anthropic_chat_completion", fake_chat_completion, raising=False)

    response = client.post(
        "/api/ai/handoff",
        json={
            "prompt": "write a reply in Spanish",
            "provider": "claude",
            "base_url": "https://api.anthropic.com/v1",
            "model": "claude-test",
            "api_key": "anthropic-key",
            "transport": "anthropic",
            "context": "Jane asked for a schedule update.",
        },
    )

    assert response.status_code == 200
    assert response.json() == {
        "text": "Hi Jane, here is the Spanish reply.",
        "provider": "claude",
        "model": "claude-test",
    }
    assert captured["base_url"] == "https://api.anthropic.com/v1"
    assert captured["api_key"] == "anthropic-key"
    assert captured["model"] == "claude-test"
    assert captured["messages"][0]["role"] == "system"
    assert "write a reply in Spanish" in captured["messages"][1]["content"]


def test_ai_handoff_endpoint_posts_openai_codex_oauth_request(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)
    captured: dict[str, object] = {}

    def fake_chat_completion(*, base_url, api_key, oauth_access_token, headers=None, model, messages, timeout):
        captured["base_url"] = base_url
        captured["api_key"] = api_key
        captured["oauth_access_token"] = oauth_access_token
        captured["model"] = model
        captured["messages"] = messages
        captured["timeout"] = timeout
        return "Codex says hello."

    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    monkeypatch.setattr(engine_main, "openai_codex_oauth_completion", fake_chat_completion, raising=False)

    response = client.post(
        "/api/ai/handoff",
        json={
            "prompt": "summarize this",
            "provider": "openai_codex",
            "base_url": "https://chatgpt.com/backend-api",
            "model": "gpt-5.4",
            "transport": "openai_codex_oauth",
            "oauth_access_token": "codex-token",
        },
    )

    assert response.status_code == 200
    assert response.json()["text"] == "Codex says hello."
    assert captured["oauth_access_token"] == "codex-token"
    assert captured["model"] == "gpt-5.4"


def test_openai_codex_oauth_completion_sends_required_instructions(monkeypatch):
    captured: dict[str, object] = {}

    class FakeResponse:
        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return False

        def read(self):
            return b'{"output_text":"Codex says hello."}'

    def fake_urlopen(request, timeout):
        captured["url"] = request.full_url
        captured["headers"] = dict(request.header_items())
        captured["payload"] = json.loads(request.data.decode("utf-8"))
        return FakeResponse()

    monkeypatch.setattr(engine_main.urllib.request, "urlopen", fake_urlopen)

    result = engine_main.openai_codex_oauth_completion(
        base_url="https://chatgpt.com/backend-api",
        oauth_access_token="codex-token",
        model="gpt-5.4",
        messages=[
            {"role": "system", "content": "Return only the text to insert."},
            {"role": "user", "content": "Summarize this."},
        ],
        timeout=1,
    )

    assert result == "Codex says hello."
    assert captured["url"] == "https://chatgpt.com/backend-api/codex/responses"
    assert captured["payload"]["instructions"] == "Return only the text to insert."
    assert captured["payload"]["input"] == [{"role": "user", "content": "Summarize this."}]
    assert captured["payload"]["stream"] is True
    assert all(message["role"] != "system" for message in captured["payload"]["input"])


def test_extract_chat_text_handles_codex_response_stream():
    body = b"""
event: response.output_text.delta
data: {"type":"response.output_text.delta","delta":"Omni"}

event: response.output_text.delta
data: {"type":"response.output_text.delta","delta":"Speak passed."}

event: response.completed
data: {"type":"response.completed","response":{"output":[]}}
"""

    assert engine_main.extract_chat_text(body) == "OmniSpeak passed."


def test_ai_handoff_endpoint_posts_github_copilot_oauth_request(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)
    captured: dict[str, object] = {}

    def fake_chat_completion(*, base_url, api_key, oauth_access_token, headers=None, model, messages, timeout):
        captured["oauth_access_token"] = oauth_access_token
        captured["model"] = model
        captured["messages"] = messages
        return "Copilot says hello."

    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    monkeypatch.setattr(engine_main, "github_copilot_oauth_completion", fake_chat_completion, raising=False)

    response = client.post(
        "/api/ai/handoff",
        json={
            "prompt": "write a shell command",
            "provider": "github_copilot",
            "model": "gpt-4.1",
            "transport": "github_copilot_oauth",
            "oauth_access_token": "gho-token",
        },
    )

    assert response.status_code == 200
    assert response.json()["text"] == "Copilot says hello."
    assert captured["oauth_access_token"] == "gho-token"
    assert captured["model"] == "gpt-4.1"


def test_ai_handoff_oauth_endpoint_requires_token():
    response = client.post(
        "/api/ai/handoff",
        json={
            "prompt": "summarize this",
            "provider": "openai_codex",
            "base_url": "https://chatgpt.com/backend-api",
            "model": "gpt-5.4",
            "transport": "openai_codex_oauth",
        },
    )

    assert response.status_code == 400
    assert response.json()["detail"] == "OAuth access token is required"


def test_ai_handoff_endpoint_rejects_unknown_transport():
    response = client.post(
        "/api/ai/handoff",
        json={
            "prompt": "write a quick reply",
            "provider": "custom",
            "base_url": "http://127.0.0.1:11434/v1",
            "model": "local-qwen",
            "transport": "unsupported",
        },
    )

    assert response.status_code == 422


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


def test_ai_models_endpoint_lists_openai_compatible_models(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)
    captured: dict[str, object] = {}

    def fake_model_list(*, base_url, api_key, oauth_access_token, headers, timeout):
        captured["base_url"] = base_url
        captured["api_key"] = api_key
        captured["headers"] = headers
        return ["kimi-k2", "kimi-latest"]

    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    monkeypatch.setattr(engine_main, "openai_compatible_model_list", fake_model_list, raising=False)

    response = client.post(
        "/api/ai/models",
        json={
            "provider": "custom",
            "base_url": "https://api.moonshot.ai/v1",
            "api_key": "kimi-key",
            "transport": "openai_compatible",
            "headers": {" X-Moonshot ": " enabled "},
        },
    )

    assert response.status_code == 200
    assert response.json() == {"provider": "custom", "models": ["kimi-k2", "kimi-latest"]}
    assert captured["base_url"] == "https://api.moonshot.ai/v1"
    assert captured["api_key"] == "kimi-key"
    assert captured["headers"] == {"X-Moonshot": "enabled"}
    assert any(event.kind == "ai_models.completed" for event in store.recent_events(5))


def test_ai_models_endpoint_requires_oauth_token():
    response = client.post(
        "/api/ai/models",
        json={
            "provider": "github_copilot",
            "transport": "github_copilot_oauth",
        },
    )

    assert response.status_code == 400
    assert response.json()["detail"] == "OAuth access token is required"


def test_extract_model_ids_handles_data_and_catalog_shapes():
    assert engine_main.extract_model_ids(
        b'{"data":[{"id":"gpt-4.1"},{"id":"gpt-4.1"},{"id":"gpt-5"}]}'
    ) == ["gpt-4.1", "gpt-5"]
    assert engine_main.extract_model_ids(
        b'[{"name":"openai/gpt-4.1"},{"model":"anthropic/claude-sonnet"}]'
    ) == ["openai/gpt-4.1", "anthropic/claude-sonnet"]


def test_fetch_model_list_sanitizes_html_error(monkeypatch):
    def fake_urlopen(request, timeout):
        raise urllib.error.HTTPError(
            request.full_url,
            403,
            "Forbidden",
            {"Content-Type": "text/html"},
            io.BytesIO(b"<html><body>forbidden</body></html>"),
        )

    monkeypatch.setattr(engine_main.urllib.request, "urlopen", fake_urlopen)

    try:
        engine_main.fetch_model_list("https://chatgpt.com/backend-api/models", {}, timeout=1)
    except RuntimeError as exc:
        message = str(exc)
    else:
        raise AssertionError("expected RuntimeError")

    assert "<html>" not in message
    assert "403 Forbidden" in message
    assert "chatgpt.com" in message
    assert "HTML instead of JSON" in message


def test_openai_codex_model_list_uses_local_codex_cache(monkeypatch, tmp_path):
    codex_dir = tmp_path / ".codex"
    codex_dir.mkdir()
    (codex_dir / "models_cache.json").write_text(
        json.dumps(
            {
                "models": [
                    {"slug": "gpt-5.5"},
                    {"slug": "gpt-5.4"},
                    {"slug": "codex-auto-review"},
                    {"slug": "gpt-5.4"},
                ]
            }
        )
    )

    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setattr(
        engine_main.urllib.request,
        "urlopen",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(AssertionError("Codex model refresh should not call chatgpt.com")),
    )

    assert engine_main.openai_codex_model_list(
        base_url="https://chatgpt.com/backend-api",
        api_key="",
        oauth_access_token="codex-token",
        timeout=1,
        headers={},
    ) == ["gpt-5.5", "gpt-5.4"]


def test_openai_codex_model_list_falls_back_without_cache(monkeypatch, tmp_path):
    monkeypatch.setenv("HOME", str(tmp_path))

    models = engine_main.openai_codex_model_list(
        base_url="",
        api_key="",
        oauth_access_token="codex-token",
        timeout=1,
        headers={},
    )

    assert "gpt-5.5" in models
    assert "gpt-5.4-mini" in models


def test_github_copilot_model_list_exchanges_github_token(monkeypatch):
    captured: dict[str, object] = {}

    def fake_fetch_github_copilot_token(github_token, timeout, headers=None):
        captured["github_token"] = github_token
        captured["token_headers"] = headers
        return "copilot-service-token"

    def fake_fetch_model_list(endpoint, headers, timeout):
        captured["endpoint"] = endpoint
        captured["authorization"] = headers["Authorization"]
        captured["integration"] = headers["Copilot-Integration-Id"]
        return ["gpt-4.1"]

    monkeypatch.setattr(engine_main, "fetch_github_copilot_token", fake_fetch_github_copilot_token)
    monkeypatch.setattr(engine_main, "fetch_model_list", fake_fetch_model_list)

    models = engine_main.github_copilot_model_list(
        base_url="",
        api_key="",
        oauth_access_token="github-oauth-token",
        timeout=1,
        headers={"X-Test": "enabled"},
    )

    assert models == ["gpt-4.1"]
    assert captured["github_token"] == "github-oauth-token"
    assert captured["token_headers"] == {"X-Test": "enabled"}
    assert captured["endpoint"] == "https://api.githubcopilot.com/models"
    assert captured["authorization"] == "Bearer copilot-service-token"
    assert captured["integration"] == "vscode-chat"


def test_fetch_github_copilot_token_caches_service_token(monkeypatch):
    calls = 0
    engine_main._github_copilot_token_cache.clear()

    class FakeResponse:
        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return False

        def read(self):
            return json.dumps({"token": "cached-token", "expires_at": time.time() + 600}).encode("utf-8")

    def fake_urlopen(_request, timeout):
        nonlocal calls
        calls += 1
        return FakeResponse()

    monkeypatch.setattr(engine_main.urllib.request, "urlopen", fake_urlopen)

    assert engine_main.fetch_github_copilot_token("github-token", timeout=1) == "cached-token"
    assert engine_main.fetch_github_copilot_token("github-token", timeout=1) == "cached-token"
    assert calls == 1
    engine_main._github_copilot_token_cache.clear()


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


def test_models_endpoint_lists_sortformer_download_target(monkeypatch):
    monkeypatch.setattr("omnivoice_engine.main.model_manager", FakeModelManager(), raising=False)

    response = client.get("/models")

    assert response.status_code == 200
    payload = response.json()
    sortformer = next(model for model in payload if model["provider_id"] == "mlx-sortformer-streaming-fp16")
    assert sortformer["repo_id"] == "mlx-community/diar_streaming_sortformer_4spk-v2.1-fp16"
    assert sortformer["missing_files"] == ["config.json", "model.safetensors"]


def test_models_endpoint_lists_mlx_parakeet_download_target(monkeypatch):
    monkeypatch.setattr("omnivoice_engine.main.model_manager", FakeModelManager(), raising=False)

    response = client.get("/models")

    assert response.status_code == 200
    payload = response.json()
    mlx_parakeet = next(model for model in payload if model["provider_id"] == "parakeet-tdt-mlx")
    assert mlx_parakeet["repo_id"] == "mlx-community/parakeet-tdt-0.6b-v3"
    assert mlx_parakeet["missing_files"] == ["config.json", "model.safetensors"]


def test_models_endpoint_lists_whisper_mlx_download_target(monkeypatch):
    monkeypatch.setattr("omnivoice_engine.main.model_manager", FakeModelManager(), raising=False)

    response = client.get("/models")

    assert response.status_code == 200
    payload = response.json()
    whisper = next(model for model in payload if model["provider_id"] == "whisper-large-v3-turbo-mlx-6bit")
    assert whisper["repo_id"] == "mlx-community/whisper-large-v3-turbo-asr-6bit"
    assert whisper["missing_files"] == [
        "config.json",
        "model.safetensors",
        "tokenizer.json",
        "preprocessor_config.json",
    ]


def test_models_endpoint_lists_canary_qwen_download_target(monkeypatch):
    monkeypatch.setattr("omnivoice_engine.main.model_manager", FakeModelManager(), raising=False)

    response = client.get("/models")

    assert response.status_code == 200
    payload = response.json()
    canary = next(model for model in payload if model["provider_id"] == "canary-qwen-2.5b")
    assert canary["repo_id"] == "nvidia/canary-qwen-2.5b"
    assert canary["recommendation"] == "English Accuracy"
    assert canary["missing_files"] == ["config.json", "model.safetensors"]


def test_models_endpoint_lists_translategemma_download_target(monkeypatch):
    monkeypatch.setattr("omnivoice_engine.main.model_manager", FakeModelManager(), raising=False)

    response = client.get("/models")

    assert response.status_code == 200
    payload = response.json()
    translate_model = next(model for model in payload if model["provider_id"] == "translategemma-mlx")
    assert translate_model["repo_id"] == "mlx-community/translategemma-4b-it-4bit"
    assert translate_model["missing_files"] == ["config.json", "model.safetensors", "tokenizer.json"]


def test_model_update_endpoint_checks_remote_revision(monkeypatch):
    monkeypatch.setattr("omnivoice_engine.main.model_manager", FakeModelManager(), raising=False)

    response = client.get("/models/parakeet-tdt/update")

    assert response.status_code == 200
    assert response.json()["installed_revision"] == "old-sha"
    assert response.json()["remote_revision"] == "new-sha"
    assert response.json()["update_available"] is True


def test_model_update_endpoint_passes_hugging_face_bearer_token(monkeypatch):
    fake_manager = FakeModelManager()
    monkeypatch.setattr("omnivoice_engine.main.model_manager", fake_manager, raising=False)

    response = client.get("/models/translategemma-mlx/update", headers={"Authorization": "Bearer hf_test"})

    assert response.status_code == 200
    assert fake_manager.update_tokens == ["hf_test"]


def test_model_download_endpoint_queues_background_download(monkeypatch):
    monkeypatch.setattr("omnivoice_engine.main.model_manager", FakeModelManager(), raising=False)

    response = client.post("/models/parakeet-tdt/download")

    assert response.status_code == 200
    assert response.json()["state"] == "queued"
    assert response.json()["message"] == "Download queued"


def test_model_download_endpoint_passes_hugging_face_bearer_token(monkeypatch):
    fake_manager = FakeModelManager()

    def run_background_task(provider_id: str, token: str | None = None):
        fake_manager.download(provider_id, token=token)

    monkeypatch.setattr("omnivoice_engine.main.model_manager", fake_manager, raising=False)
    monkeypatch.setattr(engine_main, "_download_model", run_background_task, raising=False)

    response = client.post("/models/translategemma-mlx/download", headers={"Authorization": "Bearer hf_test"})

    assert response.status_code == 200
    assert fake_manager.download_tokens == ["hf_test"]


def test_model_download_status_endpoint_reports_current_state(monkeypatch):
    monkeypatch.setattr("omnivoice_engine.main.model_manager", FakeModelManager(), raising=False)

    response = client.get("/models/parakeet-tdt/download")

    assert response.status_code == 200
    assert response.json()["state"] == "queued"


def test_model_delete_endpoint_removes_downloaded_model(monkeypatch):
    monkeypatch.setattr("omnivoice_engine.main.model_manager", FakeModelManager(), raising=False)

    response = client.delete("/models/parakeet-tdt")

    assert response.status_code == 200
    payload = response.json()
    assert payload["provider_id"] == "parakeet-tdt"
    assert payload["installed"] is False
    assert payload["missing_files"] == ["encoder.int8.onnx"]


def test_hugging_face_validate_endpoint_reports_access(monkeypatch):
    monkeypatch.setattr("omnivoice_engine.main.model_manager", FakeModelManager(), raising=False)

    response = client.post(
        "/huggingface/validate",
        json={"token": "hf_test", "provider_id": "translategemma-mlx"},
    )

    assert response.status_code == 200
    assert response.json()["connected"] is True
    assert response.json()["username"] == "test-user"
    assert response.json()["access_granted"] is True


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
        assert websocket.receive_json() == {"type": "ready", "text": ""}

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


def test_stream_endpoint_can_translate_partial_and_final_captions(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)
    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)

    with client.websocket_connect(
        "/stream?provider=fake&sample_rate=16000&translate=true&translation_provider=fake&target_language=es"
    ) as websocket:
        assert websocket.receive_json() == {"type": "ready", "text": ""}

        websocket.send_bytes(b"0" * 64_000)
        assert websocket.receive_json() == {
            "type": "partial",
            "text": "[es] fake transcript",
            "raw_text": "fake transcript",
            "translated": True,
            "detected_language": "en",
            "target_language": "es",
        }

        websocket.send_text("__finish__")
        assert websocket.receive_json() == {
            "type": "final",
            "text": "[es] fake transcript",
            "raw_text": "fake transcript",
            "translated": True,
            "detected_language": "en",
            "target_language": "es",
        }

    events = client.get("/api/events").json()
    completed = next(event for event in events if event["kind"] == "stream.completed")
    assert completed["detail"]["translation_enabled"] is True
    assert completed["detail"]["target_language"] == "es"


def test_stream_endpoint_reports_provider_failure(monkeypatch):
    monkeypatch.setattr("omnivoice_engine.main.registry", ExplodingRegistry(), raising=False)

    with client.websocket_connect("/stream?provider=exploding&sample_rate=16000") as websocket:
        assert websocket.receive_json() == {"type": "ready", "text": ""}

        websocket.send_bytes(b"0" * 64_000)

        assert websocket.receive_json() == {
            "type": "error",
            "text": "transcription failed: decoder exploded",
        }


def test_transcribe_endpoint_offloads_blocking_inference(monkeypatch):
    captured = {}

    class OffloadASR:
        def info(self):
            return ProviderInfo(id="offload", label="Offload", available=True)

        def transcribe(self, audio_bytes):
            captured["audio_bytes"] = audio_bytes
            return "offloaded transcript"

    class OffloadRegistry:
        def get(self, provider_id):
            assert provider_id == "offload"
            return OffloadASR()

    async def fake_to_thread(function, *args):
        captured["function_name"] = function.__name__
        return function(*args)

    monkeypatch.setattr("omnivoice_engine.main.registry", OffloadRegistry(), raising=False)
    monkeypatch.setattr(engine_main.asyncio, "to_thread", fake_to_thread)

    response = client.post("/transcribe?provider=offload", content=b"audio-bytes")

    assert response.status_code == 200
    assert response.json() == {"text": "offloaded transcript", "provider": "offload"}
    assert captured == {
        "audio_bytes": b"audio-bytes",
        "function_name": "transcribe",
    }


def test_stream_endpoint_bounds_partial_audio_but_finishes_with_full_audio(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)
    decoded_lengths = []

    class RecordingASR:
        def info(self):
            return ProviderInfo(id="recording", label="Recording", available=True)

        def transcribe_pcm_float32(self, pcm_bytes, sample_rate):
            assert sample_rate == 16_000
            decoded_lengths.append(len(pcm_bytes))
            return "recorded transcript"

    class RecordingRegistry:
        def get(self, provider_id):
            assert provider_id == "recording"
            return RecordingASR()

    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    monkeypatch.setattr("omnivoice_engine.main.registry", RecordingRegistry(), raising=False)

    with client.websocket_connect(
        "/stream?provider=recording&sample_rate=16000&partial_window_seconds=1"
    ) as websocket:
        assert websocket.receive_json() == {"type": "ready", "text": ""}
        websocket.send_bytes(b"0" * 128_000)
        assert websocket.receive_json()["type"] == "partial"
        websocket.send_text("__finish__")
        assert websocket.receive_json()["type"] == "final"

    assert decoded_lengths == [64_000, 128_000]
