from pathlib import Path
import sys
import types

from omnivoice_engine.schemas import TranslationLanguageOption, TranslationRequest
from omnivoice_engine.translation import (
    FakeTranslationProvider,
    MLXPromptTranslationProvider,
    clean_translation_output,
    expected_scripts_for_language,
    language_name_for_code,
    languages_from_chat_template,
    translation_script_counts,
    validate_translation_targets,
)


def test_translategemma_provider_uses_default_model_manager_path(tmp_path: Path, monkeypatch) -> None:
    project_root = tmp_path / "OmniVoice"
    package_dir = project_root / "engine" / "omnivoice_engine"
    model_dir = project_root / "models" / "translategemma-mlx"
    package_dir.mkdir(parents=True)
    model_dir.mkdir(parents=True)
    for filename in ("config.json", "model.safetensors", "tokenizer.json"):
        (model_dir / filename).write_text("model")

    monkeypatch.chdir(project_root / "engine")
    monkeypatch.delenv("OMNIVOICE_TRANSLATEGEMMA_MLX_MODEL_DIR", raising=False)
    monkeypatch.setattr("omnivoice_engine.translation.__file__", str(package_dir / "translation.py"))
    monkeypatch.setattr("omnivoice_engine.translation.importlib.util.find_spec", lambda name: object())

    provider = MLXPromptTranslationProvider()

    assert provider.info().available is True


def test_translategemma_provider_accepts_sharded_mlx_weights(tmp_path: Path, monkeypatch) -> None:
    project_root = tmp_path / "OmniVoice"
    package_dir = project_root / "engine" / "omnivoice_engine"
    model_dir = project_root / "models" / "translategemma-mlx"
    package_dir.mkdir(parents=True)
    model_dir.mkdir(parents=True)
    for filename in ("config.json", "model-00001-of-00002.safetensors", "tokenizer.json"):
        (model_dir / filename).write_text("model")

    monkeypatch.chdir(project_root / "engine")
    monkeypatch.delenv("OMNIVOICE_TRANSLATEGEMMA_MLX_MODEL_DIR", raising=False)
    monkeypatch.setattr("omnivoice_engine.translation.__file__", str(package_dir / "translation.py"))
    monkeypatch.setattr("omnivoice_engine.translation.importlib.util.find_spec", lambda name: object())

    provider = MLXPromptTranslationProvider()

    assert provider.info().available is True


def test_translategemma_provider_reports_missing_default_model_files(tmp_path: Path, monkeypatch) -> None:
    project_root = tmp_path / "OmniVoice"
    package_dir = project_root / "engine" / "omnivoice_engine"
    model_dir = project_root / "models" / "translategemma-mlx"
    package_dir.mkdir(parents=True)
    model_dir.mkdir(parents=True)
    (model_dir / "config.json").write_text("model")

    monkeypatch.chdir(project_root / "engine")
    monkeypatch.delenv("OMNIVOICE_TRANSLATEGEMMA_MLX_MODEL_DIR", raising=False)
    monkeypatch.setattr("omnivoice_engine.translation.__file__", str(package_dir / "translation.py"))
    monkeypatch.setattr("omnivoice_engine.translation.importlib.util.find_spec", lambda name: object())

    provider = MLXPromptTranslationProvider()

    info = provider.info()
    assert info.available is False
    assert info.reason == "model files missing: model*.safetensors, tokenizer.json"


def test_languages_from_chat_template_returns_base_language_options(tmp_path: Path) -> None:
    template = tmp_path / "chat_template.jinja"
    template.write_text(
        """
        {%- set languages = {
            "en": "English",
            "en-US": "English",
            "es": "Spanish",
            "de-DE": "German",
            "de": "German"
        } -%}
        """,
        encoding="utf-8",
    )

    languages = languages_from_chat_template(template)

    assert [(language.code, language.name) for language in languages] == [
        ("en", "English"),
        ("de", "German"),
        ("es", "Spanish"),
    ]


def test_language_name_for_code_resolves_chinese_name() -> None:
    languages = [
        TranslationLanguageOption(code="en", name="English"),
        TranslationLanguageOption(code="zh", name="Chinese"),
    ]

    assert language_name_for_code("zh", languages) == "Chinese"
    assert language_name_for_code("en-US", languages) == "English"
    assert language_name_for_code("zz", languages) == "zz"


