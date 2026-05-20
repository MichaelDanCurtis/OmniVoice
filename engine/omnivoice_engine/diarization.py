from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
import importlib
import importlib.util
import os
import platform
from pathlib import Path
import struct
import tempfile
import wave

from .paths import default_model_root
from omnivoice_engine.schemas import ConversationSegmentRecord, ProviderInfo


@dataclass(frozen=True)
class SpeakerAssignment:
    speaker_id: str
    speaker_display_name: str
    confidence: float | None = None
    speaker_turns: tuple["SpeakerTurnAssignment", ...] = ()


@dataclass(frozen=True)
class SpeakerTurnAssignment:
    speaker_id: str
    start_ms: int
    end_ms: int | None = None
    confidence: float | None = None
    overlap: bool = False
    source_provider: str = ""


@dataclass(frozen=True)
class DiarizationAudio:
    pcm_float32: bytes
    sample_rate: int
    start_ms: int
    end_ms: int | None = None


class DiarizationProvider(ABC):
    id: str
    label: str

    @abstractmethod
    def info(self) -> ProviderInfo:
        raise NotImplementedError

    @abstractmethod
    def assign_speaker(
        self,
        *,
        session_id: str,
        text: str,
        start_ms: int,
        end_ms: int | None,
        existing_segments: list[ConversationSegmentRecord],
        audio: DiarizationAudio | None = None,
    ) -> SpeakerAssignment:
        raise NotImplementedError


class LocalHeuristicDiarizationProvider(DiarizationProvider):
    id = "local-heuristic"
    label = "Local Heuristic"

    def info(self) -> ProviderInfo:
        return ProviderInfo(id=self.id, label=self.label, available=True)

    def assign_speaker(
        self,
        *,
        session_id: str,
        text: str,
        start_ms: int,
        end_ms: int | None,
        existing_segments: list[ConversationSegmentRecord],
        audio: DiarizationAudio | None = None,
    ) -> SpeakerAssignment:
        normalized = text.strip().lower()
        if normalized.startswith(("i ", "i'm ", "im ")):
            return SpeakerAssignment(speaker_id="you", speaker_display_name="You", confidence=0.55)

        non_user_segments = [segment for segment in existing_segments if segment.speaker_id != "you"]
        speaker_number = (len(non_user_segments) % 3) + 1
        return SpeakerAssignment(
            speaker_id=f"speaker-{speaker_number}",
            speaker_display_name=f"Speaker {speaker_number}",
            confidence=0.35,
        )


class NoDiarizationProvider(DiarizationProvider):
    id = "none"
    label = "Off"

    def info(self) -> ProviderInfo:
        return ProviderInfo(id=self.id, label=self.label, available=True)

    def assign_speaker(
        self,
        *,
        session_id: str,
        text: str,
        start_ms: int,
        end_ms: int | None,
        existing_segments: list[ConversationSegmentRecord],
        audio: DiarizationAudio | None = None,
    ) -> SpeakerAssignment:
        return SpeakerAssignment(speaker_id="speaker", speaker_display_name="Speaker", confidence=None)


class UnavailableDiarizationProvider(DiarizationProvider):
    def __init__(self, provider_id: str, label: str, reason: str) -> None:
        self.id = provider_id
        self.label = label
        self._reason = reason

    def info(self) -> ProviderInfo:
        return ProviderInfo(id=self.id, label=self.label, available=False, reason=self._reason)

    def assign_speaker(
        self,
        *,
        session_id: str,
        text: str,
        start_ms: int,
        end_ms: int | None,
        existing_segments: list[ConversationSegmentRecord],
        audio: DiarizationAudio | None = None,
    ) -> SpeakerAssignment:
        raise RuntimeError(self._reason)


