from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
import importlib.util
import os
from pathlib import Path
import re

from .paths import default_model_root
from .schemas import (
    ProviderInfo,
    TranslationCapabilities,
    TranslationLanguageOption,
    TranslationRequest,
    TranslationResponse,
    TranslationValidationItem,
    TranslationValidationResponse,
)


TRANSLATEGEMMA_ENV = "OMNIVOICE_TRANSLATEGEMMA_MLX_MODEL_DIR"
NLLB_ENV = "OMNIVOICE_NLLB_MODEL_DIR"
FALLBACK_TRANSLATION_LANGUAGES = (
    TranslationLanguageOption(code="en", name="English"),
    TranslationLanguageOption(code="ar", name="Arabic"),
    TranslationLanguageOption(code="bn", name="Bengali"),
    TranslationLanguageOption(code="bg", name="Bulgarian"),
    TranslationLanguageOption(code="zh", name="Chinese"),
    TranslationLanguageOption(code="cs", name="Czech"),
    TranslationLanguageOption(code="da", name="Danish"),
    TranslationLanguageOption(code="nl", name="Dutch"),
    TranslationLanguageOption(code="fr", name="French"),
    TranslationLanguageOption(code="de", name="German"),
    TranslationLanguageOption(code="el", name="Greek"),
    TranslationLanguageOption(code="hi", name="Hindi"),
    TranslationLanguageOption(code="id", name="Indonesian"),
    TranslationLanguageOption(code="it", name="Italian"),
    TranslationLanguageOption(code="ja", name="Japanese"),
    TranslationLanguageOption(code="ko", name="Korean"),
    TranslationLanguageOption(code="pl", name="Polish"),
    TranslationLanguageOption(code="pt", name="Portuguese"),
    TranslationLanguageOption(code="ro", name="Romanian"),
    TranslationLanguageOption(code="ru", name="Russian"),
    TranslationLanguageOption(code="es", name="Spanish"),
    TranslationLanguageOption(code="sv", name="Swedish"),
    TranslationLanguageOption(code="tr", name="Turkish"),
    TranslationLanguageOption(code="uk", name="Ukrainian"),
    TranslationLanguageOption(code="vi", name="Vietnamese"),
)

ENGLISH_SOURCE_LANGUAGE = TranslationLanguageOption(code="en", name="English", is_default=True)

