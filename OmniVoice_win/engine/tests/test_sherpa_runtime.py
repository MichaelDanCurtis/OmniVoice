import pytest

from omnivoice_engine.providers.device import CPU, CUDA
from omnivoice_engine.providers.sherpa_runtime import build_recognizer


def test_builds_on_cpu_and_reports_no_fallback():
    calls = []

    def build(provider):
        calls.append(provider)
        return f"recognizer:{provider}"

    result = build_recognizer(build, CPU)

    assert result.recognizer == "recognizer:cpu"
    assert result.device == CPU
    assert result.fallback_reason is None
    assert calls == [CPU]


def test_builds_on_cuda_when_the_gpu_runtime_works():
    result = build_recognizer(lambda provider: f"recognizer:{provider}", CUDA)

    assert result.recognizer == "recognizer:cuda"
    assert result.device == CUDA
    assert result.fallback_reason is None


def test_cuda_failure_falls_back_to_cpu_and_explains_why():
    calls = []

    def build(provider):
        calls.append(provider)
        if provider == CUDA:
            raise RuntimeError("libonnxruntime_providers_cuda.so not found")
        return f"recognizer:{provider}"

    result = build_recognizer(build, CUDA)

    assert result.recognizer == "recognizer:cpu"
    assert result.device == CPU
    assert calls == [CUDA, CPU]
    assert "libonnxruntime_providers_cuda" in result.fallback_reason


def test_cpu_failure_propagates_rather_than_looping():
    def build(provider):
        raise RuntimeError("model files are corrupt")

    with pytest.raises(RuntimeError, match="model files are corrupt"):
        build_recognizer(build, CPU)


def test_cuda_then_cpu_both_failing_raises_the_cpu_error():
    def build(provider):
        raise RuntimeError(f"boom on {provider}")

    with pytest.raises(RuntimeError, match="boom on cpu"):
        build_recognizer(build, CUDA)
