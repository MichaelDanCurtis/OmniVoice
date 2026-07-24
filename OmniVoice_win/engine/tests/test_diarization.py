import sys

from omnivoice_engine.diarization import DiarizationRegistry, WhisperXPyannoteProvider


def test_whisperx_pyannote_provider_is_registered_as_offline_diarization_stack(monkeypatch):
    monkeypatch.setenv("OMNIVOICE_WHISPERX_PYANNOTE_DIR", "/tmp/omnivoice-missing-whisperx-pyannote")

    providers = DiarizationRegistry().list_providers()

    provider = next(provider for provider in providers if provider.id == "whisperx-pyannote")
    assert provider.label == "WhisperX + pyannote"
    assert provider.available is False
    assert "model is not installed" in provider.reason


def test_whisperx_pyannote_provider_requires_runtime(tmp_path, monkeypatch):
    (tmp_path / "config.yaml").write_text("pipeline")
    monkeypatch.delitem(sys.modules, "whisperx", raising=False)
    monkeypatch.delitem(sys.modules, "pyannote.audio", raising=False)

    provider = WhisperXPyannoteProvider(str(tmp_path))

    assert provider.info().available is False
    assert provider.info().reason == "WhisperX runtime is not installed"