WHISPER_SOURCE_LANGUAGES = (
    TranslationLanguageOption(code="auto", name="Auto Detect", is_default=True),
    TranslationLanguageOption(code="en", name="English"),
    TranslationLanguageOption(code="af", name="Afrikaans"),
    TranslationLanguageOption(code="am", name="Amharic"),
    TranslationLanguageOption(code="ar", name="Arabic"),
    TranslationLanguageOption(code="as", name="Assamese"),
    TranslationLanguageOption(code="az", name="Azerbaijani"),
    TranslationLanguageOption(code="ba", name="Bashkir"),
    TranslationLanguageOption(code="be", name="Belarusian"),
    TranslationLanguageOption(code="bg", name="Bulgarian"),
    TranslationLanguageOption(code="bn", name="Bengali"),
    TranslationLanguageOption(code="bo", name="Tibetan"),
    TranslationLanguageOption(code="br", name="Breton"),
    TranslationLanguageOption(code="bs", name="Bosnian"),
    TranslationLanguageOption(code="ca", name="Catalan"),
    TranslationLanguageOption(code="cs", name="Czech"),
    TranslationLanguageOption(code="cy", name="Welsh"),
    TranslationLanguageOption(code="da", name="Danish"),
    TranslationLanguageOption(code="de", name="German"),
    TranslationLanguageOption(code="el", name="Greek"),
    TranslationLanguageOption(code="es", name="Spanish"),
    TranslationLanguageOption(code="et", name="Estonian"),
    TranslationLanguageOption(code="eu", name="Basque"),
    TranslationLanguageOption(code="fa", name="Persian"),
    TranslationLanguageOption(code="fi", name="Finnish"),
    TranslationLanguageOption(code="fo", name="Faroese"),
    TranslationLanguageOption(code="fr", name="French"),
    TranslationLanguageOption(code="gl", name="Galician"),
    TranslationLanguageOption(code="gu", name="Gujarati"),
    TranslationLanguageOption(code="ha", name="Hausa"),
    TranslationLanguageOption(code="haw", name="Hawaiian"),
    TranslationLanguageOption(code="he", name="Hebrew"),
    TranslationLanguageOption(code="hi", name="Hindi"),
    TranslationLanguageOption(code="hr", name="Croatian"),
    TranslationLanguageOption(code="ht", name="Haitian Creole"),
    TranslationLanguageOption(code="hu", name="Hungarian"),
    TranslationLanguageOption(code="hy", name="Armenian"),
    TranslationLanguageOption(code="id", name="Indonesian"),
    TranslationLanguageOption(code="is", name="Icelandic"),
    TranslationLanguageOption(code="it", name="Italian"),
    TranslationLanguageOption(code="ja", name="Japanese"),
    TranslationLanguageOption(code="jw", name="Javanese"),
    TranslationLanguageOption(code="ka", name="Georgian"),
    TranslationLanguageOption(code="kk", name="Kazakh"),
    TranslationLanguageOption(code="km", name="Khmer"),
    TranslationLanguageOption(code="kn", name="Kannada"),
    TranslationLanguageOption(code="ko", name="Korean"),
    TranslationLanguageOption(code="la", name="Latin"),
    TranslationLanguageOption(code="lb", name="Luxembourgish"),
    TranslationLanguageOption(code="ln", name="Lingala"),
    TranslationLanguageOption(code="lo", name="Lao"),
    TranslationLanguageOption(code="lt", name="Lithuanian"),
    TranslationLanguageOption(code="lv", name="Latvian"),
    TranslationLanguageOption(code="mg", name="Malagasy"),
    TranslationLanguageOption(code="mi", name="Maori"),
    TranslationLanguageOption(code="mk", name="Macedonian"),
    TranslationLanguageOption(code="ml", name="Malayalam"),
    TranslationLanguageOption(code="mn", name="Mongolian"),
    TranslationLanguageOption(code="mr", name="Marathi"),
    TranslationLanguageOption(code="ms", name="Malay"),
    TranslationLanguageOption(code="mt", name="Maltese"),
    TranslationLanguageOption(code="my", name="Burmese"),
    TranslationLanguageOption(code="ne", name="Nepali"),
    TranslationLanguageOption(code="nl", name="Dutch"),
    TranslationLanguageOption(code="nn", name="Norwegian Nynorsk"),
    TranslationLanguageOption(code="no", name="Norwegian"),
    TranslationLanguageOption(code="oc", name="Occitan"),
    TranslationLanguageOption(code="pa", name="Punjabi"),
    TranslationLanguageOption(code="pl", name="Polish"),
    TranslationLanguageOption(code="ps", name="Pashto"),
    TranslationLanguageOption(code="pt", name="Portuguese"),
    TranslationLanguageOption(code="ro", name="Romanian"),
    TranslationLanguageOption(code="ru", name="Russian"),
    TranslationLanguageOption(code="sa", name="Sanskrit"),
    TranslationLanguageOption(code="sd", name="Sindhi"),
    TranslationLanguageOption(code="si", name="Sinhala"),
    TranslationLanguageOption(code="sk", name="Slovak"),
    TranslationLanguageOption(code="sl", name="Slovenian"),
    TranslationLanguageOption(code="sn", name="Shona"),
    TranslationLanguageOption(code="so", name="Somali"),
    TranslationLanguageOption(code="sq", name="Albanian"),
    TranslationLanguageOption(code="sr", name="Serbian"),
    TranslationLanguageOption(code="su", name="Sundanese"),
    TranslationLanguageOption(code="sv", name="Swedish"),
    TranslationLanguageOption(code="sw", name="Swahili"),
    TranslationLanguageOption(code="ta", name="Tamil"),
    TranslationLanguageOption(code="te", name="Telugu"),
    TranslationLanguageOption(code="tg", name="Tajik"),
    TranslationLanguageOption(code="th", name="Thai"),
    TranslationLanguageOption(code="tk", name="Turkmen"),
    TranslationLanguageOption(code="tl", name="Tagalog"),
    TranslationLanguageOption(code="tr", name="Turkish"),
    TranslationLanguageOption(code="tt", name="Tatar"),
    TranslationLanguageOption(code="uk", name="Ukrainian"),
    TranslationLanguageOption(code="ur", name="Urdu"),
    TranslationLanguageOption(code="uz", name="Uzbek"),
    TranslationLanguageOption(code="vi", name="Vietnamese"),
    TranslationLanguageOption(code="yi", name="Yiddish"),
    TranslationLanguageOption(code="yo", name="Yoruba"),
    TranslationLanguageOption(code="yue", name="Cantonese"),
    TranslationLanguageOption(code="zh", name="Chinese"),
)