def test_translategemma_provider_uses_structured_chat_template_for_generation(tmp_path: Path, monkeypatch) -> None:
    model_dir = tmp_path / "translategemma-mlx"
    model_dir.mkdir()
    for filename in ("config.json", "model.safetensors", "tokenizer.json"):
        (model_dir / filename).write_text("model")
    (model_dir / "chat_template.jinja").write_text(
        """
        {%- set languages = {
            "en": "English",
            "zh": "Chinese"
        } -%}
        """,
        encoding="utf-8",
    )

    captured: dict[str, object] = {}

    class FakeTokenizer:
        def apply_chat_template(self, messages, *, tokenize, add_generation_prompt):
            captured["messages"] = messages
            captured["tokenize"] = tokenize
            captured["add_generation_prompt"] = add_generation_prompt
            return "templated prompt"

    fake_mlx_lm = types.SimpleNamespace(generate=lambda model, tokenizer, prompt, max_tokens, verbose: "你好")
    monkeypatch.setitem(sys.modules, "mlx_lm", fake_mlx_lm)

    provider = MLXPromptTranslationProvider(default_dir=model_dir)
    monkeypatch.setattr(provider, "_load", lambda model_path: (object(), FakeTokenizer()))
    monkeypatch.setattr("omnivoice_engine.translation.importlib.util.find_spec", lambda name: object())

    result = provider.translate(
        TranslationRequest(
            text="Hello",
            provider="translategemma-mlx",
            source_language="auto",
            target_language="zh",
        )
    )

    assert result.text == "你好"
    assert captured["tokenize"] is False
    assert captured["add_generation_prompt"] is True
    assert captured["messages"] == [
        {
            "role": "user",
            "content": [
                {
                    "type": "text",
                    "source_lang_code": "en",
                    "target_lang_code": "zh",
                    "text": "Hello",
                }
            ],
        }
    ]


def test_clean_translation_output_removes_repeated_chat_stop_tokens() -> None:
    raw = "Hello, thank you for coming.\n<end_of_turn>\nSpanish: Hola\n<end_of_turn><end_of_turn>"

    assert clean_translation_output(raw) == "Hello, thank you for coming."


def test_clean_translation_output_keeps_multiline_translation_without_labels() -> None:
    raw = "First translated line.\nSecond translated line."

    assert clean_translation_output(raw) == "First translated line.\nSecond translated line."


def test_translation_script_counts_detects_non_latin_scripts() -> None:
    counts = translation_script_counts("你好 مرحبا Hello")

    assert counts["Han"] == 2
    assert counts["Arabic"] == 5
    assert counts["Latin"] == 5


def test_validate_translation_targets_passes_expected_script_output() -> None:
    class StaticProvider(FakeTranslationProvider):
        def capabilities(self, model_path: str = "", model_provider_id: str | None = None):
            return super().capabilities(model_path, model_provider_id)

        def translate(self, request: TranslationRequest):
            response = super().translate(request)
            if request.target_language == "zh":
                return response.model_copy(update={"text": "你好，谢谢。"})
            return response

    report = validate_translation_targets(
        StaticProvider(),
        text="Hello, thank you.",
        source_language="en",
        target_languages=[TranslationLanguageOption(code="zh", name="Chinese")],
    )

    assert report.tested == 1
    assert report.passed == 1
    assert report.failed == 0
    assert report.items[0].dominant_script == "Han"
    assert report.items[0].status == "pass"
    assert report.items[0].letter_count == 4
    assert report.items[0].expected_script_characters == 4
    assert report.items[0].expected_script_ratio == 1.0
    assert report.items[0].output_preview == "你好，谢谢。"
    assert report.items[0].failure_category is None


def test_validate_translation_targets_flags_expected_script_mismatch() -> None:
    class StaticProvider(FakeTranslationProvider):
        def translate(self, request: TranslationRequest):
            response = super().translate(request)
            return response.model_copy(update={"text": "Hola, gracias."})

    report = validate_translation_targets(
        StaticProvider(),
        text="Hello, thank you.",
        source_language="en",
        target_languages=[TranslationLanguageOption(code="zh", name="Chinese")],
    )

    assert report.tested == 1
    assert report.failed == 1
    assert report.items[0].status == "fail"
    assert report.items[0].dominant_script == "Latin"
    assert report.items[0].failure_category == "wrong-script"
    assert report.items[0].output_preview == "Hola, gracias."
    assert any("Expected script" in note for note in report.items[0].notes)
    assert any("Dominant script was Latin" in note for note in report.items[0].notes)


def test_validate_translation_targets_flags_untranslated_source() -> None:
    class StaticProvider(FakeTranslationProvider):
        def translate(self, request: TranslationRequest):
            response = super().translate(request)
            return response.model_copy(update={"text": "Hello, thank you."})

    report = validate_translation_targets(
        StaticProvider(),
        text="Hello, thank you.",
        source_language="en",
        target_languages=[TranslationLanguageOption(code="es", name="Spanish")],
    )

    assert report.tested == 1
    assert report.items[0].status == "review"
    assert report.items[0].failure_category == "untranslated-source"
    assert any("untranslated source" in note for note in report.items[0].notes)


def test_validate_translation_targets_flags_low_expected_script_coverage() -> None:
    class StaticProvider(FakeTranslationProvider):
        def translate(self, request: TranslationRequest):
            response = super().translate(request)
            return response.model_copy(update={"text": "saluto,လာပြီး ευχαριστω။"})

    report = validate_translation_targets(
        StaticProvider(),
        text="Hello, thank you.",
        source_language="en",
        target_languages=[TranslationLanguageOption(code="my", name="Burmese")],
    )

    assert report.tested == 1
    assert report.items[0].status == "fail"
    assert report.items[0].failure_category == "mixed-script-wrong-language"
    assert report.items[0].expected_script_ratio < 0.65
    assert any("Expected script coverage is low" in note for note in report.items[0].notes)


def test_kurdish_accepts_common_scripts() -> None:
    scripts = expected_scripts_for_language(TranslationLanguageOption(code="ku", name="Kurdish"))

    assert scripts == ("Latin", "Arabic", "Cyrillic")
