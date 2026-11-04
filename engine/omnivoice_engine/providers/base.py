from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass

from omnivoice_engine.schemas import ProviderInfo


@dataclass(frozen=True)
class ASRToken:
    text: str
    start_ms: int | None = None
    end_ms: int | None = None
    confidence: float | None = None


@dataclass(frozen=True)
class ASRSentence:
    text: str
    start_ms: int | None = None
    end_ms: int | None = None
    confidence: float | None = None
    tokens: tuple[ASRToken, ...] = ()


@dataclass(frozen=True)
class ASRTranscript:
    text: str
    sentences: tuple[ASRSentence, ...] = ()
    tokens: tuple[ASRToken, ...] = ()


class ASRProvider(ABC):
    id: str
    label: str

    @abstractmethod
    def info(self) -> ProviderInfo:
        raise NotImplementedError

    @abstractmethod
    def transcribe(self, audio_bytes: bytes) -> str:
        raise NotImplementedError

    def warm_up(self) -> None:
        return None

    def transcribe_pcm_float32(self, pcm_bytes: bytes, sample_rate: int) -> str:
        return self.transcribe(pcm_bytes)

    def transcribe_aligned_pcm_float32(self, pcm_bytes: bytes, sample_rate: int) -> ASRTranscript:
        return ASRTranscript(text=self.transcribe_pcm_float32(pcm_bytes, sample_rate))


class UnavailableASRProvider(ASRProvider):
    def __init__(self, provider_id: str, label: str, reason: str) -> None:
        self.id = provider_id
        self.label = label
        self._reason = reason

    def info(self) -> ProviderInfo:
        return ProviderInfo(id=self.id, label=self.label, available=False, reason=self._reason)

    def transcribe(self, audio_bytes: bytes) -> str:
        raise RuntimeError(self._reason)
