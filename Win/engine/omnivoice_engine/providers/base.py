from __future__ import annotations

from abc import ABC, abstractmethod

from omnivoice_engine.schemas import ProviderInfo


class ASRProvider(ABC):
    id: str
    label: str

    @abstractmethod
    def info(self) -> ProviderInfo:
        raise NotImplementedError

    @abstractmethod
    def transcribe(self, audio_bytes: bytes) -> str:
        raise NotImplementedError

    def transcribe_pcm_float32(self, pcm_bytes: bytes, sample_rate: int) -> str:
        return self.transcribe(pcm_bytes)


class UnavailableASRProvider(ASRProvider):
    def __init__(self, provider_id: str, label: str, reason: str) -> None:
        self.id = provider_id
        self.label = label
        self._reason = reason

    def info(self) -> ProviderInfo:
        return ProviderInfo(id=self.id, label=self.label, available=False, reason=self._reason)

    def transcribe(self, audio_bytes: bytes) -> str:
        raise RuntimeError(self._reason)
