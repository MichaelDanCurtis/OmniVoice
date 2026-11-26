import importlib.util
import io
import sys
import wave
from types import ModuleType
from types import SimpleNamespace

from omnivoice_engine.providers.registry import ProviderRegistry
from omnivoice_engine.providers.canary_qwen import CanaryQwenProvider
from omnivoice_engine.providers.parakeet_sherpa import ParakeetSherpaProvider
from omnivoice_engine.providers.parakeet_mlx import ParakeetMLXProvider
from omnivoice_engine.providers.whisper_mlx import WhisperMLXProvider


def install_fake_parakeet(monkeypatch, model_dir, result):
    import numpy as np

    captured = {}
    package = ModuleType("parakeet_mlx")
    audio = ModuleType("parakeet_mlx.audio")
    mlx = ModuleType("mlx")
    core = ModuleType("mlx.core")
    core.array = np.asarray
    mlx.core = core
    audio.get_logmel = lambda samples, _config: samples

    class FakeModel:
        preprocessor_config = SimpleNamespace(sample_rate=16000, hop_length=160)

        def generate(self, samples):
            captured["samples"] = samples
            return [result]

        def transcribe(self, _path):
            raise AssertionError("The file API requires external ffmpeg")

    def from_pretrained(path):
        captured["model_path"] = path
        return FakeModel()

    package.from_pretrained = from_pretrained
    for filename in ["config.json", "model.safetensors"]:
        (model_dir / filename).write_text("model")
    monkeypatch.setattr("platform.system", lambda: "Darwin")
    monkeypatch.setattr("platform.machine", lambda: "arm64")
    monkeypatch.setattr(importlib.util, "find_spec", lambda name: object() if name == "parakeet_mlx" else None)
    for name, module in [("parakeet_mlx", package), ("parakeet_mlx.audio", audio), ("mlx", mlx), ("mlx.core", core)]:
        monkeypatch.setitem(sys.modules, name, module)
    return captured


def wav_bytes(samples, sample_rate=16000, channels=1):
    output = io.BytesIO()
    with wave.open(output, "wb") as wav:
        wav.setnchannels(channels)
        wav.setsampwidth(2)
        wav.setframerate(sample_rate)
        wav.writeframes(samples)
    return output.getvalue()


def test_fake_provider_is_available():
    registry = ProviderRegistry()

    providers = registry.list_providers()

    fake = next(provider for provider in providers if provider.id == "fake")
    assert fake.available is True
    assert fake.reason is None


def test_fake_provider_transcribes_bytes():
    registry = ProviderRegistry()
    provider = registry.get("fake")

    result = provider.transcribe(b"hello world")

    assert result == "fake transcript"


def test_parakeet_provider_is_reported_even_when_model_is_absent(monkeypatch):
    monkeypatch.setenv("OMNIVOICE_PARAKEET_MODEL_DIR", "/tmp/omnivoice-missing-parakeet-model")
    registry = ProviderRegistry()

    providers = registry.list_providers()

    parakeet = next(provider for provider in providers if provider.id == "parakeet-tdt")
    assert parakeet.available is False
    assert "model files not found" in parakeet.reason


def test_mlx_parakeet_provider_is_visible_as_optional_apple_silicon_backend(monkeypatch):
    monkeypatch.setenv("OMNIVOICE_PARAKEET_MLX_MODEL_DIR", "/tmp/omnivoice-missing-mlx-parakeet-model")
    monkeypatch.setattr("platform.system", lambda: "Darwin")
    monkeypatch.setattr("platform.machine", lambda: "arm64")
    monkeypatch.setattr(importlib.util, "find_spec", lambda name: object() if name == "parakeet_mlx" else None)
    registry = ProviderRegistry()

    providers = registry.list_providers()

    parakeet = next(provider for provider in providers if provider.id == "parakeet-tdt-mlx")
    assert parakeet.available is False
    assert "model files not found" in parakeet.reason


def test_mlx_parakeet_provider_requires_apple_silicon(monkeypatch):
    monkeypatch.setattr("platform.system", lambda: "Linux")
    monkeypatch.setattr("platform.machine", lambda: "x86_64")

    info = ParakeetMLXProvider("/tmp/unused").info()

    assert info.available is False
    assert info.reason == "Parakeet MLX requires Apple Silicon macOS"


