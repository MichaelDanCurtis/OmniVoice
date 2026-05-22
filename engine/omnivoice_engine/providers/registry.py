from __future__ import annotations

from omnivoice_engine.schemas import ProviderInfo

from .base import ASRProvider
from .canary_qwen import CanaryQwenProvider
from .fake import FakeASRProvider
from .parakeet_mlx import ParakeetMLXProvider
from .parakeet_sherpa import ParakeetSherpaProvider
from .whisper_mlx import WhisperMLXProvider


class ProviderRegistry:
    def __init__(self) -> None:
        self._providers: dict[str, ASRProvider] = {
            "fake": FakeASRProvider(),
            "parakeet-tdt": ParakeetSherpaProvider(),
            "parakeet-tdt-mlx": ParakeetMLXProvider(),
            "whisper-large-v3-turbo-mlx-6bit": WhisperMLXProvider(),
            "canary-qwen-2.5b": CanaryQwenProvider(),
        }

    def list_providers(self) -> list[ProviderInfo]:
        return [provider.info() for provider in self._providers.values()]

    def get(self, provider_id: str) -> ASRProvider:
        if provider_id not in self._providers:
            raise KeyError(provider_id)
        return self._providers[provider_id]
