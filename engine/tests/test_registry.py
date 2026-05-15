import sys

from omnivoice_engine.providers.registry import ProviderRegistry
from omnivoice_engine.providers.parakeet_sherpa import ParakeetSherpaProvider


def test_fake_provider_is_available():
    registry = ProviderRegistry()

    providers = registry.list_providers()

    fake = next(provider for provider in providers if provider.id == "fake")
    assert fake.available is True
    assert fake.reason is None


def test_fake_provider_transcribes_bytes():
    registry = ProviderRegistry()
    provider = registry.get("fake")

    result = provider.transcribe(b"hello world")

    assert result == "fake transcript"


def test_parakeet_provider_is_reported_even_when_model_is_absent(monkeypatch):
    monkeypatch.setenv("OMNIVOICE_PARAKEET_MODEL_DIR", "/tmp/omnivoice-missing-parakeet-model")
    registry = ProviderRegistry()

    providers = registry.list_providers()

    parakeet = next(provider for provider in providers if provider.id == "parakeet-tdt")
    assert parakeet.available is False
    assert "model files not found" in parakeet.reason


def test_parakeet_provider_accepts_hugging_face_int8_layout(tmp_path, monkeypatch):
    for filename in ["encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"]:
        (tmp_path / filename).write_text("model")
    monkeypatch.setitem(sys.modules, "sherpa_onnx", object())

    info = ParakeetSherpaProvider(str(tmp_path)).info()

    assert info.available is True


def test_canary_qwen_provider_is_visible_as_installable_accuracy_mode():
    registry = ProviderRegistry()

    providers = registry.list_providers()

    canary = next(provider for provider in providers if provider.id == "canary-qwen-2.5b")
    assert canary.available is False
    assert canary.reason == "Canary-Qwen-2.5B runtime is not installed in this MVP build"
