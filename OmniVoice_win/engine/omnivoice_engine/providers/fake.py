from omnivoice_engine.schemas import ProviderInfo

from .base import ASRProvider


class FakeASRProvider(ASRProvider):
    id = "fake"
    label = "Fake ASR"

    def info(self) -> ProviderInfo:
        return ProviderInfo(id=self.id, label=self.label, available=True)

    def transcribe(self, audio_bytes: bytes) -> str:
        return "fake transcript"

    def transcribe_pcm_float32(self, pcm_bytes: bytes, sample_rate: int) -> str:
        if len(pcm_bytes) < 4096:
            return "listening"
        return "fake transcript"
