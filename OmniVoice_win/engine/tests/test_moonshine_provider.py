import sys
import types

from omnivoice_engine.providers.device import CPU, CUDA
from omnivoice_engine.providers.moonshine_sherpa import MoonshineSherpaProvider

MODEL_FILES = [
    "preprocess.onnx",
    "encode.int8.onnx",
    "uncached_decode.int8.onnx",
    "cached_decode.int8.onnx",
    "tokens.txt",
]


def _installed_model_dir(tmp_path):
    for name in MODEL_FILES:
        (tmp_path / name).write_bytes(b"stub")
    return tmp_path


def _fake_sherpa(captured):
    class FakeOfflineRecognizer:
        @staticmethod
        def from_moonshine(**kwargs):
            captured.update(kwargs)
            return "moonshine-recognizer"

    return types.SimpleNamespace(OfflineRecognizer=FakeOfflineRecognizer)


def test_defaults_to_cpu_without_a_gpu():
    provider = MoonshineSherpaProvider(device="auto", available_providers=["CPUExecutionProvider"])
    assert provider.device == CPU


def test_can_run_on_cuda_when_requested():
    provider = MoonshineSherpaProvider(device="cuda")
    assert provider.device == CUDA


def test_missing_models_are_reported_with_the_device(tmp_path):
    info = MoonshineSherpaProvider(model_dir=str(tmp_path), device="cpu").info()
    assert info.available is False
    assert "model files not found" in info.reason
    assert info.device == CPU


def test_build_uses_from_moonshine_with_the_expected_arguments(tmp_path, monkeypatch):
    captured: dict = {}
    monkeypatch.setitem(sys.modules, "sherpa_onnx", _fake_sherpa(captured))

    provider = MoonshineSherpaProvider(model_dir=str(_installed_model_dir(tmp_path)), device="cpu")
    assert provider._get_recognizer() == "moonshine-recognizer"

    assert captured["provider"] == CPU
    assert captured["preprocessor"].endswith("preprocess.onnx")
    assert captured["encoder"].endswith("encode.int8.onnx")
    assert captured["uncached_decoder"].endswith("uncached_decode.int8.onnx")
    assert captured["cached_decoder"].endswith("cached_decode.int8.onnx")
    assert captured["tokens"].endswith("tokens.txt")


def test_cuda_request_is_passed_through_then_falls_back(tmp_path, monkeypatch):
    attempted = []

    class FakeOfflineRecognizer:
        @staticmethod
        def from_moonshine(**kwargs):
            attempted.append(kwargs["provider"])
            if kwargs["provider"] == CUDA:
                raise RuntimeError("cuDNN version mismatch")
            return "cpu-recognizer"

    monkeypatch.setitem(sys.modules, "sherpa_onnx", types.SimpleNamespace(OfflineRecognizer=FakeOfflineRecognizer))

    provider = MoonshineSherpaProvider(model_dir=str(_installed_model_dir(tmp_path)), device="cuda")
    assert provider._get_recognizer() == "cpu-recognizer"

    assert attempted == [CUDA, CPU]
    assert provider.device == CPU
    assert "cuDNN version mismatch" in provider.fallback_reason
