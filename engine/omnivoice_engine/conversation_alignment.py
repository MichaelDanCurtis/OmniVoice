from __future__ import annotations

import uuid
from dataclasses import dataclass

from .providers.base import ASRSentence, ASRToken, ASRTranscript
from .schemas import ConversationSpeakerLineRecord, SpeakerTurnRecord


@dataclass(frozen=True)
class TimedTextUnit:
    text: str
    start_ms: int
    end_ms: int
    confidence: float | None = None


@dataclass
class SpeakerLineDraft:
    speaker_id: str
    start_ms: int
    end_ms: int
    text_parts: list[str]
    confidences: list[float]


def build_speaker_lines(
    *,
    session_id: str,
    transcript: ASRTranscript,
    speaker_turns: list[SpeakerTurnRecord],
    audio_start_ms: int,
    source_provider: str,
    merge_gap_ms: int = 700,
) -> list[ConversationSpeakerLineRecord]:
    turns = _usable_turns(speaker_turns)
    units = _timed_units(transcript)
    if not turns or not units:
        return []

    drafts: list[SpeakerLineDraft] = []
    for unit in units:
        absolute_unit = TimedTextUnit(
            text=unit.text,
            start_ms=audio_start_ms + unit.start_ms,
            end_ms=audio_start_ms + unit.end_ms,
            confidence=unit.confidence,
        )
        speaker_id = _speaker_for_unit(absolute_unit, turns)
        if speaker_id is None:
            continue

        if drafts and drafts[-1].speaker_id == speaker_id and absolute_unit.start_ms - drafts[-1].end_ms <= merge_gap_ms:
            drafts[-1].end_ms = max(drafts[-1].end_ms, absolute_unit.end_ms)
            drafts[-1].text_parts.append(unit.text)
            if unit.confidence is not None:
                drafts[-1].confidences.append(unit.confidence)
        else:
            drafts.append(
                SpeakerLineDraft(
                    speaker_id=speaker_id,
                    start_ms=absolute_unit.start_ms,
                    end_ms=absolute_unit.end_ms,
                    text_parts=[unit.text],
                    confidences=[] if unit.confidence is None else [unit.confidence],
                )
            )

    return [
        ConversationSpeakerLineRecord(
            id=str(uuid.uuid4()),
            session_id=session_id,
            speaker_id=draft.speaker_id,
            start_ms=draft.start_ms,
            end_ms=draft.end_ms,
            text=_join_text_parts(draft.text_parts),
            confidence=_mean(draft.confidences),
            source_provider=source_provider,
        )
        for draft in drafts
        if _join_text_parts(draft.text_parts)
    ]


def _usable_turns(speaker_turns: list[SpeakerTurnRecord]) -> list[SpeakerTurnRecord]:
    return sorted(
        [turn for turn in speaker_turns if turn.end_ms is not None and turn.end_ms > turn.start_ms],
        key=lambda turn: (turn.start_ms, turn.end_ms or turn.start_ms),
    )


def _timed_units(transcript: ASRTranscript) -> list[TimedTextUnit]:
    if transcript.tokens:
        units: list[TimedTextUnit] = []
        for token in transcript.tokens:
            unit = _unit_from_token(token)
            if unit is not None:
                units.append(unit)
        return units

    units = []
    for sentence in transcript.sentences:
        unit = _unit_from_sentence(sentence)
        if unit is not None:
            units.append(unit)
    return units


def _unit_from_token(token: ASRToken) -> TimedTextUnit | None:
    text = token.text
    if not text or token.start_ms is None:
        return None
    end_ms = token.end_ms if token.end_ms is not None and token.end_ms >= token.start_ms else token.start_ms
    return TimedTextUnit(text=text, start_ms=token.start_ms, end_ms=end_ms, confidence=token.confidence)


def _unit_from_sentence(sentence: ASRSentence) -> TimedTextUnit | None:
    text = sentence.text
    if not text or sentence.start_ms is None:
        return None
    end_ms = sentence.end_ms if sentence.end_ms is not None and sentence.end_ms >= sentence.start_ms else sentence.start_ms
    return TimedTextUnit(text=text, start_ms=sentence.start_ms, end_ms=end_ms, confidence=sentence.confidence)


def _speaker_for_unit(unit: TimedTextUnit, turns: list[SpeakerTurnRecord]) -> str | None:
    best_turn: SpeakerTurnRecord | None = None
    best_overlap = 0
    for turn in turns:
        overlap = _overlap_ms(unit.start_ms, unit.end_ms, turn.start_ms, turn.end_ms or turn.start_ms)
        if overlap > best_overlap:
            best_turn = turn
            best_overlap = overlap
    if best_turn is not None and best_overlap > 0:
        return best_turn.speaker_id

    midpoint = (unit.start_ms + unit.end_ms) // 2
    containing = [turn for turn in turns if turn.start_ms <= midpoint <= (turn.end_ms or turn.start_ms)]
    if containing:
        return min(containing, key=lambda turn: (turn.end_ms or turn.start_ms) - turn.start_ms).speaker_id

    nearest = min(
        turns,
        key=lambda turn: min(abs(midpoint - turn.start_ms), abs(midpoint - (turn.end_ms or turn.start_ms))),
        default=None,
    )
    if nearest is None:
        return None
    distance = min(abs(midpoint - nearest.start_ms), abs(midpoint - (nearest.end_ms or nearest.start_ms)))
    return nearest.speaker_id if distance <= 750 else None


def _overlap_ms(start_a: int, end_a: int, start_b: int, end_b: int) -> int:
    if end_a <= start_a:
        end_a = start_a + 1
    if end_b <= start_b:
        end_b = start_b + 1
    return max(0, min(end_a, end_b) - max(start_a, start_b))


def _join_text_parts(parts: list[str]) -> str:
    return "".join(parts).strip()


def _mean(values: list[float]) -> float | None:
    if not values:
        return None
    return sum(values) / len(values)