SCRIPT_RANGES: tuple[tuple[str, tuple[tuple[int, int], ...]], ...] = (
    ("Han", ((0x3400, 0x4DBF), (0x4E00, 0x9FFF), (0xF900, 0xFAFF), (0x20000, 0x2A6DF), (0x2A700, 0x2B73F))),
    ("Hiragana", ((0x3040, 0x309F),)),
    ("Katakana", ((0x30A0, 0x30FF), (0x31F0, 0x31FF))),
    ("Hangul", ((0x1100, 0x11FF), (0x3130, 0x318F), (0xAC00, 0xD7AF))),
    ("Arabic", ((0x0600, 0x06FF), (0x0750, 0x077F), (0x08A0, 0x08FF), (0xFB50, 0xFDFF), (0xFE70, 0xFEFF))),
    ("Cyrillic", ((0x0400, 0x04FF), (0x0500, 0x052F))),
    ("Greek", ((0x0370, 0x03FF), (0x1F00, 0x1FFF))),
    ("Hebrew", ((0x0590, 0x05FF),)),
    ("Thaana", ((0x0780, 0x07BF),)),
    ("Devanagari", ((0x0900, 0x097F),)),
    ("Bengali", ((0x0980, 0x09FF),)),
    ("Gurmukhi", ((0x0A00, 0x0A7F),)),
    ("Gujarati", ((0x0A80, 0x0AFF),)),
    ("Oriya", ((0x0B00, 0x0B7F),)),
    ("Tamil", ((0x0B80, 0x0BFF),)),
    ("Telugu", ((0x0C00, 0x0C7F),)),
    ("Kannada", ((0x0C80, 0x0CFF),)),
    ("Malayalam", ((0x0D00, 0x0D7F),)),
    ("Sinhala", ((0x0D80, 0x0DFF),)),
    ("Thai", ((0x0E00, 0x0E7F),)),
    ("Lao", ((0x0E80, 0x0EFF),)),
    ("Tibetan", ((0x0F00, 0x0FFF),)),
    ("Myanmar", ((0x1000, 0x109F),)),
    ("Georgian", ((0x10A0, 0x10FF), (0x1C90, 0x1CBF))),
    ("Armenian", ((0x0530, 0x058F),)),
    ("Ethiopic", ((0x1200, 0x137F), (0x1380, 0x139F), (0x2D80, 0x2DDF), (0xAB00, 0xAB2F))),
    ("Khmer", ((0x1780, 0x17FF),)),
    ("Mongolian", ((0x1800, 0x18AF),)),
    ("Canadian Aboriginal", ((0x1400, 0x167F),)),
    ("Vai", ((0xA500, 0xA63F),)),
    ("NKo", ((0x07C0, 0x07FF),)),
    ("Yi", ((0xA000, 0xA48F),)),
    ("Latin", ((0x0041, 0x005A), (0x0061, 0x007A), (0x00C0, 0x024F), (0x1E00, 0x1EFF))),
)

EXPECTED_SCRIPT_BY_CODE: dict[str, tuple[str, ...]] = {
    "ab": ("Cyrillic",),
    "am": ("Ethiopic",),
    "ar": ("Arabic",),
    "as": ("Bengali",),
    "ba": ("Cyrillic",),
    "be": ("Cyrillic",),
    "bg": ("Cyrillic",),
    "bn": ("Bengali",),
    "bo": ("Tibetan",),
    "ce": ("Cyrillic",),
    "cv": ("Cyrillic",),
    "dv": ("Thaana",),
    "dz": ("Tibetan",),
    "el": ("Greek",),
    "fa": ("Arabic",),
    "gu": ("Gujarati",),
    "he": ("Hebrew",),
    "hi": ("Devanagari",),
    "hy": ("Armenian",),
    "iu": ("Canadian Aboriginal",),
    "ii": ("Yi",),
    "ja": ("Hiragana", "Katakana", "Han"),
    "ka": ("Georgian",),
    "kk": ("Cyrillic", "Latin"),
    "km": ("Khmer",),
    "kn": ("Kannada",),
    "ko": ("Hangul",),
    "ks": ("Arabic", "Devanagari"),
    "ku": ("Latin", "Arabic", "Cyrillic"),
    "ky": ("Cyrillic",),
    "lo": ("Lao",),
    "mk": ("Cyrillic",),
    "ml": ("Malayalam",),
    "mn": ("Cyrillic", "Mongolian"),
    "mr": ("Devanagari",),
    "my": ("Myanmar",),
    "ne": ("Devanagari",),
    "or": ("Oriya",),
    "os": ("Cyrillic", "Georgian"),
    "pa": ("Gurmukhi", "Arabic"),
    "ps": ("Arabic",),
    "ru": ("Cyrillic",),
    "sa": ("Devanagari",),
    "sd": ("Arabic", "Devanagari"),
    "si": ("Sinhala",),
    "sr": ("Cyrillic", "Latin"),
    "ta": ("Tamil",),
    "te": ("Telugu",),
    "tg": ("Cyrillic",),
    "th": ("Thai",),
    "ti": ("Ethiopic",),
    "tt": ("Cyrillic", "Latin"),
    "ug": ("Arabic",),
    "uk": ("Cyrillic",),
    "ur": ("Arabic",),
    "uz": ("Latin", "Cyrillic", "Arabic"),
    "yi": ("Hebrew",),
    "zh": ("Han",),
}


