from __future__ import annotations

import re

from .schemas import CleanupRequest, CleanupResponse


CORRECTION_PATTERNS = [
    r"\bno wait[,.!?]?\s+",
    r"\bscratch that[,.!?]?\s+",
    r"\boops[,]?\s+correction[,.!?]?\s+",
    r"\bcorrection[,.!?]?\s+",
]

INLINE_REPLACEMENT_PATTERNS = [
    (re.compile(r"\bfor\s+([A-Za-z]+),\s+actually\s+([A-Za-z]+)", re.IGNORECASE), r"for \2"),
    (re.compile(r"\bto\s+([A-Za-z]+),\s+actually\s+([A-Za-z]+)", re.IGNORECASE), r"to \2"),
]

LEADING_FILLERS = re.compile(r"^(um|uh|like|you know|i just wanted to say that)\s+", re.IGNORECASE)
UI_PLACEHOLDER_SUFFIXES = [
    re.compile(r"\s*Ask for follow-up changes[\s.!?\"'”’]*$", re.IGNORECASE),
    re.compile(r"\s*Type\s+(?:/|slash)\s+for\s+commands[\s.!?\"'”’]*$", re.IGNORECASE),
]
QUOTE_PATTERNS = [
    re.compile(r"\bopen quote\s+(.+?)\s+close quote\b", re.IGNORECASE),
    re.compile(r"\bquote\s+(.+?)\s+quote\b", re.IGNORECASE),
]
SPOKEN_PUNCTUATION_PATTERNS = [
    (re.compile(r"\s+\bcomma\b\s+", re.IGNORECASE), ", "),
    (re.compile(r"\s+\bperiod\b\s*", re.IGNORECASE), ". "),
    (re.compile(r"\s+\bfull stop\b\s*", re.IGNORECASE), ". "),
    (re.compile(r"\s+\bquestion mark\b\s*", re.IGNORECASE), "? "),
    (re.compile(r"\s+\bexclamation mark\b\s*", re.IGNORECASE), "! "),
    (re.compile(r"\s+\bexclamation point\b\s*", re.IGNORECASE), "! "),
    (re.compile(r"\s+\bcolon\b\s+", re.IGNORECASE), ": "),
    (re.compile(r"\s+\bsemicolon\b\s+", re.IGNORECASE), "; "),
    (re.compile(r"\bnew paragraph\b", re.IGNORECASE), "\n\n"),
    (re.compile(r"\bnew line\b", re.IGNORECASE), "\n"),
    (re.compile(r"\bdouble quote\b", re.IGNORECASE), '"'),
    (re.compile(r"\bsingle quote\b", re.IGNORECASE), "'"),
]


def clean_transcript(request: CleanupRequest) -> CleanupResponse:
    raw = " ".join(request.raw_transcript.strip().split())
    raw = _remove_ui_placeholder_suffixes(raw)
    if request.style == "raw":
        return CleanupResponse(text=raw, cleanup_applied=False)

    text = _apply_clause_corrections(raw)
    text = _apply_inline_replacements(text)
    text = _apply_spoken_text_commands(text)
    text = _apply_dictionary_terms(text, request.dictionary_terms)
    text = _apply_dictionary_entries(text, request.dictionary_entries)
    if request.style == "concise":
        text = _remove_leading_fillers(text)
    text = _normalize_capitalization(text)
    text = _ensure_terminal_punctuation(text)
    return CleanupResponse(text=text, cleanup_applied=True)


def _apply_clause_corrections(text: str) -> str:
    matches = [
        match
        for pattern in CORRECTION_PATTERNS
        for match in re.finditer(pattern, text, re.IGNORECASE)
    ]
    if not matches:
        return text
    last_match = max(matches, key=lambda match: match.end())
    return text[last_match.end() :].strip(" ,.")


def _apply_inline_replacements(text: str) -> str:
    current = text
    for pattern, replacement in INLINE_REPLACEMENT_PATTERNS:
        current = pattern.sub(replacement, current)
    current = re.sub(r"\bactually\s+", "", current, flags=re.IGNORECASE)
    return current.strip()


def _remove_leading_fillers(text: str) -> str:
    current = text
    while True:
        updated = LEADING_FILLERS.sub("", current).strip()
        if updated == current:
            return current
        current = updated


def _apply_spoken_text_commands(text: str) -> str:
    current = text
    for pattern in QUOTE_PATTERNS:
        current = pattern.sub(lambda match: f'"{match.group(1).strip()}"', current)
    for pattern, replacement in SPOKEN_PUNCTUATION_PATTERNS:
        current = pattern.sub(replacement, current)
    current = re.sub(r"[ \t]+([,.;:!?])", r"\1", current)
    current = re.sub(r"([,.;:])(?=\S)", r"\1 ", current)
    current = re.sub(r"[ \t]{2,}", " ", current)
    return current.strip()


def _apply_dictionary_terms(text: str, terms: list[str]) -> str:
    current = text
    for term in terms:
        cleaned_term = " ".join(term.strip().split())
        if not cleaned_term:
            continue
        pattern = re.compile(rf"\b{re.escape(cleaned_term)}\b", re.IGNORECASE)
        current = pattern.sub(cleaned_term, current)
    return current


def _entry_field(entry, name, default):
    if isinstance(entry, dict):
        return entry.get(name, default)
    return getattr(entry, name, default)


def _apply_dictionary_entries(text: str, entries) -> str:
    """Apply learned/manual dictionary entries: replace each enabled entry's aliases with its
    canonical (case-insensitive, whole-word), then normalize the canonical's own casing.
    Accepts pydantic models or plain dicts."""
    current = text
    for entry in entries:
        if not _entry_field(entry, "enabled", True):
            continue
        canonical = " ".join(str(_entry_field(entry, "canonical", "")).strip().split())
        if not canonical:
            continue
        for alias in _entry_field(entry, "aliases", []) or []:
            cleaned_alias = " ".join(str(alias).strip().split())
            if not cleaned_alias:
                continue
            pattern = re.compile(rf"\b{re.escape(cleaned_alias)}\b", re.IGNORECASE)
            current = pattern.sub(canonical, current)
        pattern = re.compile(rf"\b{re.escape(canonical)}\b", re.IGNORECASE)
        current = pattern.sub(canonical, current)
    return current


def _remove_ui_placeholder_suffixes(text: str) -> str:
    current = text
    for pattern in UI_PLACEHOLDER_SUFFIXES:
        current = pattern.sub("", current).strip()
    return current


def _normalize_capitalization(text: str) -> str:
    if not text:
        return text
    return text[0].upper() + text[1:]


def _ensure_terminal_punctuation(text: str) -> str:
    if not text or text[-1] in ".!?":
        return text
    return text + "."
