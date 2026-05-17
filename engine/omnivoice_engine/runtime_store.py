from __future__ import annotations

import json
import os
import threading
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

from pydantic import ValidationError

from .schemas import (
    ConversationAssistCardRecord,
    ConversationSegmentRecord,
    ConversationSessionRecord,
    EngineEvent,
    StreamingStats,
    TranscriptRecord,
)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


class RuntimeStore:
    def __init__(self, data_dir: str | Path | None = None) -> None:
        self.data_dir = Path(data_dir or os.environ.get("OMNIVOICE_ENGINE_DATA_DIR") or ".omnivoice-engine")
        self.events_path = self.data_dir / "events.jsonl"
        self.transcripts_path = self.data_dir / "transcripts.jsonl"
        self.conversation_sessions_path = self.data_dir / "conversation_sessions.jsonl"
        self.conversation_segments_path = self.data_dir / "conversation_segments.jsonl"
        self.conversation_assist_cards_path = self.data_dir / "conversation_assist_cards.jsonl"
        self.started_at = utc_now()
        self._lock = threading.RLock()
        self._streaming_stats: dict[str, object] = StreamingStats().model_dump()

    def record_event(
        self,
        kind: str,
        message: str,
        *,
        level: str = "info",
        detail: dict[str, object] | None = None,
    ) -> EngineEvent:
        event = EngineEvent(
            id=str(uuid.uuid4()),
            timestamp=utc_now(),
            level=level,
            kind=kind,
            message=message,
            detail=detail or {},
        )
        self._append(self.events_path, event.model_dump(mode="json"))
        return event

    def record_transcript(
        self,
        *,
        source: str,
        raw_text: str,
        cleaned_text: str | None = None,
        provider: str | None = None,
        style: str | None = None,
        audio_bytes: int | None = None,
        sample_rate: int | None = None,
        duration_ms: int | None = None,
    ) -> TranscriptRecord:
        transcript = TranscriptRecord(
            id=str(uuid.uuid4()),
            created_at=utc_now(),
            source=source,
            raw_text=raw_text,
            cleaned_text=cleaned_text,
            provider=provider,
            style=style,
            audio_bytes=audio_bytes,
            sample_rate=sample_rate,
            duration_ms=duration_ms,
        )
        self._append(self.transcripts_path, transcript.model_dump(mode="json"))
        return transcript

    def recent_events(self, limit: int = 200) -> list[EngineEvent]:
        return [EngineEvent.model_validate(item) for item in self._read_recent(self.events_path, limit)]

    def recent_transcripts(self, limit: int = 200) -> list[TranscriptRecord]:
        return [TranscriptRecord.model_validate(item) for item in self._read_recent(self.transcripts_path, limit)]

    def create_conversation_session(
        self,
        *,
        title: str,
        capture_mode: str,
        asr_provider: str,
        diarization_provider: str,
        external_processing_enabled: bool,
    ) -> ConversationSessionRecord:
        session = ConversationSessionRecord(
            id=str(uuid.uuid4()),
            title=title,
            started_at=utc_now(),
            ended_at=None,
            capture_mode=capture_mode,
            asr_provider=asr_provider,
            diarization_provider=diarization_provider,
            external_processing_enabled=external_processing_enabled,
        )
        self._append(self.conversation_sessions_path, session.model_dump(mode="json"))
        return session

    def recent_conversation_sessions(self, limit: int = 100) -> list[ConversationSessionRecord]:
        bounded_limit = max(1, min(limit, 1000))
        sessions: list[ConversationSessionRecord] = []
        for item in reversed(self._parse_lines(self._read_lines(self.conversation_sessions_path))):
            try:
                sessions.append(ConversationSessionRecord.model_validate(item))
            except ValidationError:
                continue
            if len(sessions) >= bounded_limit:
                break
        return sessions

    def conversation_session(self, session_id: str) -> ConversationSessionRecord | None:
        for item in self._parse_lines(self._read_lines(self.conversation_sessions_path)):
            try:
                session = ConversationSessionRecord.model_validate(item)
            except ValidationError:
                continue
            if session.id == session_id:
                return session
        return None

    def stop_conversation_session(self, session_id: str) -> ConversationSessionRecord | None:
        with self._lock:
            sessions: list[ConversationSessionRecord] = []
            for item in self._parse_lines(self._read_lines(self.conversation_sessions_path)):
                try:
                    sessions.append(ConversationSessionRecord.model_validate(item))
                except ValidationError:
                    continue

            stopped: ConversationSessionRecord | None = None
            rewritten: list[dict[str, object]] = []
            for session in sessions:
                if session.id == session_id:
                    session = session.model_copy(update={"ended_at": utc_now()})
                    stopped = session
                rewritten.append(session.model_dump(mode="json"))
            if stopped is not None:
                self._rewrite_jsonl(self.conversation_sessions_path, rewritten)
            return stopped

    def add_conversation_segment(
        self,
        *,
        session_id: str,
        speaker_id: str,
        speaker_display_name: str,
        start_ms: int,
        end_ms: int | None,
        text: str,
        state: str,
        confidence: float | None,
    ) -> ConversationSegmentRecord:
        segment = ConversationSegmentRecord(
            id=str(uuid.uuid4()),
            session_id=session_id,
            speaker_id=speaker_id,
            speaker_display_name=speaker_display_name,
            start_ms=start_ms,
            end_ms=end_ms,
            text=text,
            state=state,
            confidence=confidence,
        )
        self._append(self.conversation_segments_path, segment.model_dump(mode="json"))
        return segment

    def conversation_segments(self, session_id: str) -> list[ConversationSegmentRecord]:
        segments: list[ConversationSegmentRecord] = []
        for item in self._parse_lines(self._read_lines(self.conversation_segments_path)):
            if item.get("session_id") != session_id:
                continue
            try:
                segments.append(ConversationSegmentRecord.model_validate(item))
            except ValidationError:
                continue
        return segments

    def add_conversation_assist_card(
        self,
        *,
        session_id: str,
        kind: str,
        title: str,
        body: str,
        source_references: list[str],
        confidence: float | None,
    ) -> ConversationAssistCardRecord:
        card = ConversationAssistCardRecord(
            id=str(uuid.uuid4()),
            session_id=session_id,
            kind=kind,
            title=title,
            body=body,
            source_references=source_references,
            confidence=confidence,
            status="active",
            created_at=utc_now(),
        )
        self._append(self.conversation_assist_cards_path, card.model_dump(mode="json"))
        return card

    def conversation_assist_cards(self, session_id: str) -> list[ConversationAssistCardRecord]:
        cards: list[ConversationAssistCardRecord] = []
        for item in self._parse_lines(self._read_lines(self.conversation_assist_cards_path)):
            if item.get("session_id") != session_id:
                continue
            try:
                cards.append(ConversationAssistCardRecord.model_validate(item))
            except ValidationError:
                continue
        return cards

    def event_count(self) -> int:
        return self._line_count(self.events_path)

    def transcript_count(self) -> int:
        return self._line_count(self.transcripts_path)

    def streaming_stats(self) -> StreamingStats:
        with self._lock:
            return StreamingStats.model_validate(dict(self._streaming_stats))

    def record_stream_opened(self, *, provider: str, sample_rate: int) -> None:
        with self._lock:
            self._streaming_stats["active_streams"] = int(self._streaming_stats["active_streams"]) + 1
            self._streaming_stats["opened_streams"] = int(self._streaming_stats["opened_streams"]) + 1
            self._streaming_stats["last_provider"] = provider
            self._streaming_stats["last_sample_rate"] = sample_rate
            self._streaming_stats["last_error"] = None

    def record_stream_chunk(self, *, provider: str, chunk_bytes: int) -> None:
        with self._lock:
            self._streaming_stats["total_chunks"] = int(self._streaming_stats["total_chunks"]) + 1
            self._streaming_stats["total_audio_bytes"] = int(self._streaming_stats["total_audio_bytes"]) + chunk_bytes
            self._streaming_stats["last_provider"] = provider

    def record_stream_partial(self, *, provider: str, text: str) -> None:
        with self._lock:
            self._streaming_stats["total_partials"] = int(self._streaming_stats["total_partials"]) + 1
            self._streaming_stats["last_provider"] = provider
            self._streaming_stats["last_partial_text"] = text

    def record_stream_completed(self, *, provider: str) -> None:
        with self._lock:
            self._streaming_stats["completed_streams"] = int(self._streaming_stats["completed_streams"]) + 1
            self._streaming_stats["active_streams"] = max(0, int(self._streaming_stats["active_streams"]) - 1)
            self._streaming_stats["last_provider"] = provider

    def record_stream_failed(self, *, provider: str, error: str) -> None:
        with self._lock:
            self._streaming_stats["failed_streams"] = int(self._streaming_stats["failed_streams"]) + 1
            self._streaming_stats["active_streams"] = max(0, int(self._streaming_stats["active_streams"]) - 1)
            self._streaming_stats["last_provider"] = provider
            self._streaming_stats["last_error"] = error

    def record_stream_closed(self, *, provider: str) -> None:
        with self._lock:
            self._streaming_stats["closed_streams"] = int(self._streaming_stats["closed_streams"]) + 1
            self._streaming_stats["active_streams"] = max(0, int(self._streaming_stats["active_streams"]) - 1)
            self._streaming_stats["last_provider"] = provider

    def export_events(self) -> str:
        return self._read_text(self.events_path)

    def export_transcripts(self) -> str:
        return self._read_text(self.transcripts_path)

    def _append(self, path: Path, payload: dict[str, object]) -> None:
        with self._lock:
            self.data_dir.mkdir(parents=True, exist_ok=True)
            with path.open("a", encoding="utf-8") as handle:
                handle.write(json.dumps(payload, ensure_ascii=False, sort_keys=True))
                handle.write("\n")

    def _rewrite_jsonl(self, path: Path, payloads: list[dict[str, object]]) -> None:
        with self._lock:
            self.data_dir.mkdir(parents=True, exist_ok=True)
            with path.open("w", encoding="utf-8") as handle:
                for payload in payloads:
                    handle.write(json.dumps(payload, ensure_ascii=False, sort_keys=True))
                    handle.write("\n")

    def _read_recent(self, path: Path, limit: int) -> list[dict[str, object]]:
        bounded_limit = max(1, min(limit, 1000))
        lines = self._read_lines(path)
        recent: list[dict[str, object]] = []
        for line in reversed(lines):
            parsed = self._parse_lines([line])
            if not parsed:
                continue
            recent.append(parsed[0])
            if len(recent) >= bounded_limit:
                break
        return recent

    def _read_lines(self, path: Path) -> list[str]:
        with self._lock:
            if not path.exists():
                return []
            return path.read_text(encoding="utf-8").splitlines()

    def _parse_lines(self, lines: Iterable[str]) -> list[dict[str, object]]:
        parsed: list[dict[str, object]] = []
        for line in lines:
            try:
                item = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(item, dict):
                parsed.append(item)
        return parsed

    def _line_count(self, path: Path) -> int:
        return len(self._read_lines(path))

    def _read_text(self, path: Path) -> str:
        with self._lock:
            if not path.exists():
                return ""
            return path.read_text(encoding="utf-8")