@dataclass(frozen=True)
class LanguageDetection:
    language: str
    confidence: float


class TranslationProvider(ABC):
    id: str
    label: str

    @abstractmethod
    def info(self, model_path: str = "") -> ProviderInfo:
        raise NotImplementedError

    @abstractmethod
    def translate(self, request: TranslationRequest) -> TranslationResponse:
        raise NotImplementedError


class FakeTranslationProvider(TranslationProvider):
    id = "fake"
    label = "Fake Local Translator"

    def info(self, model_path: str = "") -> ProviderInfo:
        return ProviderInfo(id=self.id, label=self.label, available=True)

    def capabilities(
        self,
        model_path: str = "",
        model_provider_id: str | None = None,
        asr_provider_id: str = "parakeet-tdt-mlx",
    ) -> TranslationCapabilities:
        return translation_capabilities(
            provider_id=self.id,
            model_provider_id=model_provider_id,
            asr_provider_id=asr_provider_id,
            target_languages=list(FALLBACK_TRANSLATION_LANGUAGES),
            capability_source="curated-fallback",
        )

    def translate(self, request: TranslationRequest) -> TranslationResponse:
        detection = resolve_source_language(request.text, request.source_language)
        return TranslationResponse(
            text=f"[{request.target_language}] {request.text}",
            provider=self.id,
            source_language=request.source_language,
            detected_language=detection.language,
            target_language=request.target_language,
            confidence=detection.confidence,
            is_final=request.is_final,
        )


class MLXPromptTranslationProvider(TranslationProvider):
    id = "translategemma-mlx"
    label = "TranslateGemma MLX"
    required_file_patterns = ("config.json", "model*.safetensors", "tokenizer.json")

    def __init__(self, *, env_var: str = TRANSLATEGEMMA_ENV, default_dir: str | Path | None = None) -> None:
        self.env_var = env_var
        self.default_dir = Path(default_dir).expanduser() if default_dir is not None else default_model_root(__file__) / self.id
        self._loaded_path: str | None = None
        self._model = None
        self._tokenizer = None

    def info(self, model_path: str = "") -> ProviderInfo:
        resolved_path = resolved_model_path(model_path, self.env_var, self.default_dir)
        if not resolved_path:
            return ProviderInfo(
                id=self.id,
                label=self.label,
                available=False,
                reason=f"model path not configured; choose a model folder or set {self.env_var}",
            )
        if not Path(resolved_path).exists():
            return ProviderInfo(id=self.id, label=self.label, available=False, reason=f"model path not found: {resolved_path}")
        missing_files = missing_required_patterns(Path(resolved_path), self.required_file_patterns)
        if missing_files:
            return ProviderInfo(
                id=self.id,
                label=self.label,
                available=False,
                reason=f"model files missing: {', '.join(missing_files)}",
            )
        if importlib.util.find_spec("mlx_lm") is None:
            return ProviderInfo(id=self.id, label=self.label, available=False, reason="mlx-lm is not installed")
        return ProviderInfo(id=self.id, label=self.label, available=True)

    def capabilities(
        self,
        model_path: str = "",
        model_provider_id: str | None = None,
        asr_provider_id: str = "parakeet-tdt-mlx",
    ) -> TranslationCapabilities:
        resolved_path = resolved_model_path(model_path, self.env_var, self.default_dir)
        template_path = Path(resolved_path) / "chat_template.jinja" if resolved_path else Path()
        languages = languages_from_chat_template(template_path)
        capability_source = "model-template" if languages else "curated-fallback"
        return translation_capabilities(
            provider_id=self.id,
            model_provider_id=model_provider_id,
            asr_provider_id=asr_provider_id,
            target_languages=languages or list(FALLBACK_TRANSLATION_LANGUAGES),
            capability_source=capability_source,
            message=None if languages else "Model language template not found; showing curated fallback languages.",
        )

    def translate(self, request: TranslationRequest) -> TranslationResponse:
        info = self.info(request.model_path)
        if not info.available:
            raise RuntimeError(info.reason or "provider unavailable")

        resolved_path = resolved_model_path(request.model_path, self.env_var, self.default_dir)
        detection = resolve_source_language(request.text, request.source_language)
        languages = languages_from_chat_template(Path(resolved_path) / "chat_template.jinja") or list(FALLBACK_TRANSLATION_LANGUAGES)
        model, tokenizer = self._load(resolved_path)
        prompt = translategemma_prompt(
            tokenizer=tokenizer,
            text=request.text,
            source_language=detection.language,
            target_language=request.target_language,
            languages=languages,
            context=request.context,
        )

        from mlx_lm import generate

        generated = generate(model, tokenizer, prompt=prompt, max_tokens=128, verbose=False)
        translated = clean_translation_output(generated)
        return TranslationResponse(
            text=translated,
            provider=self.id,
            source_language=request.source_language,
            detected_language=detection.language,
            target_language=request.target_language,
            confidence=detection.confidence,
            is_final=request.is_final,
        )

    def _load(self, model_path: str):
        if self._model is not None and self._tokenizer is not None and self._loaded_path == model_path:
            return self._model, self._tokenizer

        from mlx_lm import load

        self._model, self._tokenizer = load(model_path)
        self._loaded_path = model_path
        return self._model, self._tokenizer


