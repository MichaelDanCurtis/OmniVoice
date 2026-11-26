import importlib.util
import sys
from types import ModuleType, SimpleNamespace

from fastapi.testclient import TestClient

from omnivoice_engine.local_cleanup import LocalMLXCleanupEngine, strip_thinking_blocks
from omnivoice_engine.main import app
from omnivoice_engine.model_manager import ModelManager
from omnivoice_engine.providers.qwen3_asr_mlx import Qwen3ASRMLXProvider
from omnivoice_engine.providers.registry import ProviderRegistry
from omnivoice_engine.runtime_store import RuntimeStore


client = TestClient(app)


def test_strip_thinking_blocks_removes_complete_and_unclosed_think_tags():
    assert strip_thinking_blocks("<think>reasoning</think>\nFinal cleaned text.") == "Final cleaned text."
    assert strip_thinking_blocks("Clean text.<think>dangling") == "Clean text."


def test_local_mlx_cleanup_engine_runs_with_mlx_lm_and_disables_thinking(tmp_path, monkeypatch):
    model_dir = tmp_path / "qwen3-1.7b-mlx-4bit"
    model_dir.mkdir()
    for name in ("config.json", "model.safetensors", "tokenizer.json"):
        (model_dir / name).write_text("stub")

    captured = {}

    class FakeTokenizer:
        def apply_chat_template(self, messages, tokenize=False, add_generation_prompt=True, enable_thinking=True):
            captured["messages"] = messages
            captured["enable_thinking"] = enable_thinking
            return "FORMATTED_PROMPT"

    fake_mlx_lm = ModuleType("mlx_lm")
    fake_mlx_lm.load = lambda path: (SimpleNamespace(path=path), FakeTokenizer())

    def fake_generate(model, tokenizer, prompt, max_tokens=384, verbose=False):
        captured["prompt"] = prompt
        captured["max_tokens"] = max_tokens
        return "<think>plan</think>Ship the Figma update at 3 PM."

    fake_mlx_lm.generate = fake_generate
    monkeypatch.setattr("platform.system", lambda: "Darwin")
    monkeypatch.setattr("platform.machine", lambda: "arm64")
    monkeypatch.setattr(importlib.util, "find_spec", lambda name: object() if name == "mlx_lm" else None)
    monkeypatch.setitem(sys.modules, "mlx_lm", fake_mlx_lm)

    engine = LocalMLXCleanupEngine(model_root=tmp_path)
    assert engine.info("qwen3-1.7b-mlx-4bit").available is True

    result = engine.cleanup(
        messages=[{"role": "system", "content": "clean"}, {"role": "user", "content": "raw"}],
        model_id="qwen3-1.7b-mlx-4bit",
    )
    assert result == "Ship the Figma update at 3 PM."
    assert captured["enable_thinking"] is False
    assert captured["prompt"] == "FORMATTED_PROMPT"


def test_cleanup_endpoint_routes_local_mlx_transport(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)
    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    captured = {}

    class FakeLocalEngine:
        def cleanup(self, *, messages, model_id, model_path=""):
            captured["model_id"] = model_id
            captured["messages"] = messages
            return "Let's meet at 3 PM to review OmniSpeak."

    monkeypatch.setattr("omnivoice_engine.main.local_cleanup_engine", FakeLocalEngine(), raising=False)

    response = client.post(
        "/cleanup",
        json={
            "raw_transcript": "um lets meet at 2pm actually 3pm to review omnispeak",
            "style": "concise",
            "dictionary_terms": ["OmniSpeak"],
            "llm": {
                "enabled": True,
                "provider": "local_mlx",
                "model": "qwen3-1.7b-mlx-4bit",
                "transport": "local_mlx",
            },
        },
    )
    assert response.status_code == 200
    assert response.json() == {
        "text": "Let's meet at 3 PM to review OmniSpeak.",
        "cleanup_applied": True,
        "llm_applied": True,
    }
    assert captured["model_id"] == "qwen3-1.7b-mlx-4bit"


def test_model_manager_exposes_qwen3_asr_and_local_cleanup_models(tmp_path):
    manager = ModelManager(model_root=tmp_path)
    by_id = {status.provider_id: status for status in manager.list_statuses()}

    assert "qwen3-asr-1.7b-mlx-4bit" in by_id
    assert by_id["qwen3-asr-1.7b-mlx-4bit"].category == "asr"
    assert by_id["qwen3-asr-1.7b-mlx-4bit"].repo_id == "mlx-community/Qwen3-ASR-1.7B-4bit"

    assert "qwen3-1.7b-mlx-4bit" in by_id
    assert by_id["qwen3-1.7b-mlx-4bit"].category == "cleanup"
    assert by_id["qwen3-1.7b-mlx-4bit"].repo_id == "mlx-community/Qwen3-1.7B-4bit"

    assert "qwen3-4b-instruct-mlx-4bit" in by_id
    assert by_id["qwen3-4b-instruct-mlx-4bit"].category == "cleanup"
    assert by_id["qwen3-4b-instruct-mlx-4bit"].repo_id == "mlx-community/Qwen3-4B-Instruct-2507-4bit"


def test_qwen3_asr_mlx_provider_registered_and_transcribes(tmp_path, monkeypatch):
    for name in ("config.json", "model.safetensors", "tokenizer.json"):
        (tmp_path / name).write_text("model")

    fake_utils = ModuleType("mlx_audio.stt.utils")
    fake_generate = ModuleType("mlx_audio.stt.generate")
    fake_utils.load_model = lambda model_path, lazy=False, strict=False: SimpleNamespace(path=model_path)
    fake_generate.generate_transcription = lambda **kwargs: SimpleNamespace(text="hello from qwen3 asr", segments=[])

    monkeypatch.setattr("platform.system", lambda: "Darwin")
    monkeypatch.setattr("platform.machine", lambda: "arm64")
    monkeypatch.setattr(importlib.util, "find_spec", lambda name: object() if name == "mlx_audio" else None)
    monkeypatch.setitem(sys.modules, "mlx_audio", ModuleType("mlx_audio"))
    monkeypatch.setitem(sys.modules, "mlx_audio.stt", ModuleType("mlx_audio.stt"))
    monkeypatch.setitem(sys.modules, "mlx_audio.stt.utils", fake_utils)
    monkeypatch.setitem(sys.modules, "mlx_audio.stt.generate", fake_generate)

    registry = ProviderRegistry()
    assert any(p.id == "qwen3-asr-1.7b-mlx-4bit" for p in registry.list_providers())

    provider = Qwen3ASRMLXProvider(str(tmp_path))
    assert provider.info().available is True
    assert provider.transcribe_pcm_float32(b"\0\0\0\0" * 1600, 16000) == "hello from qwen3 asr"
