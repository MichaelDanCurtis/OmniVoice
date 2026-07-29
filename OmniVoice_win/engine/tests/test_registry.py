import sys
from types import SimpleNamespace

from omnivoice_engine.providers.registry import ProviderRegistry
from omnivoice_engine.providers.parakeet_sherpa import ParakeetSherpaProvider
from omnivoice_engine.providers.sensevoice_funasr import SenseVoiceFunASRProvider


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


def test_parakeet_provider_default_dir_uses_project_models_when_started_from_engine_dir(tmp_path, monkeypatch):
    project_root = tmp_path / "OmniSpeak"
    package_dir = project_root / "engine" / "omnivoice_engine" / "providers"
    package_dir.mkdir(parents=True)
    model_dir = project_root / "models" / "parakeet-tdt"
    model_dir.mkdir(parents=True)
    for filename in ["encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"]:
        (model_dir / filename).write_text("model")

    monkeypatch.chdir(project_root / "engine")
    monkeypatch.delenv("OMNIVOICE_MODEL_ROOT", raising=False)
    monkeypatch.delenv("OMNIVOICE_PARAKEET_MODEL_DIR", raising=False)
    monkeypatch.setattr("omnivoice_engine.providers.parakeet_sherpa.__file__", str(package_dir / "parakeet_sherpa.py"))
    monkeypatch.setitem(sys.modules, "sherpa_onnx", object())

    provider = ParakeetSherpaProvider()

    assert str(provider.model_dir) == str(model_dir)
    assert provider.info().available is True


def test_parakeet_provider_accepts_hugging_face_int8_layout(tmp_path, monkeypatch):
    for filename in ["encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"]:
        (tmp_path / filename).write_text("model")
    monkeypatch.setitem(sys.modules, "sherpa_onnx", object())

    info = ParakeetSherpaProvider(str(tmp_path)).info()

    assert info.available is True


def test_parakeet_provider_uses_nemo_transducer_runtime_config(tmp_path, monkeypatch):
    captured = {}

    for filename in ["encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"]:
        (tmp_path / filename).write_text("model")

    class FakeOfflineRecognizer:
        @staticmethod
        def from_transducer(**kwargs):
            captured.update(kwargs)
            return object()

    monkeypatch.setitem(
        sys.modules,
        "sherpa_onnx",
        SimpleNamespace(OfflineRecognizer=FakeOfflineRecognizer),
    )

    ParakeetSherpaProvider(str(tmp_path))._get_recognizer()

    assert captured["model_type"] == "nemo_transducer"
    assert captured["feature_dim"] == 80


def test_parakeet_provider_returns_empty_text_for_too_short_audio(monkeypatch):
    import numpy as np

    provider = ParakeetSherpaProvider("/tmp/unused")
    monkeypatch.setattr(
        provider,
        "_get_recognizer",
        lambda: (_ for _ in ()).throw(AssertionError("recognizer should not be initialized")),
    )

    assert provider._decode_samples(np.zeros(1000, dtype=np.float32), 16000) == ""


def test_parakeet_provider_returns_empty_text_for_empty_request_body(tmp_path, monkeypatch):
    for filename in ["encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"]:
        (tmp_path / filename).write_text("model")
    monkeypatch.setitem(sys.modules, "sherpa_onnx", object())

    assert ParakeetSherpaProvider(str(tmp_path)).transcribe(b"") == ""


def test_canary_qwen_provider_is_visible_as_installable_accuracy_mode():
    registry = ProviderRegistry()

    providers = registry.list_providers()

    canary = next(provider for provider in providers if provider.id == "canary-qwen-2.5b")
    assert canary.available is False
    assert canary.reason == "Canary-Qwen-2.5B runtime is not installed in this MVP build"


def test_sensevoice_provider_is_visible_as_fast_multilingual_backend(monkeypatch):
    monkeypatch.setenv("OMNIVOICE_SENSEVOICE_MODEL_DIR", "/tmp/omnivoice-missing-sensevoice-model")
    registry = ProviderRegistry()

    providers = registry.list_providers()

    sensevoice = next(provider for provider in providers if provider.id == "sensevoice-small-funasr")
    assert sensevoice.label == "SenseVoice Small FunASR"
    assert sensevoice.available is False
    assert "model files not found" in sensevoice.reason


def test_sensevoice_provider_reports_missing_runtime(tmp_path, monkeypatch):
    for filename in ["config.yaml", "model.pt", "am.mvn", "chn_jpn_yue_eng_ko_spectok.bpe.model"]:
        (tmp_path / filename).write_text("model")
    monkeypatch.delitem(sys.modules, "funasr", raising=False)

    info = SenseVoiceFunASRProvider(str(tmp_path)).info()

    assert info.available is False
    assert info.reason == "FunASR runtime is not installed"


def test_sensevoice_provider_transcribes_with_local_model_dir(tmp_path, monkeypatch):
    captured = {}
    for filename in ["config.yaml", "model.pt", "am.mvn", "chn_jpn_yue_eng_ko_spectok.bpe.model"]:
        (tmp_path / filename).write_text("model")

    class FakeAutoModel:
        def __init__(self, **kwargs):
            captured.update(kwargs)

        def generate(self, **_kwargs):
            return [{"text": "<|en|><|NEUTRAL|><|Speech|><|woitn|>hello from sensevoice"}]

    monkeypatch.setitem(sys.modules, "funasr", SimpleNamespace(AutoModel=FakeAutoModel))
    monkeypatch.setitem(
        sys.modules,
        "funasr.utils.postprocess_utils",
        SimpleNamespace(rich_transcription_postprocess=lambda text: text.replace("<|en|>", "").strip()),
    )

    result = SenseVoiceFunASRProvider(str(tmp_path)).transcribe(b"RIFF fake wav")

    assert result == "hello from sensevoice"
    assert captured["model"] == str(tmp_path)