class NLLBTranslationProvider(TranslationProvider):
    id = "nllb-200-distilled-600m"
    label = "NLLB-200 Distilled 600M"

    def __init__(self, *, env_var: str = NLLB_ENV) -> None:
        self.env_var = env_var

    def info(self, model_path: str = "") -> ProviderInfo:
        resolved_path = resolved_model_path(model_path, self.env_var)
        if not resolved_path:
            return ProviderInfo(
                id=self.id,
                label=self.label,
                available=False,
                reason=f"model path not configured; choose a model folder or set {self.env_var}",
            )
        if not Path(resolved_path).exists():
            return ProviderInfo(id=self.id, label=self.label, available=False, reason=f"model path not found: {resolved_path}")
        if importlib.util.find_spec("transformers") is None:
            return ProviderInfo(id=self.id, label=self.label, available=False, reason="transformers is not installed")
        return ProviderInfo(
            id=self.id,
            label=self.label,
            available=False,
            reason="NLLB runtime is planned; use TranslateGemma MLX for the first local backend",
        )

    def capabilities(
        self,
        model_path: str = "",
        model_provider_id: str | None = None,
        asr_provider_id: str = "parakeet-tdt-mlx",
    ) -> TranslationCapabilities:
        return translation_capabilities(
            provider_id=self.id,
            model_provider_id=model_provider_id,
            asr_provider_id=asr_provider_id,
            target_languages=list(FALLBACK_TRANSLATION_LANGUAGES),
            capability_source="curated-fallback",
            message="NLLB runtime is planned; language support is a curated placeholder.",
        )

    def translate(self, request: TranslationRequest) -> TranslationResponse:
        info = self.info(request.model_path)
        raise RuntimeError(info.reason or "provider unavailable")


class TranslationRegistry:
    def __init__(self) -> None:
        self._providers: dict[str, TranslationProvider] = {
            FakeTranslationProvider.id: FakeTranslationProvider(),
            MLXPromptTranslationProvider.id: MLXPromptTranslationProvider(),
            NLLBTranslationProvider.id: NLLBTranslationProvider(),
        }

    def list_providers(self) -> list[ProviderInfo]:
        return [provider.info() for provider in self._providers.values()]

    def get(self, provider_id: str) -> TranslationProvider:
        return self._providers[provider_id]

    def capabilities(
        self,
        provider_id: str,
        *,
        model_path: str = "",
        model_provider_id: str | None = None,
        asr_provider_id: str = "parakeet-tdt-mlx",
    ) -> TranslationCapabilities:
        provider = self.get(provider_id)
        provider_capabilities = getattr(provider, "capabilities")
        return provider_capabilities(model_path, model_provider_id, asr_provider_id)


def resolved_model_path(model_path: str, env_var: str, default_dir: str | Path | None = None) -> str:
    trimmed = model_path.strip()
    if trimmed:
        return trimmed
    configured = os.getenv(env_var, "").strip()
    if configured:
        return configured
    return str(default_dir).strip() if default_dir is not None else ""


def missing_required_patterns(model_dir: Path, patterns: tuple[str, ...]) -> list[str]:
    missing: list[str] = []
    for pattern in patterns:
        if any(character in pattern for character in "*?[]"):
            if not list(model_dir.glob(pattern)):
                missing.append(pattern)
        elif not (model_dir / pattern).exists():
            missing.append(pattern)
    return missing