def test_mlx_parakeet_provider_reports_missing_runtime(tmp_path, monkeypatch):
    for filename in ["config.json", "model.safetensors"]:
        (tmp_path / filename).write_text("model")
    monkeypatch.setattr("platform.system", lambda: "Darwin")
    monkeypatch.setattr("platform.machine", lambda: "arm64")
    monkeypatch.setattr(importlib.util, "find_spec", lambda name: None)

    info = ParakeetMLXProvider(str(tmp_path)).info()

    assert info.available is False
    assert info.reason == "parakeet-mlx runtime is not installed"


def test_mlx_parakeet_provider_transcribes_with_local_model_dir(tmp_path, monkeypatch):
    captured = install_fake_parakeet(monkeypatch, tmp_path, SimpleNamespace(text="hello from mlx"))
    monkeypatch.setenv("PATH", "")
    result = ParakeetMLXProvider(str(tmp_path)).transcribe(wav_bytes(b"\0\0" * 1600))

    assert result == "hello from mlx"
    assert captured["model_path"] == str(tmp_path)
    assert captured["samples"].shape == (1600,)


def test_mlx_parakeet_provider_preserves_aligned_tokens(tmp_path, monkeypatch):
    install_fake_parakeet(
        monkeypatch,
        tmp_path,
        SimpleNamespace(
            text="hello world",
            sentences=[
                SimpleNamespace(
                    text="hello world",
                    start=0.10,
                    end=0.85,
                    confidence=0.91,
                    tokens=[
                        SimpleNamespace(text="hello", start=0.10, end=0.40, confidence=0.9),
                        SimpleNamespace(text=" world", start=0.40, duration=0.45, confidence=0.8),
                    ],
                )
            ],
        ),
    )

    transcript = ParakeetMLXProvider(str(tmp_path)).transcribe_aligned_pcm_float32(b"\0\0\0\0" * 1600, 16000)

    assert transcript.text == "hello world"
    assert len(transcript.sentences) == 1
    assert transcript.sentences[0].start_ms == 100
    assert transcript.sentences[0].end_ms == 850
    assert [token.text for token in transcript.tokens] == ["hello", " world"]
    assert [(token.start_ms, token.end_ms) for token in transcript.tokens] == [(100, 400), (400, 850)]


def test_mlx_parakeet_downmixes_and_resamples_without_ffmpeg(tmp_path, monkeypatch):
    import numpy as np

    captured = install_fake_parakeet(monkeypatch, tmp_path, SimpleNamespace(text="resampled"))
    monkeypatch.setenv("PATH", "")
    stereo = np.tile(np.array([8192, 24576], dtype="<i2"), (4800, 1))
    result = ParakeetMLXProvider(str(tmp_path)).transcribe(wav_bytes(stereo.tobytes(), 48000, 2))

    assert result == "resampled"
    assert captured["samples"].shape == (1600,)
    np.testing.assert_allclose(captured["samples"][20:-20], 0.5, atol=0.001)


def test_mlx_parakeet_skips_audio_shorter_than_one_hop(tmp_path, monkeypatch):
    captured = install_fake_parakeet(monkeypatch, tmp_path, SimpleNamespace(text="unexpected"))
    transcript = ParakeetMLXProvider(str(tmp_path)).transcribe_aligned_pcm_float32(b"\0\0\0\0" * 16, 16000)

    assert transcript.text == ""
    assert "samples" not in captured


def test_mlx_parakeet_pcm_float32_decodes_in_memory_without_temp_files(tmp_path, monkeypatch):
    import numpy as np
    import tempfile

    captured = install_fake_parakeet(monkeypatch, tmp_path, SimpleNamespace(text="in memory"))

    def forbid_tempfile(*_args, **_kwargs):
        raise AssertionError("PCM decoding should not create temp files on disk")

    monkeypatch.setattr(tempfile, "NamedTemporaryFile", forbid_tempfile)
    pcm = np.full(1600, 0.25, dtype=np.float32).tobytes()
    transcript = ParakeetMLXProvider(str(tmp_path)).transcribe_aligned_pcm_float32(pcm, 16000)

    assert transcript.text == "in memory"
    assert captured["samples"].shape == (1600,)
    np.testing.assert_allclose(captured["samples"], 0.25, atol=1e-6)


