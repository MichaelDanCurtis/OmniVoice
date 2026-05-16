from __future__ import annotations

import json
import os
import threading
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

from .schemas import EngineEvent, TranscriptRecord


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


class RuntimeStore:
    def __init__(self, data_dir: str | Path | None = None) -> None:
        self.data_dir = Path(data_dir or os.environ.get("OMNIVOICE_ENGINE_DATA_DIR") or ".omnivoice-engine")
        self.events_path = self.data_dir / "events.jsonl"
        self.transcripts_path = self.data_dir / "transcripts.jsonl"
        self.started_at = utc_now()
        self._lock = threading.Lock()

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

    def event_count(self) -> int:
        return self._line_count(self.events_path)

    def transcript_count(self) -> int:
        return self._line_count(self.transcripts_path)

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

    def _read_recent(self, path: Path, limit: int) -> list[dict[str, object]]:
        bounded_limit = max(1, min(limit, 1000))
        lines = self._read_lines(path)
        recent = lines[-bounded_limit:]
        return list(reversed([item for item in self._parse_lines(recent)]))

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
