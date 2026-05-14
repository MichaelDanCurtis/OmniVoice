from __future__ import annotations

import re

from .schemas import CleanupRequest, CleanupResponse


CORRECTION_PATTERNS = [
    r"\bno wait[,]?\s+",
    r"\bscratch that[,]?\s+",
    r"\bcorrection[,]?\s+",
]

INLINE_REPLACEMENT_PATTERNS = [
    (re.compile(r"\bfor\s+([A-Za-z]+),\s+actually\s+([A-Za-z]+)", re.IGNORECASE), r"for \2"),
    (re.compile(r"\bto\s+([A-Za-z]+),\s+actually\s+([A-Za-z]+)", re.IGNORECASE), r"to \2"),
]

LEADING_FILLERS = re.compile(r"^(um|uh|like|you know|i just wanted to say that)\s+", re.IGNORECASE)


def clean_transcript(request: CleanupRequest) -> CleanupResponse:
    raw = " ".join(request.raw_transcript.strip().split())
    if request.style == "raw":
        return CleanupResponse(text=raw, cleanup_applied=False)

    text = _apply_clause_corrections(raw)
    text = _apply_inline_replacements(text)
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


def _normalize_capitalization(text: str) -> str:
    if not text:
        return text
    return text[0].upper() + text[1:]


def _ensure_terminal_punctuation(text: str) -> str:
    if not text or text[-1] in ".!?":
        return text
    return text + "."