def test_whisper_mlx_provider_is_visible_as_multilingual_apple_silicon_backend(monkeypatch):
    monkeypatch.setenv("OMNIVOICE_WHISPER_MLX_MODEL_DIR", "/tmp/omnivoice-missing-whisper-model")
    monkeypatch.setattr("platform.system", lambda: "Darwin")
    monkeypatch.setattr("platform.machine", lambda: "arm64")
    monkeypatch.setattr(importlib.util, "find_spec", lambda name: object() if name == "mlx_audio" else None)
    registry = ProviderRegistry()

    providers = registry.list_providers()

    whisper = next(provider for provider in providers if provider.id == "whisper-large-v3-turbo-mlx-6bit")
    assert whisper.available is False
    assert whisper.label == "Whisper Large v3 Turbo MLX 6-bit"
    assert "model files not found" in whisper.reason


def test_whisper_mlx_provider_requires_apple_silicon(monkeypatch):
    monkeypatch.setattr("platform.system", lambda: "Linux")
    monkeypatch.setattr("platform.machine", lambda: "x86_64")

    info = WhisperMLXProvider("/tmp/unused").info()

    assert info.available is False
    assert info.reason == "Whisper MLX requires Apple Silicon macOS"


def test_whisper_mlx_provider_reports_missing_runtime(tmp_path, monkeypatch):
    for filename in ["config.json", "model.safetensors", "tokenizer.json", "preprocessor_config.json"]:
        (tmp_path / filename).write_text("model")
    monkeypatch.setattr("platform.system", lambda: "Darwin")
    monkeypatch.setattr("platform.machine", lambda: "arm64")
    monkeypatch.setattr(importlib.util, "find_spec", lambda name: None)

    info = WhisperMLXProvider(str(tmp_path)).info()

    assert info.available is False
    assert info.reason == "mlx-audio runtime is not installed"


def test_whisper_mlx_provider_transcribes_with_local_model_dir(tmp_path, monkeypatch):
    captured = {}
    fake_utils_module = ModuleType("mlx_audio.stt.utils")
    fake_generate_module = ModuleType("mlx_audio.stt.generate")

    for filename in ["config.json", "model.safetensors", "tokenizer.json", "preprocessor_config.json"]:
        (tmp_path / filename).write_text("model")

    class FakeModel:
        pass

    def fake_load_model(model_path, lazy=False, strict=False):
        captured["model_path"] = model_path
        captured["lazy"] = lazy
        captured["strict"] = strict
        return FakeModel()

    def fake_generate_transcription(**kwargs):
        captured.update(kwargs)
        return SimpleNamespace(
            text="你好世界",
            segments=[
                {"text": "你好", "start": 0.0, "end": 0.4},
                {"text": "世界", "start": 0.4, "end": 0.9},
            ],
        )

    fake_utils_module.load_model = fake_load_model
    fake_generate_module.generate_transcription = fake_generate_transcription
    monkeypatch.setattr("platform.system", lambda: "Darwin")
    monkeypatch.setattr("platform.machine", lambda: "arm64")
    monkeypatch.setattr(importlib.util, "find_spec", lambda name: object() if name == "mlx_audio" else None)
    monkeypatch.setitem(sys.modules, "mlx_audio", ModuleType("mlx_audio"))
    monkeypatch.setitem(sys.modules, "mlx_audio.stt", ModuleType("mlx_audio.stt"))
    monkeypatch.setitem(sys.modules, "mlx_audio.stt.utils", fake_utils_module)
    monkeypatch.setitem(sys.modules, "mlx_audio.stt.generate", fake_generate_module)

    transcript = WhisperMLXProvider(str(tmp_path)).transcribe_aligned_pcm_float32(b"\0\0\0\0" * 16, 16000)

    assert transcript.text == "你好世界"
    assert captured["model_path"] == str(tmp_path)
    assert captured["audio"].endswith(".wav")
    assert captured["format"] == "txt"
    assert captured["verbose"] is False
    assert captured["task"] == "transcribe"
    assert [sentence.text for sentence in transcript.sentences] == ["你好", "世界"]
    assert [(sentence.start_ms, sentence.end_ms) for sentence in transcript.sentences] == [(0, 400), (400, 900)]