def _write_float32_wav(path: str, pcm_float32: bytes, sample_rate: int) -> None:
    sample_count = len(pcm_float32) // 4
    pcm16 = bytearray(sample_count * 2)
    for index in range(sample_count):
        sample = struct.unpack_from("<f", pcm_float32, index * 4)[0]
        clipped = min(max(sample, -1.0), 1.0)
        value = int(clipped * 32767.0) if clipped >= 0 else int(clipped * 32768.0)
        struct.pack_into("<h", pcm16, index * 2, value)

    with wave.open(path, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(sample_rate)
        wav.writeframes(bytes(pcm16))


def _dominant_speaker(
    segments: list[dict[str, object]],
    *,
    target_start: float | None = None,
    target_end: float | None = None,
) -> tuple[str, float | None]:
    totals: dict[str, float] = {}
    confidences: dict[str, list[float]] = {}
    use_target = target_start is not None and target_end is not None and target_end > target_start
    for segment in segments:
        raw_speaker = _segment_value(segment, "speaker", "speaker_id", "label")
        if raw_speaker is None:
            continue
        speaker_id = _speaker_id(str(raw_speaker))
        start = float(_segment_value(segment, "start", "start_ms") or 0)
        end = float(_segment_value(segment, "end", "end_ms") or start)
        if use_target:
            duration = max(0.0, min(end, target_end) - max(start, target_start))
        else:
            duration = max(0.0, end - start)
        if duration <= 0:
            continue
        totals[speaker_id] = totals.get(speaker_id, 0.0) + duration
        if isinstance(segment.get("confidence"), int | float):
            confidences.setdefault(speaker_id, []).append(float(segment["confidence"]))

    if not totals and use_target:
        return _dominant_speaker(segments)
    if not totals:
        return "speaker-1", 0.5
    speaker_id = max(totals, key=totals.get)
    if confidences.get(speaker_id):
        confidence = sum(confidences[speaker_id]) / len(confidences[speaker_id])
    else:
        confidence = 0.7
    return speaker_id, confidence


def _segment_value(segment: dict[str, object], *keys: str) -> object | None:
    for key in keys:
        if key in segment and segment[key] is not None:
            return segment[key]
    return None


def _speaker_id(raw: str) -> str:
    suffix = raw.strip().lower().replace("speaker", "").replace("_", "").replace("-", "")
    if suffix.isdigit():
        return f"speaker-{int(suffix) + 1}"
    return raw.strip().lower().replace("_", "-") or "speaker-1"


def _display_name(speaker_id: str) -> str:
    suffix = speaker_id.removeprefix("speaker-")
    if suffix.isdigit():
        return f"Speaker {suffix}"
    return speaker_id.replace("-", " ").title()


def _speaker_turns(
    segments: list[dict[str, object]],
    *,
    audio_start_ms: int,
    source_provider: str,
) -> tuple[SpeakerTurnAssignment, ...]:
    turns: list[SpeakerTurnAssignment] = []
    for segment in segments:
        raw_speaker = _segment_value(segment, "speaker", "speaker_id", "label")
        if raw_speaker is None:
            continue
        start = float(_segment_value(segment, "start", "start_ms") or 0)
        end = float(_segment_value(segment, "end", "end_ms") or start)
        start_ms = audio_start_ms + int(round(start * 1_000))
        end_ms = audio_start_ms + int(round(end * 1_000))
        if end_ms < start_ms:
            continue
        confidence = segment.get("confidence")
        turns.append(
            SpeakerTurnAssignment(
                speaker_id=_speaker_id(str(raw_speaker)),
                start_ms=start_ms,
                end_ms=end_ms,
                confidence=float(confidence) if isinstance(confidence, int | float) else None,
                overlap=bool(segment.get("overlap") or segment.get("overlapped") or False),
                source_provider=source_provider,
            )
        )
    return tuple(turns)


def _unique_speaker_count(segments: list[dict[str, object]]) -> int:
    speakers: set[str] = set()
    for segment in segments:
        raw_speaker = _segment_value(segment, "speaker", "speaker_id", "label")
        if raw_speaker is not None:
            speakers.add(_speaker_id(str(raw_speaker)))
    return len(speakers)


class MlxStreamingSortformerProvider(DiarizationProvider):
    required_files = ("config.json", "model.safetensors")

    def __init__(
        self,
        provider_id: str,
        label: str,
        model_dir: str | Path | None = None,
    ) -> None:
        self.id = provider_id
        self.label = label
        root = default_model_root(__file__)
        default_dir = root / provider_id
        env_name = "OMNIVOICE_MLX_SORTFORMER_FP32_DIR" if provider_id.endswith("fp32") else "OMNIVOICE_MLX_SORTFORMER_FP16_DIR"
        self.model_dir = Path(model_dir or os.environ.get(env_name, default_dir)).expanduser()
        self._model = None

    def info(self) -> ProviderInfo:
        runtime_error = self._runtime_unavailable_reason()
        if runtime_error is not None:
            return ProviderInfo(id=self.id, label=self.label, available=False, reason=runtime_error)
        if not self._model_installed():
            return ProviderInfo(id=self.id, label=self.label, available=False, reason="MLX Sortformer model is not installed")
        return ProviderInfo(id=self.id, label=self.label, available=True)

    @classmethod
    def _runtime_unavailable_reason(cls) -> str | None:
        if platform.system().lower() != "darwin" or platform.machine().lower() not in {"arm64", "aarch64"}:
            return "MLX Sortformer requires Apple Silicon macOS"
        try:
            if importlib.util.find_spec("mlx_audio.vad") is not None:
                return None
        except ModuleNotFoundError:
            pass
        except Exception as exc:
            return f"MLX Sortformer runtime is not available: {exc}"
        return "MLX Sortformer runtime is not installed"

    def assign_speaker(
        self,
        *,
        session_id: str,
        text: str,
        start_ms: int,
        end_ms: int | None,
        existing_segments: list[ConversationSegmentRecord],
        audio: DiarizationAudio | None = None,
    ) -> SpeakerAssignment:
        if audio is None or not audio.pcm_float32:
            raise RuntimeError("audio payload is required for MLX Sortformer diarization")

        model = self._mlx_model()
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=True) as handle:
            _write_float32_wav(handle.name, audio.pcm_float32, audio.sample_rate)
            output = model.generate(handle.name)

        normalized_output = self._normalize_output(output)
        normalized_output = self._adaptive_segments_from_output(model, output, normalized_output)
        target_start = max(0.0, (start_ms - audio.start_ms) / 1_000)
        target_end = max(target_start, ((end_ms or start_ms) - audio.start_ms) / 1_000)
        speaker_id, confidence = _dominant_speaker(
            normalized_output,
            target_start=target_start,
            target_end=target_end,
        )
        return SpeakerAssignment(
            speaker_id=speaker_id,
            speaker_display_name=_display_name(speaker_id),
            confidence=confidence,
            speaker_turns=_speaker_turns(
                normalized_output,
                audio_start_ms=audio.start_ms,
                source_provider=self.id,
            ),
        )

    @staticmethod
    def _adaptive_segments_from_output(
        model: object,
        output: object,
        current_segments: list[dict[str, object]],
    ) -> list[dict[str, object]]:
        current_count = _unique_speaker_count(current_segments)
        if current_count > 1:
            return current_segments

        speaker_probs = getattr(output, "speaker_probs", None)
        if speaker_probs is None or not hasattr(model, "_preds_to_segments"):
            return current_segments

        try:
            processor = getattr(model, "_processor_config")
            hop_length = float(getattr(processor, "hop_length"))
            sample_rate = float(getattr(processor, "sampling_rate"))
            subsampling_factor = float(getattr(model.config.fc_encoder_config, "subsampling_factor"))
            frame_duration = (hop_length * subsampling_factor) / sample_rate
        except Exception:
            return current_segments

        best_segments = current_segments
        best_count = current_count
        for threshold in (0.45, 0.40, 0.35, 0.30, 0.25):
            try:
                candidate = model._preds_to_segments(
                    speaker_probs,
                    frame_duration=frame_duration,
                    threshold=threshold,
                    min_duration=0.20,
                    merge_gap=0.12,
                )
            except Exception:
                continue
            normalized = MlxStreamingSortformerProvider._normalize_output(candidate)
            speaker_count = _unique_speaker_count(normalized)
            if speaker_count > best_count:
                best_segments = normalized
                best_count = speaker_count
            if speaker_count > 1:
                return normalized

        return best_segments

    def _model_installed(self) -> bool:
        return all((self.model_dir / filename).exists() for filename in self.required_files)

    def _mlx_model(self):
        if self._model is not None:
            return self._model
        module = importlib.import_module("mlx_audio.vad")
        self._model = module.load(str(self.model_dir), lazy=False, strict=False)
        return self._model

    @staticmethod
    def _normalize_output(output: object) -> list[dict[str, object]]:
        raw_segments = getattr(output, "segments", output)
        if raw_segments is None:
            return []
        normalized = []
        for segment in raw_segments:
            if isinstance(segment, dict):
                normalized.append(segment)
                continue
            normalized.append(
                {
                    "speaker": getattr(segment, "speaker", None),
                    "start": getattr(segment, "start", 0),
                    "end": getattr(segment, "end", 0),
                }
            )
        return normalized


class DiarizationRegistry:
    def __init__(self) -> None:
        self._providers: dict[str, DiarizationProvider] = {
            "none": NoDiarizationProvider(),
            "mlx-sortformer-streaming-fp16": MlxStreamingSortformerProvider(
                "mlx-sortformer-streaming-fp16",
                "MLX Sortformer Streaming FP16",
            ),
            "mlx-sortformer-streaming-fp32": MlxStreamingSortformerProvider(
                "mlx-sortformer-streaming-fp32",
                "MLX Sortformer Streaming FP32",
            ),
            "local-heuristic": LocalHeuristicDiarizationProvider(),
            "pyannote": UnavailableDiarizationProvider(
                "pyannote",
                "pyannote.audio",
                "pyannote.audio runtime and model access are not configured in this local build",
            ),
        }

    def list_providers(self) -> list[ProviderInfo]:
        return [provider.info() for provider in self._providers.values()]

    def get(self, provider_id: str) -> DiarizationProvider:
        if provider_id not in self._providers:
            raise KeyError(provider_id)
        return self._providers[provider_id]
