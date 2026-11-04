from __future__ import annotations

import json
import os
import shutil
import threading
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Protocol

from huggingface_hub import HfApi, get_token, snapshot_download
from huggingface_hub.errors import GatedRepoError, HfHubHTTPError

from .paths import default_model_root
from .schemas import HuggingFaceAuthStatus, ModelDownloadStatus, ModelStatus, ModelUpdateInfo


class HubApi(Protocol):
    def model_info(self, repo_id: str, token: str | None = None):
        ...

    def whoami(self, token: str | None = None):
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
    category: str = "asr"
    recommendation: str | None = None
    detail: str | None = None
    size: str | None = None
    precision: str | None = None
    requires_hf_auth: bool = False
    agreement_url: str | None = None
    license: str | None = None


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
        parakeet_mlx_dir = Path(
            os.environ.get("OMNIVOICE_PARAKEET_MLX_MODEL_DIR", root / "parakeet-tdt-mlx")
        ).expanduser()
        whisper_mlx_dir = Path(
            os.environ.get("OMNIVOICE_WHISPER_MLX_MODEL_DIR", root / "whisper-large-v3-turbo-mlx-6bit")
        ).expanduser()
        sensevoice_dir = Path(
            os.environ.get("OMNIVOICE_SENSEVOICE_MODEL_DIR", root / "sensevoice-small-funasr")
        ).expanduser()
        canary_dir = Path(os.environ.get("OMNIVOICE_CANARY_MODEL_DIR", root / "canary-qwen-2.5b")).expanduser()
        translategemma_dir = Path(
            os.environ.get("OMNIVOICE_TRANSLATEGEMMA_MLX_MODEL_DIR", root / "translategemma-mlx")
        ).expanduser()
        translategemma_4b_8bit_dir = Path(
            os.environ.get("OMNIVOICE_TRANSLATEGEMMA_MLX_4B_8BIT_DIR", root / "translategemma-mlx-4b-8bit")
        ).expanduser()
        translategemma_12b_4bit_dir = Path(
            os.environ.get("OMNIVOICE_TRANSLATEGEMMA_MLX_12B_4BIT_DIR", root / "translategemma-mlx-12b-4bit")
        ).expanduser()
        sarvam_translate_dir = Path(
            os.environ.get("OMNIVOICE_SARVAM_TRANSLATE_MLX_4BIT_DIR", root / "sarvam-translate-mlx-4bit")
        ).expanduser()
        plamo_translate_dir = Path(
            os.environ.get("OMNIVOICE_PLAMO_2_TRANSLATE_MLX_DIR", root / "plamo-2-translate-mlx")
        ).expanduser()
        mlx_sortformer_fp16_dir = Path(
            os.environ.get("OMNIVOICE_MLX_SORTFORMER_FP16_DIR", root / "mlx-sortformer-streaming-fp16")
        ).expanduser()
        mlx_sortformer_fp32_dir = Path(
            os.environ.get("OMNIVOICE_MLX_SORTFORMER_FP32_DIR", root / "mlx-sortformer-streaming-fp32")
        ).expanduser()
        whisperx_pyannote_dir = Path(
            os.environ.get("OMNIVOICE_WHISPERX_PYANNOTE_DIR", root / "whisperx-pyannote")
        ).expanduser()

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
            "parakeet-tdt-mlx": ModelSpec(
                provider_id="parakeet-tdt-mlx",
                label="Parakeet TDT MLX",
                repo_id="mlx-community/parakeet-tdt-0.6b-v3",
                local_dir=parakeet_mlx_dir,
                required_files=["config.json", "model.safetensors"],
                allow_patterns=["config.json", "model.safetensors", "README.md"],
            ),
            "whisper-large-v3-turbo-mlx-6bit": ModelSpec(
                provider_id="whisper-large-v3-turbo-mlx-6bit",
                label="Whisper Large v3 Turbo MLX 6-bit",
                repo_id="mlx-community/whisper-large-v3-turbo-asr-6bit",
                local_dir=whisper_mlx_dir,
                required_files=["config.json", "model.safetensors", "tokenizer.json", "preprocessor_config.json"],
                allow_patterns=whisper_mlx_allow_patterns(),
                recommendation="Multilingual",
                detail="Local multilingual ASR for 99-language dictation on Apple Silicon.",
                size="664 MB",
                precision="6-bit",
                license="mit",
            ),
            "sensevoice-small-funasr": ModelSpec(
                provider_id="sensevoice-small-funasr",
                label="SenseVoice Small FunASR",
                repo_id="FunAudioLLM/SenseVoiceSmall",
                local_dir=sensevoice_dir,
                required_files=["config.yaml", "model.pt", "am.mvn", "chn_jpn_yue_eng_ko_spectok.bpe.model"],
                allow_patterns=sensevoice_allow_patterns(),
                recommendation="Fast Multilingual",
                detail="Fast local multilingual ASR through FunASR/SenseVoice with CJK coverage and rich tags.",
                size="900 MB",
                precision="FP32",
                license="model-license",
            ),
            "canary-qwen-2.5b": ModelSpec(
                provider_id="canary-qwen-2.5b",
                label="Canary-Qwen-2.5B",
                repo_id="nvidia/canary-qwen-2.5b",
                local_dir=canary_dir,
                required_files=["config.json", "model.safetensors"],
                allow_patterns=["config.json", "model.safetensors", "README.md", "LICENSES"],
                recommendation="English Accuracy",
                detail="Advanced English ASR through NVIDIA NeMo when the Canary runtime is installed.",
                size="5.1 GB",
                precision="BF16",
                license="cc-by-4.0",
            ),
            "translategemma-mlx": ModelSpec(
                provider_id="translategemma-mlx",
                label="TranslateGemma 4B 4-bit",
                repo_id="mlx-community/translategemma-4b-it-4bit",
                local_dir=translategemma_dir,
                required_files=["config.json", "model.safetensors", "tokenizer.json"],
                allow_patterns=translategemma_allow_patterns(),
                category="translation",
                recommendation="Fast / Recommended",
                detail="Default low-latency local translation model for Apple Silicon.",
                size="2.18 GB",
                precision="4-bit",
                requires_hf_auth=True,
                agreement_url="https://huggingface.co/google/translategemma-4b-it",
                license="gemma",
            ),
            "translategemma-mlx-4b-8bit": ModelSpec(
                provider_id="translategemma-mlx-4b-8bit",
                label="TranslateGemma 4B 8-bit",
                repo_id="mlx-community/translategemma-4b-it-8bit",
                local_dir=translategemma_4b_8bit_dir,
                required_files=["config.json", "model.safetensors", "tokenizer.json"],
                allow_patterns=translategemma_allow_patterns(),
                category="translation",
                recommendation="Balanced Quality",
                detail="Cleaner 4B translation output with a larger download and higher memory use.",
                size="4.12 GB",
                precision="8-bit",
                requires_hf_auth=True,
                agreement_url="https://huggingface.co/google/translategemma-4b-it",
                license="gemma",
            ),
            "translategemma-mlx-12b-4bit": ModelSpec(
                provider_id="translategemma-mlx-12b-4bit",
                label="TranslateGemma 12B 4-bit",
                repo_id="mlx-community/translategemma-12b-it-4bit",
                local_dir=translategemma_12b_4bit_dir,
                required_files=["config.json", "model-*.safetensors", "tokenizer.json"],
                allow_patterns=translategemma_12b_allow_patterns(),
                category="translation",
                recommendation="Quality / High-End Mac",
                detail="Higher-quality TranslateGemma option for Macs with more memory.",
                size="6.62 GB",
                precision="4-bit",
                requires_hf_auth=True,
                agreement_url="https://huggingface.co/google/translategemma-12b-it",
                license="gemma",
            ),
            "sarvam-translate-mlx-4bit": ModelSpec(
                provider_id="sarvam-translate-mlx-4bit",
                label="Sarvam Translate 4-bit",
                repo_id="mlx-community/sarvam-translate-mlx-4bit",
                local_dir=sarvam_translate_dir,
                required_files=["config.json", "model.safetensors", "tokenizer.json"],
                allow_patterns=translategemma_allow_patterns(),
                category="translation",
                recommendation="Indic Languages",
                detail="Specialized translation model for Indic-language coverage.",
                size="2.56 GB",
                precision="4-bit",
                requires_hf_auth=False,
                agreement_url="https://huggingface.co/mlx-community/sarvam-translate-mlx-4bit",
                license="gpl-3.0",
            ),
            "plamo-2-translate-mlx": ModelSpec(
                provider_id="plamo-2-translate-mlx",
                label="PLaMo 2 Translate",
                repo_id="mlx-community/plamo-2-translate",
                local_dir=plamo_translate_dir,
                required_files=["config.json", "model.safetensors", "tokenizer.jsonl", "modeling_plamo.py", "tokenization_plamo.py"],
                allow_patterns=plamo_allow_patterns(),
                category="translation",
                recommendation="Japanese / English Specialist",
                detail="Specialized Japanese-English translation model with separate license constraints.",
                size=None,
                precision="4-bit",
                requires_hf_auth=False,
                agreement_url="https://huggingface.co/mlx-community/plamo-2-translate",
                license="plamo-community-license",
            ),
            "mlx-sortformer-streaming-fp16": ModelSpec(
                provider_id="mlx-sortformer-streaming-fp16",
                label="MLX Sortformer Streaming FP16",
                repo_id="mlx-community/diar_streaming_sortformer_4spk-v2.1-fp16",
                local_dir=mlx_sortformer_fp16_dir,
                required_files=["config.json", "model.safetensors"],
                allow_patterns=["config.json", "model.safetensors", "README.md"],
            ),
            "mlx-sortformer-streaming-fp32": ModelSpec(
                provider_id="mlx-sortformer-streaming-fp32",
                label="MLX Sortformer Streaming FP32",
                repo_id="mlx-community/diar_streaming_sortformer_4spk-v2.1-fp32",
                local_dir=mlx_sortformer_fp32_dir,
                required_files=["config.json", "model.safetensors"],
                allow_patterns=["config.json", "model.safetensors", "README.md"],
            ),
            "whisperx-pyannote": ModelSpec(
                provider_id="whisperx-pyannote",
                label="WhisperX + pyannote",
                repo_id="pyannote/speaker-diarization-3.1",
                local_dir=whisperx_pyannote_dir,
                required_files=["config.yaml"],
                allow_patterns=pyannote_allow_patterns(),
                category="diarization",
                recommendation="Offline Accuracy",
                detail="High-quality offline transcription alignment and speaker diarization for saved conversations.",
                requires_hf_auth=True,
                agreement_url="https://huggingface.co/pyannote/speaker-diarization-3.1",
                license="mit",
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
            category=spec.category,
            recommendation=spec.recommendation,
            detail=spec.detail,
            size=spec.size,
            precision=spec.precision,
            requires_hf_auth=spec.requires_hf_auth,
            agreement_url=spec.agreement_url,
            license=spec.license,
            installed_revision=metadata.get("revision"),
            missing_files=missing_files,
            download_state=download_state.state,
            download_message=download_state.message,
        )

    def check_update(self, provider_id: str, token: str | None = None) -> ModelUpdateInfo:
        spec = self._spec(provider_id)
        remote_revision = self._remote_revision(spec, token=token)
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

    def download(self, provider_id: str, token: str | None = None) -> ModelDownloadStatus:
        spec = self._spec(provider_id)
        resolved_token, _ = resolve_huggingface_token(token)
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
            remote_revision = self._remote_revision(spec, token=resolved_token)
            spec.local_dir.mkdir(parents=True, exist_ok=True)
            self.snapshot_downloader(
                repo_id=spec.repo_id,
                repo_type="model",
                local_dir=str(spec.local_dir),
                allow_patterns=spec.allow_patterns,
                token=resolved_token,
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
            message = self._download_error_message(spec, exc)
            state = ModelDownloadStatus(
                provider_id=provider_id,
                state="failed",
                message=message,
                local_path=str(spec.local_dir),
                revision=None,
            )
            self._set_download_state(state)
            raise RuntimeError(message) from exc

    def validate_huggingface_access(self, provider_id: str, token: str = "") -> HuggingFaceAuthStatus:
        resolved_token, source = resolve_huggingface_token(token)
        if not resolved_token:
            return HuggingFaceAuthStatus(
                connected=False,
                source="none",
                provider_id=provider_id or None,
                message="No Hugging Face token found. Paste a token, set HF_TOKEN, or run hf auth login.",
            )

        username: str | None = None
        try:
            user_info = self.hub_api.whoami(token=resolved_token)
            username = user_info.get("name") if isinstance(user_info, dict) else None
        except Exception as exc:
            return HuggingFaceAuthStatus(
                connected=False,
                source=source,
                provider_id=provider_id or None,
                message=f"Hugging Face token validation failed: {exc}",
            )

        if not provider_id:
            return HuggingFaceAuthStatus(
                connected=True,
                source=source,
                username=username,
                message="Hugging Face token is valid",
            )

        spec = self._spec(provider_id)
        try:
            self._remote_revision(spec, token=resolved_token)
        except Exception as exc:
            return HuggingFaceAuthStatus(
                connected=True,
                source=source,
                username=username,
                provider_id=spec.provider_id,
                repo_id=spec.repo_id,
                access_granted=False,
                message=str(exc),
            )

        return HuggingFaceAuthStatus(
            connected=True,
            source=source,
            username=username,
            provider_id=spec.provider_id,
            repo_id=spec.repo_id,
            access_granted=True,
            message="Access granted",
        )

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

    def delete(self, provider_id: str) -> ModelStatus:
        spec = self._spec(provider_id)
        with self._lock:
            current = self._download_states.get(provider_id)
            if current and current.state in {"queued", "downloading"}:
                raise RuntimeError(f"Cannot delete {spec.label} while a download is in progress.")

            self._delete_local_model_path(spec)
            self._download_states.pop(provider_id, None)

        return self.status(provider_id)

    def _set_download_state(self, state: ModelDownloadStatus) -> None:
        with self._lock:
            self._download_states[state.provider_id] = state

    def _spec(self, provider_id: str) -> ModelSpec:
        if provider_id not in self._specs:
            raise KeyError(provider_id)
        return self._specs[provider_id]

    def _missing_files(self, spec: ModelSpec) -> list[str]:
        missing: list[str] = []
        for filename in spec.required_files:
            if "*" in filename:
                if not any(spec.local_dir.glob(filename)):
                    missing.append(filename)
            elif not (spec.local_dir / filename).exists():
                missing.append(filename)
        return missing

    def _remote_revision(self, spec: ModelSpec, token: str | None = None) -> str:
        try:
            info = self.hub_api.model_info(spec.repo_id, token=token)
        except Exception as exc:
            message = self._hub_authorization_message(spec, exc)
            if message:
                raise RuntimeError(message) from exc
            raise
        revision = getattr(info, "sha", None)
        if not revision:
            raise RuntimeError(f"no revision returned for {spec.repo_id}")
        return revision

    def _delete_local_model_path(self, spec: ModelSpec) -> None:
        local_dir = spec.local_dir.expanduser()
        resolved = local_dir.resolve(strict=False)
        home = Path.home().resolve(strict=False)

        if resolved == Path(resolved.anchor) or resolved == home or resolved == home.parent:
            raise RuntimeError(f"Refusing to delete unsafe model path: {local_dir}")

        if not local_dir.exists() and not local_dir.is_symlink():
            return

        if local_dir.is_symlink() or local_dir.is_file():
            local_dir.unlink()
            return

        if not local_dir.is_dir():
            raise RuntimeError(f"Refusing to delete non-directory model path: {local_dir}")

        shutil.rmtree(local_dir)

    def _download_error_message(self, spec: ModelSpec, exc: Exception) -> str:
        authorization_message = self._hub_authorization_message(spec, exc)
        if authorization_message:
            return authorization_message
        return str(exc)

    def _hub_authorization_message(self, spec: ModelSpec, exc: Exception) -> str | None:
        response = getattr(exc, "response", None)
        status_code = getattr(response, "status_code", None)
        text = str(exc).lower()
        gated_or_unauthorized = (
            isinstance(exc, GatedRepoError)
            or (isinstance(exc, HfHubHTTPError) and status_code in {401, 403})
            or status_code in {401, 403}
            or "gated" in text
            or "unauthorized" in text
            or "forbidden" in text
        )
        if not gated_or_unauthorized:
            return None

        return (
            f"{spec.label} requires Hugging Face authorization. "
            f"Accept the model agreement at https://huggingface.co/{spec.repo_id}, "
            "then run `huggingface-cli login` or set HF_TOKEN before downloading."
        )

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


def translategemma_allow_patterns() -> list[str]:
    return [
        "config.json",
        "generation_config.json",
        "model.safetensors",
        "model.safetensors.index.json",
        "tokenizer.json",
        "tokenizer.model",
        "tokenizer_config.json",
        "special_tokens_map.json",
        "added_tokens.json",
        "chat_template.jinja",
        "README.md",
    ]


def translategemma_12b_allow_patterns() -> list[str]:
    patterns = translategemma_allow_patterns()
    return [*patterns[:3], "model-*.safetensors", *patterns[3:]]


def plamo_allow_patterns() -> list[str]:
    return [
        "config.json",
        "generation_config.json",
        "model.safetensors",
        "model.safetensors.index.json",
        "tokenizer.jsonl",
        "tokenizer_config.json",
        "special_tokens_map.json",
        "modeling_plamo.py",
        "tokenization_plamo.py",
        "README.md",
    ]


def whisper_mlx_allow_patterns() -> list[str]:
    return [
        "config.json",
        "generation_config.json",
        "model.safetensors",
        "model.safetensors.index.json",
        "tokenizer.json",
        "tokenizer_config.json",
        "preprocessor_config.json",
        "normalizer.json",
        "vocab.json",
        "merges.txt",
        "added_tokens.json",
        "special_tokens_map.json",
        "README.md",
    ]


def sensevoice_allow_patterns() -> list[str]:
    return [
        "config.yaml",
        "configuration.json",
        "model.pt",
        "am.mvn",
        "chn_jpn_yue_eng_ko_spectok.bpe.model",
        "README.md",
    ]


def pyannote_allow_patterns() -> list[str]:
    return [
        "config.yaml",
        "handler.py",
        "requirements.txt",
        "README.md",
    ]


def resolve_huggingface_token(explicit_token: str | None = None) -> tuple[str | None, str]:
    explicit = (explicit_token or "").strip()
    if explicit:
        return explicit, "app-keychain"

    for name in ("HF_TOKEN", "HUGGING_FACE_HUB_TOKEN"):
        value = os.environ.get(name, "").strip()
        if value:
            return value, "environment"

    cached = get_token()
    if cached:
        return cached, "cli"

    return None, "none"