def test_parakeet_provider_default_dir_uses_project_models_when_started_from_engine_dir(tmp_path, monkeypatch):
    project_root = tmp_path / "OmniSpeak"
    package_dir = project_root / "engine" / "omnivoice_engine" / "providers"
    package_dir.mkdir(parents=True)
    model_dir = project_root / "models" / "parakeet-tdt"
    model_dir.mkdir(parents=True)
    for filename in ["encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"]:
        (model_dir / filename).write_text("model")

    monkeypatch.chdir(project_root / "engine")
    monkeypatch.delenv("OMNIVOICE_MODEL_ROOT", raising=False)
    monkeypatch.delenv("OMNIVOICE_PARAKEET_MODEL_DIR", raising=False)
    monkeypatch.setattr("omnivoice_engine.providers.parakeet_sherpa.__file__", str(package_dir / "parakeet_sherpa.py"))
    monkeypatch.setitem(sys.modules, "sherpa_onnx", object())

    provider = ParakeetSherpaProvider()

    assert str(provider.model_dir) == str(model_dir)
    assert provider.info().available is True


def test_parakeet_provider_accepts_hugging_face_int8_layout(tmp_path, monkeypatch):
    for filename in ["encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"]:
        (tmp_path / filename).write_text("model")
    monkeypatch.setitem(sys.modules, "sherpa_onnx", object())

    info = ParakeetSherpaProvider(str(tmp_path)).info()

    assert info.available is True


def test_parakeet_provider_uses_nemo_transducer_runtime_config(tmp_path, monkeypatch):
    captured = {}

    for filename in ["encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"]:
        (tmp_path / filename).write_text("model")

    class FakeOfflineRecognizer:
        @staticmethod
        def from_transducer(**kwargs):
            captured.update(kwargs)
            return object()

    monkeypatch.setitem(
        sys.modules,
        "sherpa_onnx",
        SimpleNamespace(OfflineRecognizer=FakeOfflineRecognizer),
    )

    ParakeetSherpaProvider(str(tmp_path))._get_recognizer()

    assert captured["model_type"] == "nemo_transducer"
    assert captured["feature_dim"] == 80


def test_parakeet_provider_returns_empty_text_for_too_short_audio(monkeypatch):
    import numpy as np

    provider = ParakeetSherpaProvider("/tmp/unused")
    monkeypatch.setattr(
        provider,
        "_get_recognizer",
        lambda: (_ for _ in ()).throw(AssertionError("recognizer should not be initialized")),
    )

    assert provider._decode_samples(np.zeros(1000, dtype=np.float32), 16000) == ""


def test_parakeet_provider_returns_empty_text_for_empty_request_body(tmp_path, monkeypatch):
    for filename in ["encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"]:
        (tmp_path / filename).write_text("model")
    monkeypatch.setitem(sys.modules, "sherpa_onnx", object())

    assert ParakeetSherpaProvider(str(tmp_path)).transcribe(b"") == ""


def test_canary_qwen_provider_is_visible_as_installable_accuracy_mode(monkeypatch):
    monkeypatch.setenv("OMNIVOICE_CANARY_MODEL_DIR", "/tmp/omnivoice-missing-canary-model")
    registry = ProviderRegistry()

    providers = registry.list_providers()

    canary = next(provider for provider in providers if provider.id == "canary-qwen-2.5b")
    assert canary.available is False
    assert canary.label == "Canary-Qwen-2.5B"
    assert "model files not found" in canary.reason


def test_canary_qwen_provider_reports_missing_runtime(tmp_path, monkeypatch):
    for filename in ["config.json", "model.safetensors"]:
        (tmp_path / filename).write_text("model")
    monkeypatch.setattr(importlib.util, "find_spec", lambda name: None)

    info = CanaryQwenProvider(str(tmp_path)).info()

    assert info.available is False
    assert info.reason == "NVIDIA NeMo speechlm2 runtime is not installed"