def languages_from_chat_template(template_path: Path) -> list[TranslationLanguageOption]:
    if not template_path.exists():
        return []

    template = template_path.read_text(encoding="utf-8")
    entries = re.findall(r'"([^"]+)"\s*:\s*"([^"]+)"', template)
    languages_by_code: dict[str, TranslationLanguageOption] = {}
    for code, name in entries:
        normalized_code = code.strip()
        normalized_name = name.strip()
        if not normalized_code or not normalized_name:
            continue
        if "-" in normalized_code or "_" in normalized_code:
            continue
        languages_by_code.setdefault(normalized_code, TranslationLanguageOption(code=normalized_code, name=normalized_name))

    return sorted(languages_by_code.values(), key=lambda language: (language.name.casefold(), language.code.casefold()))


def language_name_for_code(code: str, languages: list[TranslationLanguageOption]) -> str:
    normalized_code = code.strip().lower()
    if not normalized_code:
        return code
    for language in languages:
        if language.code.lower() == normalized_code:
            return language.name
    base_code = normalized_code.split("-", 1)[0].split("_", 1)[0]
    for language in languages:
        if language.code.lower() == base_code:
            return language.name
    return code


def validate_translation_targets(
    provider: TranslationProvider,
    *,
    text: str,
    source_language: str,
    model_path: str = "",
    target_languages: list[TranslationLanguageOption] | None = None,
    max_languages: int | None = None,
) -> TranslationValidationResponse:
    capabilities = provider.capabilities(model_path) if hasattr(provider, "capabilities") else translation_capabilities(
        provider_id=provider.id,
        target_languages=list(FALLBACK_TRANSLATION_LANGUAGES),
        capability_source="curated-fallback",
    )
    languages = target_languages or capabilities.target_languages
    if max_languages is not None:
        languages = languages[:max_languages]

    items: list[TranslationValidationItem] = []
    for language in languages:
        try:
            result = provider.translate(
                TranslationRequest(
                    text=text,
                    provider=provider.id,
                    source_language=source_language,
                    target_language=language.code,
                    model_path=model_path,
                )
            )
            items.append(
                diagnose_translation_output(
                    language=language,
                    text=result.text,
                    source_text=text,
                    source_language=source_language,
                )
            )
        except Exception as exc:
            items.append(
                TranslationValidationItem(
                    code=language.code,
                    name=language.name,
                    text="",
                    status="fail",
                    expected_scripts=list(expected_scripts_for_language(language)),
                    failure_category="request-failed",
                    notes=[f"Translation failed: {exc}"],
                )
            )

    passed = sum(1 for item in items if item.status == "pass")
    review = sum(1 for item in items if item.status == "review")
    failed = sum(1 for item in items if item.status == "fail")
    return TranslationValidationResponse(
        provider=provider.id,
        source_language=source_language,
        text=text,
        capability_source=capabilities.capability_source,
        tested=len(items),
        passed=passed,
        review=review,
        failed=failed,
        items=items,
    )


def diagnose_translation_output(
    *,
    language: TranslationLanguageOption,
    text: str,
    source_text: str = "",
    source_language: str = "en",
) -> TranslationValidationItem:
    counts = translation_script_counts(text)
    expected_scripts = expected_scripts_for_language(language)
    replacement_characters = text.count("\ufffd")
    dominant = dominant_translation_script(counts)
    letter_count = sum(counts.values())
    output_preview = preview_translation_validation_text(text)
    notes: list[str] = []

    if not text.strip():
        notes.append("Translation returned empty text.")
    if replacement_characters:
        notes.append("Output contains Unicode replacement characters, which usually means decoding or font fallback is broken.")

    expected_count = sum(counts.get(script, 0) for script in expected_scripts)
    expected_ratio = expected_count / letter_count if letter_count else 0.0
    if expected_scripts and expected_count == 0 and text.strip():
        notes.append(f"Expected script {', '.join(expected_scripts)} was not detected in the output.")
        if dominant:
            notes.append(f"Dominant script was {dominant} with {counts[dominant]} detected letters.")
        elif letter_count == 0:
            notes.append("No alphabetic script characters were detected in the output.")
    elif expected_scripts and expected_scripts != ("Latin",) and text.strip() and expected_ratio < 0.9:
        notes.append(
            f"Expected script coverage is low: {expected_count}/{letter_count} letters "
            f"({expected_ratio:.0%}) matched {', '.join(expected_scripts)}."
        )
        if dominant and dominant not in expected_scripts:
            notes.append(f"Dominant script was {dominant} with {counts[dominant]} detected letters.")

    if expected_scripts == ("Latin",) and expected_count > 0:
        notes.append("Latin-script output rendered; review manually because script alone cannot prove the exact language.")

    if not expected_scripts:
        notes.append("No strict script check for this language; review the text manually.")

    if looks_like_untranslated_source(
        source_text=source_text,
        output_text=text,
        source_language=source_language,
        target_language=language.code,
    ):
        notes.append("Output looks like untranslated source text.")

    failure_category = translation_failure_category(
        text=text,
        expected_scripts=expected_scripts,
        expected_count=expected_count,
        expected_ratio=expected_ratio,
        replacement_characters=replacement_characters,
        notes=notes,
    )
    status = translation_validation_status(
        text=text,
        expected_scripts=expected_scripts,
        expected_count=expected_count,
        expected_ratio=expected_ratio,
        replacement_characters=replacement_characters,
    )
    return TranslationValidationItem(
        code=language.code,
        name=language.name,
        text=text,
        status=status,
        expected_scripts=list(expected_scripts),
        dominant_script=dominant,
        scripts=counts,
        letter_count=letter_count,
        expected_script_characters=expected_count,
        expected_script_ratio=round(expected_ratio, 3),
        replacement_characters=replacement_characters,
        output_preview=output_preview,
        failure_category=failure_category,
        notes=notes,
    )


