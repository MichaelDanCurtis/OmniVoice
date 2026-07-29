from omnivoice_engine.providers.device import CPU, CUDA
from omnivoice_engine.providers.parakeet_sherpa import ParakeetSherpaProvider

MODEL_FILES = ["encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"]


def _installed_model_dir(tmp_path):
    for name in MODEL_FILES:
        (tmp_path / name).write_bytes(b"stub")
    return tmp_path


def test_auto_selects_cpu_when_no_cuda_execution_provider():
    provider = ParakeetSherpaProvider(device="auto", available_providers=["CPUExecutionProvider"])
    assert provider.device == CPU


def test_auto_selects_cuda_when_execution_provider_present():
    provider = ParakeetSherpaProvider(device="auto", available_providers=["CUDAExecutionProvider"])
    assert provider.device == CUDA


def test_info_reports_the_selected_device(tmp_path):
    provider = ParakeetSherpaProvider(model_dir=str(tmp_path), device="cuda")
    assert provider.info().device == CUDA


def test_missing_models_still_report_a_device(tmp_path):
    provider = ParakeetSherpaProvider(model_dir=str(tmp_path), device="cpu")
    info = provider.info()
    assert info.available is False
    assert "model files not found" in info.reason
    assert info.device == CPU


def test_cuda_build_failure_falls_back_to_cpu(tmp_path):
    provider = ParakeetSherpaProvider(model_dir=str(_installed_model_dir(tmp_path)), device="cuda")
    attempted = []

    def fake_build(execution_provider):
        attempted.append(execution_provider)
        if execution_provider == CUDA:
            raise RuntimeError("onnxruntime CUDA provider not found")
        return object()

    provider._build_recognizer = fake_build
    provider._get_recognizer()

    assert attempted == [CUDA, CPU]
    assert provider.device == CPU
    assert "onnxruntime CUDA provider not found" in provider.fallback_reason


def test_info_surfaces_the_gpu_fallback_once_models_are_present(tmp_path):
    provider = ParakeetSherpaProvider(model_dir=str(_installed_model_dir(tmp_path)), device="cuda")
    provider._sherpa_import_error = lambda: None
    provider._build_recognizer = lambda execution_provider: (
        _raise() if execution_provider == CUDA else object()
    )
    provider._get_recognizer()

    info = provider.info()
    assert info.available is True
    assert info.device == CPU
    assert "using CPU instead" in info.reason


def _raise():
    raise RuntimeError("cuda init failed")


def test_recognizer_is_built_once_and_reused(tmp_path):
    provider = ParakeetSherpaProvider(model_dir=str(_installed_model_dir(tmp_path)), device="cpu")
    calls = []
    provider._build_recognizer = lambda execution_provider: calls.append(execution_provider) or object()

    first = provider._get_recognizer()
    second = provider._get_recognizer()

    assert first is second
    assert calls == [CPU]
