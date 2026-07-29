from omnivoice_engine.providers.device import (
    CPU,
    CUDA,
    requested_device_from_env,
    resolve_device,
)


def test_auto_prefers_cuda_when_execution_provider_is_available():
    assert resolve_device("auto", ["CUDAExecutionProvider", "CPUExecutionProvider"]) == CUDA


def test_auto_falls_back_to_cpu_when_cuda_is_not_available():
    assert resolve_device("auto", ["CPUExecutionProvider"]) == CPU


def test_missing_request_is_treated_as_auto():
    assert resolve_device(None, ["CUDAExecutionProvider"]) == CUDA
    assert resolve_device("", ["CPUExecutionProvider"]) == CPU


def test_explicit_cpu_wins_even_when_cuda_is_available():
    assert resolve_device("cpu", ["CUDAExecutionProvider", "CPUExecutionProvider"]) == CPU


def test_explicit_cuda_is_honored_even_when_detection_finds_nothing():
    # Detection can under-report (sherpa may bundle its own ORT), so an explicit
    # request is trusted; a genuinely broken CUDA install is caught by the
    # runtime fallback instead of being silently downgraded here.
    assert resolve_device("cuda", []) == CUDA


def test_device_aliases_are_accepted():
    for alias in ("gpu", "nvidia", "CUDA", "  cuda  "):
        assert resolve_device(alias, []) == CUDA


def test_unknown_request_falls_back_to_cpu():
    assert resolve_device("banana", ["CUDAExecutionProvider"]) == CPU


def test_requested_device_from_env():
    assert requested_device_from_env({"OMNIVOICE_ASR_DEVICE": "cuda"}) == "cuda"
    assert requested_device_from_env({"OMNIVOICE_ASR_DEVICE": ""}) is None
    assert requested_device_from_env({}) is None
