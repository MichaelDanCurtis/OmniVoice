from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
import importlib.util
import os
from pathlib import Path
import struct
import sys
import tempfile
import wave

from .paths import default_model_root
from .schemas import ProviderInfo


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
        existing_segments: list[object],
        audio: DiarizationAudio | None = None,
    ) -> SpeakerAssignment:
        raise NotImplementedError


class NoDiarizationProvider(DiarizationProvider):
    id = "off"
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
        existing_segments: list[object],
        audio: DiarizationAudio | None = None,
    ) -> SpeakerAssignment:
        return SpeakerAssignment(speaker_id="speaker", speaker_display_name="Speaker")


class WhisperXPyannoteProvider(DiarizationProvider):
    id = "whisperx-pyannote"
    label = "WhisperX + pyannote"
    required_files = ("config.yaml",)

    def __init__(
        self,
        model_dir: str | Path | None = None,
        provider_id: str = "whisperx-pyannote",
        label: str = "WhisperX + pyannote",
    ) -> None:
        self.id = provider_id
        self.label = label
        default_dir = default_model_root(__file__) / self.id
        self.model_dir = Path(model_dir or os.environ.get("OMNIVOICE_WHISPERX_PYANNOTE_DIR", default_dir)).expanduser()
        self._pipeline = None

    def info(self) -> ProviderInfo:
        missing = [filename for filename in self.required_files if not (self.model_dir / filename).exists()]
        if missing:
            return ProviderInfo(
                id=self.id,
                label=self.label,
                available=False,
                reason=f"WhisperX + pyannote model is not installed: {', '.join(missing)}",
            )
        if not self._runtime_available("whisperx"):
            return ProviderInfo(id=self.id, label=self.label, available=False, reason="WhisperX runtime is not installed")
        if not self._runtime_available("pyannote.audio"):
            return ProviderInfo(id=self.id, label=self.label, available=False, reason="pyannote.audio runtime is not installed")
        return ProviderInfo(id=self.id, label=self.label, available=True)

    def assign_speaker(
        self,
        *,
        session_id: str,
        text: str,
        start_ms: int,
        end_ms: int | None,
        existing_segments: list[object],
        audio: DiarizationAudio | None = None,
    ) -> SpeakerAssignment:
        info = self.info()
        if not info.available:
            raise RuntimeError(info.reason)
        if audio is None or not audio.pcm_float32:
            raise RuntimeError("audio payload is required for WhisperX + pyannote diarization")

        with tempfile.NamedTemporaryFile(suffix=".wav", delete=True) as handle:
            _write_float32_wav(handle.name, audio.pcm_float32, audio.sample_rate)
            output = self._pyannote_pipeline()(handle.name)

        segments = self._normalize_pyannote_output(output)
        speaker_id, confidence = _dominant_speaker(segments)
        return SpeakerAssignment(
            speaker_id=speaker_id,
            speaker_display_name=_display_name(speaker_id),
            confidence=confidence,
            speaker_turns=_speaker_turns(segments, audio_start_ms=audio.start_ms, source_provider=self.id),
        )

    def _pyannote_pipeline(self):
        if self._pipeline is not None:
            return self._pipeline
        from pyannote.audio import Pipeline

        token = os.environ.get("HF_TOKEN") or os.environ.get("HUGGING_FACE_HUB_TOKEN") or None
        self._pipeline = Pipeline.from_pretrained(str(self.model_dir), use_auth_token=token)
        return self._pipeline

    @staticmethod
    def _runtime_available(module_name: str) -> bool:
        if module_name in sys.modules:
            return True
        try:
            return importlib.util.find_spec(module_name) is not None
        except (ModuleNotFoundError, ValueError):
            return False

    @staticmethod
    def _normalize_pyannote_output(output: object) -> list[dict[str, object]]:
        segments: list[dict[str, object]] = []
        itertracks = getattr(output, "itertracks", None)
        if callable(itertracks):
            for segment, _track, speaker in itertracks(yield_label=True):
                segments.append(
                    {
                        "speaker": speaker,
                        "start": getattr(segment, "start", 0),
                        "end": getattr(segment, "end", 0),
                    }
                )
        return segments


class DiarizationRegistry:
    def __init__(self) -> None:
        self._providers: dict[str, DiarizationProvider] = {
            "off": NoDiarizationProvider(),
            "whisperx-pyannote": WhisperXPyannoteProvider(),
        }

    def list_providers(self) -> list[ProviderInfo]:
        return [provider.info() for provider in self._providers.values()]

    def get(self, provider_id: str) -> DiarizationProvider:
        if provider_id not in self._providers:
            raise KeyError(provider_id)
        return self._providers[provider_id]


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


def _dominant_speaker(segments: list[dict[str, object]]) -> tuple[str, float | None]:
    totals: dict[str, float] = {}
    for segment in segments:
        raw_speaker = segment.get("speaker")
        if raw_speaker is None:
            continue
        speaker_id = _speaker_id(str(raw_speaker))
        start = float(segment.get("start") or 0)
        end = float(segment.get("end") or start)
        duration = max(0.0, end - start)
        if duration > 0:
            totals[speaker_id] = totals.get(speaker_id, 0.0) + duration
    if not totals:
        return "speaker-1", 0.5
    return max(totals, key=totals.get), 0.7


def _speaker_turns(
    segments: list[dict[str, object]],
    *,
    audio_start_ms: int,
    source_provider: str,
) -> tuple[SpeakerTurnAssignment, ...]:
    turns: list[SpeakerTurnAssignment] = []
    for segment in segments:
        raw_speaker = segment.get("speaker")
        if raw_speaker is None:
            continue
        start = float(segment.get("start") or 0)
        end = float(segment.get("end") or start)
        turns.append(
            SpeakerTurnAssignment(
                speaker_id=_speaker_id(str(raw_speaker)),
                start_ms=audio_start_ms + int(round(start * 1_000)),
                end_ms=audio_start_ms + int(round(end * 1_000)),
                source_provider=source_provider,
            )
        )
    return tuple(turns)


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