def preview_translation_validation_text(text: str, limit: int = 96) -> str:
    normalized = re.sub(r"\s+", " ", text).strip()
    if len(normalized) <= limit:
        return normalized
    return f"{normalized[: limit - 1].rstrip()}…"


def normalize_translation_validation_text(text: str) -> str:
    return re.sub(r"[^0-9A-Za-z]+", " ", text).strip().lower()


def looks_like_untranslated_source(
    *,
    source_text: str,
    output_text: str,
    source_language: str,
    target_language: str,
) -> bool:
    source_code = source_language.strip().lower().split("-", 1)[0].split("_", 1)[0]
    target_code = target_language.strip().lower().split("-", 1)[0].split("_", 1)[0]
    if source_code == target_code:
        return False

    source = normalize_translation_validation_text(source_text)
    output = normalize_translation_validation_text(output_text)
    if not source or not output:
        return False
    return output == source or source in output


def translation_failure_category(
    *,
    text: str,
    expected_scripts: tuple[str, ...],
    expected_count: int,
    expected_ratio: float = 0.0,
    replacement_characters: int,
    notes: list[str],
) -> str | None:
    if not text.strip():
        return "empty-output"
    if replacement_characters:
        return "encoding-or-font"
    if any("untranslated source" in note for note in notes):
        return "untranslated-source"
    if expected_scripts and expected_count == 0:
        return "wrong-script"
    if expected_scripts and expected_scripts != ("Latin",) and expected_ratio < 0.65:
        return "mixed-script-wrong-language"
    if expected_scripts and expected_scripts != ("Latin",) and expected_ratio < 0.9:
        return "mixed-script-review"
    if expected_scripts == ("Latin",):
        return "latin-script-review"
    if not expected_scripts:
        return "manual-review"
    return None


def translation_validation_status(
    *,
    text: str,
    expected_scripts: tuple[str, ...],
    expected_count: int,
    expected_ratio: float = 0.0,
    replacement_characters: int,
) -> str:
    if not text.strip() or replacement_characters:
        return "fail"
    if expected_scripts and expected_count == 0:
        return "fail"
    if expected_scripts == ("Latin",):
        return "review"
    if not expected_scripts:
        return "review"
    if expected_ratio < 0.65:
        return "fail"
    if expected_ratio < 0.9:
        return "review"
    return "pass"


def translation_script_counts(text: str) -> dict[str, int]:
    counts: dict[str, int] = {}
    for character in text:
        if not character.isalpha():
            continue
        script = script_for_character(character)
        if script is None:
            continue
        counts[script] = counts.get(script, 0) + 1
    return counts


def script_for_character(character: str) -> str | None:
    value = ord(character)
    for script, ranges in SCRIPT_RANGES:
        if any(start <= value <= end for start, end in ranges):
            return script
    return None


def dominant_translation_script(counts: dict[str, int]) -> str | None:
    if not counts:
        return None
    return max(counts.items(), key=lambda item: item[1])[0]


def expected_scripts_for_language(language: TranslationLanguageOption) -> tuple[str, ...]:
    code = language.code.strip().lower().split("-", 1)[0].split("_", 1)[0]
    if code in EXPECTED_SCRIPT_BY_CODE:
        return EXPECTED_SCRIPT_BY_CODE[code]
    return ("Latin",)


