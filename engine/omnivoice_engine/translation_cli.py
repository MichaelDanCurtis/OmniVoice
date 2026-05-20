from __future__ import annotations

import argparse
import json

from .schemas import TranslationRequest
from .translation import TranslationRegistry, validate_translation_targets


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Translate text with a local OmniVoice translation provider.")
    parser.add_argument("--text", required=True, help="Text to translate.")
    parser.add_argument("--provider", default="fake", choices=["fake", "translategemma-mlx", "nllb-200-distilled-600m"])
    parser.add_argument("--source-language", default="auto", help="Source language code, or auto.")
    parser.add_argument("--target-language", default="en", help="Target language code.")
    parser.add_argument("--model-path", default="", help="Optional local model folder.")
    parser.add_argument("--context", action="append", default=[], help="Optional context string; may be repeated.")
    parser.add_argument("--validate-targets", action="store_true", help="Translate the test text into every advertised target language.")
    parser.add_argument("--max-languages", type=int, default=None, help="Limit validation to the first N advertised languages.")
    parser.add_argument("--json", action="store_true", help="Emit the full translation event as JSON.")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.max_languages is not None and args.max_languages < 1:
        parser.error("--max-languages must be greater than zero")
    registry = TranslationRegistry()
    provider = registry.get(args.provider)
    if args.validate_targets:
        report = validate_translation_targets(
            provider,
            text=args.text,
            source_language=args.source_language,
            model_path=args.model_path,
            max_languages=args.max_languages,
        )
        if args.json:
            print(json.dumps(report.model_dump(), indent=2, sort_keys=True, ensure_ascii=False))
        else:
            print(
                f"Validated {report.tested} languages: "
                f"{report.passed} pass, {report.review} review, {report.failed} fail"
            )
            for item in report.items:
                print(f"{item.status.upper():6} {item.code:8} {item.name:24} {item.text}")
        return 0

    request = TranslationRequest(
        text=args.text,
        provider=args.provider,
        source_language=args.source_language,
        target_language=args.target_language,
        model_path=args.model_path,
        context=args.context,
    )
    result = provider.translate(request)
    if args.json:
        print(json.dumps(result.model_dump(), indent=2, sort_keys=True))
    else:
        print(result.text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