def test_canary_qwen_provider_transcribes_with_local_model_dir(tmp_path, monkeypatch):
    captured = {}
    fake_models_module = ModuleType("nemo.collections.speechlm2.models")

    for filename in ["config.json", "model.safetensors"]:
        (tmp_path / filename).write_text("model")

    class FakeIds:
        def cpu(self):
            return "decoded-token-ids"

    class FakeTokenizer:
        def ids_to_text(self, token_ids):
            captured["token_ids"] = token_ids
            return "hello from canary"

    class FakeSALM:
        audio_locator_tag = "<|audio|>"
        tokenizer = FakeTokenizer()

        @classmethod
        def from_pretrained(cls, model_path):
            captured["model_path"] = model_path
            return cls()

        def generate(self, prompts, max_new_tokens):
            captured["prompts"] = prompts
            captured["max_new_tokens"] = max_new_tokens
            return [FakeIds()]

    fake_models_module.SALM = FakeSALM
    monkeypatch.setattr(
        importlib.util,
        "find_spec",
        lambda name: object() if name == "nemo.collections.speechlm2.models" else None,
    )
    monkeypatch.setitem(sys.modules, "nemo", ModuleType("nemo"))
    monkeypatch.setitem(sys.modules, "nemo.collections", ModuleType("nemo.collections"))
    monkeypatch.setitem(sys.modules, "nemo.collections.speechlm2", ModuleType("nemo.collections.speechlm2"))
    monkeypatch.setitem(sys.modules, "nemo.collections.speechlm2.models", fake_models_module)

    transcript = CanaryQwenProvider(str(tmp_path)).transcribe_aligned_pcm_float32(b"\0\0\0\0" * 16, 16000)

    assert transcript.text == "hello from canary"
    assert captured["model_path"] == str(tmp_path)
    assert captured["token_ids"] == "decoded-token-ids"
    assert captured["max_new_tokens"] == 128
    assert captured["prompts"][0][0]["content"] == "Transcribe the following: <|audio|>"
    assert captured["prompts"][0][0]["audio"][0].endswith(".wav")


def test_canary_qwen_provider_cleans_chat_template_echoes(tmp_path, monkeypatch):
    captured = {}
    fake_models_module = ModuleType("nemo.collections.speechlm2.models")

    for filename in ["config.json", "model.safetensors"]:
        (tmp_path / filename).write_text("model")

    class FakeIds:
        def cpu(self):
            return [1, 2, 3]

    class FakeTokenizer:
        def decode(self, token_ids, skip_special_tokens=False):
            captured["decode_token_ids"] = token_ids
            captured["skip_special_tokens"] = skip_special_tokens
            return "<|im_start|>user\nTranscribe the following: <|audioplaceholder|><|im_end|>\n<|im_start|>assistant\nHello from Canary.<|im_end|>"

        def ids_to_text(self, token_ids):
            captured["ids_to_text_token_ids"] = token_ids
            return "should not be used"

    class FakeSALM:
        audio_locator_tag = "<|audioplaceholder|>"
        tokenizer = FakeTokenizer()

        @classmethod
        def from_pretrained(cls, model_path):
            captured["model_path"] = model_path
            return cls()

        def generate(self, prompts, max_new_tokens):
            captured["prompts"] = prompts
            captured["max_new_tokens"] = max_new_tokens
            return [FakeIds()]

    fake_models_module.SALM = FakeSALM
    monkeypatch.setattr(
        importlib.util,
        "find_spec",
        lambda name: object() if name == "nemo.collections.speechlm2.models" else None,
    )
    monkeypatch.setitem(sys.modules, "nemo", ModuleType("nemo"))
    monkeypatch.setitem(sys.modules, "nemo.collections", ModuleType("nemo.collections"))
    monkeypatch.setitem(sys.modules, "nemo.collections.speechlm2", ModuleType("nemo.collections.speechlm2"))
    monkeypatch.setitem(sys.modules, "nemo.collections.speechlm2.models", fake_models_module)

    transcript = CanaryQwenProvider(str(tmp_path)).transcribe_aligned_pcm_float32(b"\0\0\0\0" * 16, 16000)

    assert transcript.text == "Hello from Canary."
    assert captured["decode_token_ids"] == [1, 2, 3]
    assert captured["skip_special_tokens"] is True
    assert "ids_to_text_token_ids" not in captured
    assert captured["max_new_tokens"] == 128


def test_canary_qwen_provider_cleans_list_shaped_transcript_payload():
    provider = CanaryQwenProvider("/tmp/unused")

    assert provider._clean_text("['Hello from Canary.']") == "Hello from Canary."
    assert provider._clean_text('["Hello", "from Canary."]') == "Hello from Canary."