def translation_capabilities(
    *,
    provider_id: str,
    target_languages: list[TranslationLanguageOption],
    capability_source: str,
    model_provider_id: str | None = None,
    asr_provider_id: str = "parakeet-tdt-mlx",
    message: str | None = None,
) -> TranslationCapabilities:
    source_locked, source_reason, source_languages = source_language_capabilities(asr_provider_id, target_languages)
    return TranslationCapabilities(
        provider_id=provider_id,
        model_provider_id=model_provider_id,
        source_language_locked=source_locked,
        source_language_reason=source_reason,
        source_languages=source_languages,
        target_languages=target_languages,
        capability_source=capability_source,
        message=message,
    )


def source_language_capabilities(
    asr_provider_id: str,
    target_languages: list[TranslationLanguageOption] | None = None,
) -> tuple[bool, str | None, list[TranslationLanguageOption]]:
    normalized = asr_provider_id.strip().lower() or "parakeet-tdt-mlx"
    if normalized == "whisper-large-v3-turbo-mlx-6bit":
        target_codes = {language.code.lower() for language in target_languages or []}
        source_languages = list(WHISPER_SOURCE_LANGUAGES)
        if target_codes:
            source_languages = [
                language
                for language in source_languages
                if language.code == "auto" or language.code.lower() in target_codes
            ]
            if len(source_languages) == 1:
                source_languages.append(TranslationLanguageOption(code="en", name="English"))

        return (
            False,
            "Whisper MLX can auto-detect or manually tag multilingual speech before translation.",
            source_languages,
        )

    return (
        True,
        "The selected speech model uses English input for live translation. Use Whisper MLX for multilingual speech.",
        [ENGLISH_SOURCE_LANGUAGE],
    )


def clean_translation_output(text: str) -> str:
    cleaned = text.strip()
    for stop_token in ("<end_of_turn>", "</s>", "<|endoftext|>", "<|end_of_text|>", "<|im_end|>"):
        if stop_token in cleaned:
            cleaned = cleaned.split(stop_token, 1)[0].strip()

    lines = [line.strip() for line in cleaned.splitlines() if line.strip()]
    if len(lines) > 1 and ":" in lines[1]:
        first_label = lines[1].split(":", 1)[0].strip()
        if first_label.isalpha() and first_label[0].isupper():
            lines = lines[:1]

    return "\n".join(lines).strip()


def resolve_source_language(text: str, source_language: str) -> LanguageDetection:
    requested = source_language.strip().lower() or "auto"
    if requested != "auto":
        return LanguageDetection(language=requested, confidence=1.0)
    return detect_language(text)


def detect_language(text: str) -> LanguageDetection:
    normalized = f" {text.casefold()} "
    spanish_markers = (" hola", " gracias", " por ", " para ", " que ", " qué", " estoy", " venir")
    french_markers = (" bonjour", " merci", " oui ", " ça", " etre", " être")
    german_markers = (" hallo", " danke", " ich ", " und ", " nicht")
    if any(marker in normalized for marker in spanish_markers):
        return LanguageDetection(language="es", confidence=0.74)
    if any(marker in normalized for marker in french_markers):
        return LanguageDetection(language="fr", confidence=0.72)
    if any(marker in normalized for marker in german_markers):
        return LanguageDetection(language="de", confidence=0.70)
    return LanguageDetection(language="en", confidence=0.64)


def translation_prompt(*, text: str, source_language: str, target_language: str, context: list[str]) -> str:
    context_text = "\n".join(item for item in context if item.strip())
    if context_text:
        return (
            f"Translate the text from {source_language} to {target_language}.\n"
            f"Return only the {target_language} translation, with no labels, explanations, or commentary.\n"
            "Use the context only to preserve meaning and terminology.\n"
            f"Context:\n{context_text}\n\nText:\n{text}\n\nTranslation:"
        )
    return (
        f"Translate the text from {source_language} to {target_language}.\n"
        f"Return only the {target_language} translation, with no labels, explanations, or commentary.\n"
        f"Text:\n{text}\n\nTranslation:"
    )


def translategemma_prompt(
    *,
    tokenizer,
    text: str,
    source_language: str,
    target_language: str,
    languages: list[TranslationLanguageOption],
    context: list[str],
) -> str:
    if not context and hasattr(tokenizer, "apply_chat_template"):
        messages = [
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "source_lang_code": source_language,
                        "target_lang_code": target_language,
                        "text": text,
                    }
                ],
            }
        ]
        return tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)

    return translation_prompt(
        text=text,
        source_language=language_name_for_code(source_language, languages),
        target_language=language_name_for_code(target_language, languages),
        context=context,
    )
