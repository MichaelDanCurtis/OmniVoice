from omnivoice_engine.conversation_alignment import build_speaker_lines
from omnivoice_engine.providers.base import ASRToken, ASRTranscript
from omnivoice_engine.schemas import SpeakerTurnRecord


def test_build_speaker_lines_assigns_aligned_tokens_to_turns():
    transcript = ASRTranscript(
        text="Bob asked. Sarah answered.",
        tokens=(
            ASRToken(text="Bob", start_ms=0, end_ms=300, confidence=0.9),
            ASRToken(text=" asked.", start_ms=300, end_ms=900, confidence=0.8),
            ASRToken(text=" Sarah", start_ms=1_000, end_ms=1_300, confidence=0.95),
            ASRToken(text=" answered.", start_ms=1_300, end_ms=2_000, confidence=0.85),
        ),
    )
    turns = [
        SpeakerTurnRecord(
            id="turn-1",
            session_id="session-1",
            speaker_id="speaker-1",
            start_ms=250,
            end_ms=1_150,
            source_provider="sortformer",
        ),
        SpeakerTurnRecord(
            id="turn-2",
            session_id="session-1",
            speaker_id="speaker-2",
            start_ms=1_150,
            end_ms=2_250,
            source_provider="sortformer",
        ),
    ]

    lines = build_speaker_lines(
        session_id="session-1",
        transcript=transcript,
        speaker_turns=turns,
        audio_start_ms=250,
        source_provider="sortformer",
    )

    assert [line.speaker_id for line in lines] == ["speaker-1", "speaker-2"]
    assert [line.text for line in lines] == ["Bob asked.", "Sarah answered."]
    assert [(line.start_ms, line.end_ms) for line in lines] == [(250, 1_150), (1_250, 2_250)]


def test_build_speaker_lines_falls_back_to_sentence_timing_when_tokens_are_missing():
    from omnivoice_engine.providers.base import ASRSentence

    transcript = ASRTranscript(
        text="First sentence. Second sentence.",
        sentences=(
            ASRSentence(text="First sentence.", start_ms=0, end_ms=800),
            ASRSentence(text="Second sentence.", start_ms=900, end_ms=1_700),
        ),
    )
    turns = [
        SpeakerTurnRecord(
            id="turn-1",
            session_id="session-1",
            speaker_id="speaker-1",
            start_ms=0,
            end_ms=850,
            source_provider="sortformer",
        ),
        SpeakerTurnRecord(
            id="turn-2",
            session_id="session-1",
            speaker_id="speaker-2",
            start_ms=850,
            end_ms=1_800,
            source_provider="sortformer",
        ),
    ]

    lines = build_speaker_lines(
        session_id="session-1",
        transcript=transcript,
        speaker_turns=turns,
        audio_start_ms=0,
        source_provider="sortformer",
    )

    assert [line.text for line in lines] == ["First sentence.", "Second sentence."]
