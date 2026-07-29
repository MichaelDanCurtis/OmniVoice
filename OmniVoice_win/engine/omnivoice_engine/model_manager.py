from __future__ import annotations

import json
import os
import threading
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Protocol

from huggingface_hub import HfApi, snapshot_download

from .paths import default_model_root
from .schemas import ModelDownloadStatus, ModelStatus, ModelUpdateInfo


class HubApi(Protocol):
    def model_info(self, repo_id: str):
        ...


SnapshotDownloader = Callable[..., str]


@dataclass(frozen=True)
class ModelSpec:
    provider_id: str
    label: str
    repo_id: str
    local_dir: Path
    required_files: list[str]
    allow_patterns: list[str]


class ModelManager:
    metadata_filename = ".omnivoice-model.json"

    def __init__(
        self,
        model_root: str | Path | None = None,
        hub_api: HubApi | None = None,
        snapshot_downloader: SnapshotDownloader | None = None,
    ) -> None:
        root = Path(model_root).expanduser() if model_root is not None else default_model_root(__file__)
        parakeet_dir = Path(os.environ.get("OMNIVOICE_PARAKEET_MODEL_DIR", root / "parakeet-tdt")).expanduser()
        moonshine_dir = Path(os.environ.get("OMNIVOICE_MOONSHINE_MODEL_DIR", root / "moonshine-base-en")).expanduser()
        canary_dir = Path(os.environ.get("OMNIVOICE_CANARY_MODEL_DIR", root / "canary-qwen-2.5b")).expanduser()

        self.hub_api = hub_api or HfApi()
        self.snapshot_downloader = snapshot_downloader or snapshot_download
        self._lock = threading.Lock()
        self._download_states: dict[str, ModelDownloadStatus] = {}
        self._specs: dict[str, ModelSpec] = {
            "parakeet-tdt": ModelSpec(
                provider_id="parakeet-tdt",
                label="Parakeet TDT",
                repo_id="csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8",
                local_dir=parakeet_dir,
                required_files=["encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"],
                allow_patterns=["encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"],
            ),
            "moonshine-base-en": ModelSpec(
                provider_id="moonshine-base-en",
                label="Moonshine Base (English)",
                repo_id="csukuangfj/sherpa-onnx-moonshine-base-en-int8",
                local_dir=moonshine_dir,
                required_files=[
                    "preprocess.onnx",
                    "encode.int8.onnx",
                    "uncached_decode.int8.onnx",
                    "cached_decode.int8.onnx",
                    "tokens.txt",
                ],
                allow_patterns=[
                    "preprocess.onnx",
                    "encode.int8.onnx",
                    "uncached_decode.int8.onnx",
                    "cached_decode.int8.onnx",
                    "tokens.txt",
                ],
            ),
            "canary-qwen-2.5b": ModelSpec(
                provider_id="canary-qwen-2.5b",
                label="Canary-Qwen-2.5B",
                repo_id="nvidia/canary-qwen-2.5b",
                local_dir=canary_dir,
                required_files=["config.json", "model.safetensors"],
                allow_patterns=["config.json", "model.safetensors", "README.md", "LICENSES"],
            ),
        }

    def list_statuses(self) -> list[ModelStatus]:
        return [self.status(provider_id) for provider_id in self._specs]

    def status(self, provider_id: str) -> ModelStatus:
        spec = self._spec(provider_id)
        missing_files = self._missing_files(spec)
        metadata = self._read_metadata(spec)
        download_state = self.download_state(provider_id)
        return ModelStatus(
            provider_id=spec.provider_id,
            label=spec.label,
            repo_id=spec.repo_id,
            local_path=str(spec.local_dir),
            installed=not missing_files,
            installed_revision=metadata.get("revision"),
            missing_files=missing_files,
            download_state=download_state.state,
            download_message=download_state.message,
        )

    def check_update(self, provider_id: str) -> ModelUpdateInfo:
        spec = self._spec(provider_id)
        remote_revision = self._remote_revision(spec)
        installed_revision = self._read_metadata(spec).get("revision")
        return ModelUpdateInfo(
            provider_id=spec.provider_id,
            repo_id=spec.repo_id,
            installed_revision=installed_revision,
            remote_revision=remote_revision,
            update_available=installed_revision != remote_revision,
        )

    def start_download(self, provider_id: str) -> ModelDownloadStatus:
        spec = self._spec(provider_id)
        with self._lock:
            current = self._download_states.get(provider_id)
            if current and current.state in {"queued", "downloading"}:
                return current
            state = ModelDownloadStatus(
                provider_id=provider_id,
                state="queued",
                message="Download queued",
                local_path=str(spec.local_dir),
                revision=None,
            )
            self._download_states[provider_id] = state
            return state

    def download(self, provider_id: str) -> ModelDownloadStatus:
        spec = self._spec(provider_id)
        self._set_download_state(
            ModelDownloadStatus(
                provider_id=provider_id,
                state="downloading",
                message=f"Downloading {spec.label} from Hugging Face",
                local_path=str(spec.local_dir),
                revision=None,
            )
        )
        try:
            remote_revision = self._remote_revision(spec)
            spec.local_dir.mkdir(parents=True, exist_ok=True)
            self.snapshot_downloader(
                repo_id=spec.repo_id,
                repo_type="model",
                local_dir=str(spec.local_dir),
                allow_patterns=spec.allow_patterns,
            )
            missing_files = self._missing_files(spec)
            if missing_files:
                raise RuntimeError(f"download missing required files: {', '.join(missing_files)}")
            self._write_metadata(spec, remote_revision)
            state = ModelDownloadStatus(
                provider_id=provider_id,
                state="completed",
                message=f"{spec.label} is ready",
                local_path=str(spec.local_dir),
                revision=remote_revision,
            )
            self._set_download_state(state)
            return state
        except Exception as exc:
            state = ModelDownloadStatus(
                provider_id=provider_id,
                state="failed",
                message=str(exc),
                local_path=str(spec.local_dir),
                revision=None,
            )
            self._set_download_state(state)
            raise

    def download_state(self, provider_id: str) -> ModelDownloadStatus:
        spec = self._spec(provider_id)
        with self._lock:
            return self._download_states.get(
                provider_id,
                ModelDownloadStatus(
                    provider_id=provider_id,
                    state="idle",
                    message=None,
                    local_path=str(spec.local_dir),
                    revision=self._read_metadata(spec).get("revision"),
                ),
            )

    def _set_download_state(self, state: ModelDownloadStatus) -> None:
        with self._lock:
            self._download_states[state.provider_id] = state

    def _spec(self, provider_id: str) -> ModelSpec:
        if provider_id not in self._specs:
            raise KeyError(provider_id)
        return self._specs[provider_id]

    def _missing_files(self, spec: ModelSpec) -> list[str]:
        return [filename for filename in spec.required_files if not (spec.local_dir / filename).exists()]

    def _remote_revision(self, spec: ModelSpec) -> str:
        info = self.hub_api.model_info(spec.repo_id)
        revision = getattr(info, "sha", None)
        if not revision:
            raise RuntimeError(f"no revision returned for {spec.repo_id}")
        return revision

    def _metadata_path(self, spec: ModelSpec) -> Path:
        return spec.local_dir / self.metadata_filename

    def _read_metadata(self, spec: ModelSpec) -> dict:
        path = self._metadata_path(spec)
        if not path.exists():
            return {}
        try:
            return json.loads(path.read_text())
        except (OSError, json.JSONDecodeError):
            return {}

    def _write_metadata(self, spec: ModelSpec, revision: str) -> None:
        payload = {
            "provider_id": spec.provider_id,
            "repo_id": spec.repo_id,
            "revision": revision,
            "downloaded_at": datetime.now(timezone.utc).isoformat(),
        }
        self._metadata_path(spec).write_text(json.dumps(payload, indent=2, sort_keys=True))
