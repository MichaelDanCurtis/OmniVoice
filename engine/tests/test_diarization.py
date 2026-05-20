from pathlib import Path
from types import SimpleNamespace

from omnivoice_engine.diarization import DiarizationAudio, MlxStreamingSortformerProvider, NoDiarizationProvider, _dominant_speaker


def _pretend_apple_silicon(monkeypatch):
    monkeypatch.setattr("omnivoice_engine.diarization.platform.system", lambda: "Darwin")
    monkeypatch.setattr("omnivoice_engine.diarization.platform.machine", lambda: "arm64")


def test_no_diarization_provider_assigns_single_generic_speaker():
    provider = NoDiarizationProvider()

    assignment = provider.assign_speaker(
        session_id="session-1",
        text="hello from the conversation",
        start_ms=0,
        end_ms=1200,
        existing_segments=[],
        audio=None,
    )

    assert provider.info().available is True
    assert assignment.speaker_id == "speaker"
    assert assignment.speaker_display_name == "Speaker"
    assert assignment.confidence is None


def test_mlx_sortformer_provider_requires_runtime_and_local_model(monkeypatch, tmp_path: Path):
    _pretend_apple_silicon(monkeypatch)
    monkeypatch.setattr(
        "omnivoice_engine.diarization.importlib.util.find_spec",
        lambda name: object() if name == "mlx_audio.vad" else None,
    )

    provider = MlxStreamingSortformerProvider(
        provider_id="mlx-sortformer-streaming-fp16",
        label="MLX Sortformer Streaming FP16",
        model_dir=tmp_path,
    )

    info = provider.info()

    assert info.available is False
    assert info.reason == "MLX Sortformer model is not installed"


def test_mlx_sortformer_provider_uses_installed_model(monkeypatch, tmp_path: Path):
    _pretend_apple_silicon(monkeypatch)
    monkeypatch.setattr(
        "omnivoice_engine.diarization.importlib.util.find_spec",
        lambda name: object() if name == "mlx_audio.vad" else None,
    )
    (tmp_path / "config.json").write_text("{}")
    (tmp_path / "model.safetensors").write_text("weights")

    provider = MlxStreamingSortformerProvider(
        provider_id="mlx-sortformer-streaming-fp16",
        label="MLX Sortformer Streaming FP16",
        model_dir=tmp_path,
    )

    assert provider.info().available is True


def test_dominant_speaker_prefers_target_window_overlap():
    speaker_id, confidence = _dominant_speaker(
        [
            {"speaker": "speaker_0", "start": 0.0, "end": 2.0},
            {"speaker": "speaker_1", "start": 2.0, "end": 4.5},
            {"speaker": "speaker_0", "start": 4.5, "end": 8.0},
        ],
        target_start=2.4,
        target_end=3.6,
    )

    assert speaker_id == "speaker-2"
    assert confidence == 0.7


def test_dominant_speaker_keeps_zero_indexed_speaker_ids():
    speaker_id, confidence = _dominant_speaker(
        [
            {"speaker": 0, "start": 0.0, "end": 2.0},
            {"speaker": 1, "start": 2.0, "end": 3.0},
        ],
    )

    assert speaker_id == "speaker-1"
    assert confidence == 0.7


def test_mlx_sortformer_provider_returns_absolute_speaker_turns(tmp_path: Path):
    class FakeModel:
        def generate(self, _path):
            return [
                {"speaker": "speaker_0", "start": 0.0, "end": 1.2, "confidence": 0.81},
                {"speaker": "speaker_1", "start": 1.2, "end": 3.2, "confidence": 0.74},
            ]

    provider = MlxStreamingSortformerProvider(
        provider_id="mlx-sortformer-streaming-fp32",
        label="MLX Sortformer Streaming FP32",
        model_dir=tmp_path,
    )
    provider._model = FakeModel()

    assignment = provider.assign_speaker(
        session_id="session-1",
        text="Bob asked and Sarah answered.",
        start_ms=1_450,
        end_ms=3_450,
        existing_segments=[],
        audio=DiarizationAudio(
            pcm_float32=b"\x00" * 6_400,
            sample_rate=16_000,
            start_ms=250,
            end_ms=3_450,
        ),
    )

    assert assignment.speaker_id == "speaker-2"
    assert [turn.speaker_id for turn in assignment.speaker_turns] == ["speaker-1", "speaker-2"]
    assert [(turn.start_ms, turn.end_ms) for turn in assignment.speaker_turns] == [(250, 1450), (1450, 3450)]


def test_mlx_sortformer_provider_adapts_threshold_when_default_finds_one_speaker(tmp_path: Path):
    class FakeSegment:
        def __init__(self, *, start, end, speaker):
            self.start = start
            self.end = end
            self.speaker = speaker

    class FakeModel:
        config = SimpleNamespace(
            fc_encoder_config=SimpleNamespace(subsampling_factor=8),
        )
        _processor_config = SimpleNamespace(hop_length=160, sampling_rate=16000)

        def generate(self, _path):
            return SimpleNamespace(
                segments=[FakeSegment(start=0.0, end=4.0, speaker=0)],
                speaker_probs="fake-probs",
            )

        @staticmethod
        def _preds_to_segments(_preds, *, frame_duration, threshold, min_duration, merge_gap):
            if threshold > 0.35:
                return [FakeSegment(start=0.0, end=4.0, speaker=0)]
            return [
                FakeSegment(start=0.0, end=1.6, speaker=0),
                FakeSegment(start=1.6, end=4.0, speaker=1),
            ]

    provider = MlxStreamingSortformerProvider(
        provider_id="mlx-sortformer-streaming-fp32",
        label="MLX Sortformer Streaming FP32",
        model_dir=tmp_path,
    )
    provider._model = FakeModel()

    assignment = provider.assign_speaker(
        session_id="session-1",
        text="Bob asked and Sarah answered.",
        start_ms=1_700,
        end_ms=4_250,
        existing_segments=[],
        audio=DiarizationAudio(
            pcm_float32=b"\x00" * 6_400,
            sample_rate=16_000,
            start_ms=250,
            end_ms=4_250,
        ),
    )

    assert assignment.speaker_id == "speaker-2"
    assert [turn.speaker_id for turn in assignment.speaker_turns] == ["speaker-1", "speaker-2"]


def test_mlx_sortformer_provider_reports_runtime_import_error(monkeypatch, tmp_path: Path):
    _pretend_apple_silicon(monkeypatch)

    def broken_find_spec(name):
        raise RuntimeError("MLX runtime exploded")

    monkeypatch.setattr("omnivoice_engine.diarization.importlib.util.find_spec", broken_find_spec)

    provider = MlxStreamingSortformerProvider(
        provider_id="mlx-sortformer-streaming-fp16",
        label="MLX Sortformer Streaming FP16",
        model_dir=tmp_path,
    )

    info = provider.info()

    assert info.available is False
    assert "MLX runtime exploded" in info.reason
