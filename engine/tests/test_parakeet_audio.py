"""Exercise native audio decoding when the optional Apple Silicon runtime exists."""
from types import SimpleNamespace

import pytest

np = pytest.importorskip("numpy")
sf = pytest.importorskip("soundfile")
mx = pytest.importorskip("mlx.core")
audio = pytest.importorskip("parakeet_mlx.audio")

from omnivoice_engine.providers.parakeet_mlx import ParakeetMLXProvider


def test_audio_decodes_and_resamples_stereo_without_ffmpeg(tmp_path, monkeypatch):
    path = tmp_path / "recording.wav"
    samples = np.tile(np.array([0.5, -0.25], dtype=np.float32), (48000, 1))
    sf.write(path, samples, 48000, subtype="FLOAT")
    config = SimpleNamespace(sample_rate=16000, hop_length=160)
    captured = {}

    def logmel(samples, received_config):
        captured["samples"] = np.array(samples)
        assert received_config is config
        return "mel"

    def forbid_subprocess(*args, **kwargs):
        pytest.fail("Audio decoding must not invoke an external executable")

    monkeypatch.setattr(audio, "get_logmel", logmel)
    monkeypatch.setattr("subprocess.Popen", forbid_subprocess)
    monkeypatch.setenv("PATH", "/usr/bin:/bin")

    assert ParakeetMLXProvider()._audio_features(str(path), config) == "mel"
    assert captured["samples"].shape == (16000,)
    np.testing.assert_allclose(captured["samples"][100:-100], 0.125, atol=1e-4)


def test_audio_shorter_than_one_hop_returns_empty_transcript(tmp_path):
    path = tmp_path / "short.wav"
    sf.write(path, np.zeros(16, dtype=np.float32), 16000)
    provider = ParakeetMLXProvider()
    provider._model = SimpleNamespace(
        preprocessor_config=SimpleNamespace(sample_rate=16000, hop_length=160)
    )

    assert provider._transcribe_file_aligned(str(path)).text == ""
