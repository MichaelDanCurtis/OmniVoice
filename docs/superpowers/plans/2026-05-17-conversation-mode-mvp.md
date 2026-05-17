# Conversation Mode MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first working Conversation Mode slice: a dedicated live meeting window with paragraph-style captions, speaker bars, timestamps, persisted conversation records, and an assist rail with Copy/Speak/Sources actions.

**Architecture:** Add shared conversation models to `OmniVoiceCore`, persist conversation sessions in the local FastAPI engine, and expose the engine data through `EngineClient`. The macOS app gets a separate Conversation Mode window and a `ConversationRecorderService` that reuses the current microphone capture and streaming ASR path, while speaker labels and assist cards are pluggable MVP services so real diarization and retrieval can land later.

**Tech Stack:** Swift/SwiftUI, AVFoundation, URLSession WebSocket, XCTest, FastAPI, Pydantic, pytest, JSONL local persistence, AppKit pasteboard, `NSSpeechSynthesizer`.

---

## Scope

This plan implements the Conversation Mode MVP foundation. It intentionally includes microphone-only live recording and mock/pluggable diarization, but does not implement real system/app audio capture, Sortformer integration, or Obsidian/MCP retrieval yet.

The MVP must still feel real:

- a user can open a Conversation window
- start a microphone conversation recording
- see live paragraph-style transcript updates
- stop and review the conversation
- copy transcript/assist text
- speak assist card text with local TTS
- see persisted sessions after app refresh

## File Structure

- `Sources/OmniVoiceCore/ConversationModels.swift`: shared conversation, speaker, segment, and assist-card value models.
- `Tests/OmniVoiceCoreTests/ConversationModelsTests.swift`: model behavior tests.
- `engine/omnivoice_engine/schemas.py`: Pydantic conversation request/response models.
- `engine/omnivoice_engine/runtime_store.py`: JSONL session, segment, speaker, and assist-card persistence.
- `engine/omnivoice_engine/main.py`: conversation endpoints.
- `engine/tests/test_conversations.py`: engine conversation endpoint tests.
- `Sources/OmniVoiceCore/EngineClient.swift`: Swift conversation client models and methods.
- `Tests/OmniVoiceCoreTests/EngineClientTests.swift`: Swift decode/encode coverage for conversation payloads.
- `Sources/OmniVoiceApp/ConversationRecorderService.swift`: microphone capture plus streaming ASR bridge for Conversation Mode.
- `Sources/OmniVoiceApp/ConversationModeView.swift`: dedicated live transcript and assist rail UI.
- `Sources/OmniVoiceApp/AppModel.swift`: conversation state and actions.
- `Sources/OmniVoiceApp/OmniVoiceApp.swift`: Conversation Mode window scene and open-window wiring.
- `Sources/OmniVoiceApp/MenuBarControlsView.swift`: menu entry to open Conversation Mode.
- `Sources/OmniVoiceApp/SettingsView.swift`: optional entry point and capability text update.
- `docs/OMNIVOICE_QUICK_REFERENCE.md`: user help for Conversation Mode.
- `docs/V2_FEATURE_GUI_MAP.md`: feature map update.

---

### Task 1: Shared Conversation Models

**Files:**
- Create: `Sources/OmniVoiceCore/ConversationModels.swift`
- Create: `Tests/OmniVoiceCoreTests/ConversationModelsTests.swift`

- [ ] **Step 1: Write failing model tests**

Create `Tests/OmniVoiceCoreTests/ConversationModelsTests.swift`:

```swift
import XCTest
@testable import OmniVoiceCore

final class ConversationModelsTests: XCTestCase {
    func testSpeakerIdentityDefaultsToGenericName() {
        let speaker = ConversationSpeakerIdentity(
            id: "speaker-1",
            displayName: "Speaker 1",
            origin: .generic,
            colorHex: "#FDE047"
        )

        XCTAssertEqual(speaker.displayName, "Speaker 1")
        XCTAssertEqual(speaker.origin, .generic)
    }

    func testSegmentUsesSpeakerDisplayName() {
        let segment = ConversationSegment(
            id: "seg-1",
            sessionID: "session-1",
            speakerID: "speaker-1",
            speakerDisplayName: "Bob",
            startMs: 18_130,
            endMs: 21_900,
            text: "How many users did we have last year?",
            state: .settled,
            confidence: 0.91
        )

        XCTAssertEqual(segment.timestampLabel, "00:18")
        XCTAssertEqual(segment.speakerDisplayName, "Bob")
        XCTAssertEqual(segment.state, .settled)
    }

    func testAssistCardCopyTextUsesBodyOnly() {
        let card = ConversationAssistCard(
            id: "card-1",
            sessionID: "session-1",
            kind: .answer,
            title: "Answer Found",
            body: "Last year we had 18,420 active users.",
            sourceReferences: ["Obsidian/adoption-2025.md"],
            confidence: 0.78,
            status: .active,
            createdAt: "2026-05-17T08:00:00Z"
        )

        XCTAssertEqual(card.copyText, "Last year we had 18,420 active users.")
        XCTAssertEqual(card.sourceReferences, ["Obsidian/adoption-2025.md"])
    }

    func testConversationSessionDetectsActiveState() {
        let active = ConversationSession(
            id: "session-1",
            title: "Conversation",
            startedAt: "2026-05-17T08:00:00Z",
            endedAt: nil,
            captureMode: .microphoneOnly,
            asrProvider: "parakeet-tdt",
            diarizationProvider: "mock",
            externalProcessingEnabled: false
        )

        XCTAssertTrue(active.isActive)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter ConversationModelsTests
```

Expected: compile fails because `ConversationSession`, `ConversationSegment`, `ConversationSpeakerIdentity`, and `ConversationAssistCard` do not exist.

- [ ] **Step 3: Implement shared models**

Create `Sources/OmniVoiceCore/ConversationModels.swift`:

```swift
import Foundation

public enum ConversationCaptureMode: String, Codable, CaseIterable, Equatable, Sendable {
    case microphoneOnly = "microphone_only"
    case systemAudioOnly = "system_audio_only"
    case microphoneAndSystemAudio = "microphone_and_system_audio"
    case mixedFallback = "mixed_fallback"

    public var displayName: String {
        switch self {
        case .microphoneOnly: "Microphone"
        case .systemAudioOnly: "System Audio"
        case .microphoneAndSystemAudio: "Mic + System"
        case .mixedFallback: "Mixed"
        }
    }
}

public enum ConversationSegmentState: String, Codable, Equatable, Sendable {
    case live
    case settled
    case correctedSpeaker = "corrected_speaker"
}

public enum ConversationSpeakerOrigin: String, Codable, Equatable, Sendable {
    case generic
    case inferred
    case userConfirmed = "user_confirmed"
}

public enum ConversationAssistCardKind: String, Codable, Equatable, Sendable {
    case question
    case answer
    case timeZone = "time_zone"
    case followUp = "follow_up"
    case actionItem = "action_item"
    case warning
}

public enum ConversationAssistCardStatus: String, Codable, Equatable, Sendable {
    case active
    case copied
    case spoken
    case pinned
    case dismissed
}

public struct ConversationSession: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let startedAt: String
    public let endedAt: String?
    public let captureMode: ConversationCaptureMode
    public let asrProvider: String
    public let diarizationProvider: String
    public let externalProcessingEnabled: Bool

    public var isActive: Bool { endedAt == nil }

    public init(
        id: String,
        title: String,
        startedAt: String,
        endedAt: String? = nil,
        captureMode: ConversationCaptureMode,
        asrProvider: String,
        diarizationProvider: String,
        externalProcessingEnabled: Bool
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.captureMode = captureMode
        self.asrProvider = asrProvider
        self.diarizationProvider = diarizationProvider
        self.externalProcessingEnabled = externalProcessingEnabled
    }
}

public struct ConversationSpeakerIdentity: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var displayName: String
    public var origin: ConversationSpeakerOrigin
    public let colorHex: String

    public init(id: String, displayName: String, origin: ConversationSpeakerOrigin, colorHex: String) {
        self.id = id
        self.displayName = displayName
        self.origin = origin
        self.colorHex = colorHex
    }
}

public struct ConversationSegment: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let sessionID: String
    public let speakerID: String
    public let speakerDisplayName: String
    public let startMs: Int
    public let endMs: Int?
    public let text: String
    public let state: ConversationSegmentState
    public let confidence: Double?

    public var sessionId: String { sessionID }

    public var timestampLabel: String {
        let totalSeconds = max(0, startMs / 1000)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    public init(
        id: String,
        sessionID: String,
        speakerID: String,
        speakerDisplayName: String,
        startMs: Int,
        endMs: Int? = nil,
        text: String,
        state: ConversationSegmentState,
        confidence: Double? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.speakerID = speakerID
        self.speakerDisplayName = speakerDisplayName
        self.startMs = startMs
        self.endMs = endMs
        self.text = text
        self.state = state
        self.confidence = confidence
    }
}

public struct ConversationAssistCard: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let sessionID: String
    public let kind: ConversationAssistCardKind
    public let title: String
    public let body: String
    public let sourceReferences: [String]
    public let confidence: Double?
    public var status: ConversationAssistCardStatus
    public let createdAt: String

    public var sessionId: String { sessionID }
    public var copyText: String { body.trimmingCharacters(in: .whitespacesAndNewlines) }

    public init(
        id: String,
        sessionID: String,
        kind: ConversationAssistCardKind,
        title: String,
        body: String,
        sourceReferences: [String] = [],
        confidence: Double? = nil,
        status: ConversationAssistCardStatus = .active,
        createdAt: String
    ) {
        self.id = id
        self.sessionID = sessionID
        self.kind = kind
        self.title = title
        self.body = body
        self.sourceReferences = sourceReferences
        self.confidence = confidence
        self.status = status
        self.createdAt = createdAt
    }
}
```

- [ ] **Step 4: Verify tests pass**

Run:

```bash
swift test --filter ConversationModelsTests
```

Expected: `ConversationModelsTests` passes.

- [ ] **Step 5: Commit**

```bash
git add Sources/OmniVoiceCore/ConversationModels.swift Tests/OmniVoiceCoreTests/ConversationModelsTests.swift
git commit -m "feat: add conversation core models"
```

---

### Task 2: Engine Conversation Persistence And API

**Files:**
- Modify: `engine/omnivoice_engine/schemas.py`
- Modify: `engine/omnivoice_engine/runtime_store.py`
- Modify: `engine/omnivoice_engine/main.py`
- Create: `engine/tests/test_conversations.py`

- [ ] **Step 1: Write failing engine tests**

Create `engine/tests/test_conversations.py`:

```python
from fastapi.testclient import TestClient

from omnivoice_engine.main import app
from omnivoice_engine.runtime_store import RuntimeStore


client = TestClient(app)


def test_conversation_session_round_trip(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)
    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)

    response = client.post(
        "/api/conversations",
        json={
            "title": "Roadmap call",
            "capture_mode": "microphone_only",
            "asr_provider": "parakeet-tdt",
            "diarization_provider": "mock",
            "external_processing_enabled": False,
        },
    )

    assert response.status_code == 200
    session = response.json()
    assert session["title"] == "Roadmap call"
    assert session["capture_mode"] == "microphone_only"
    assert session["ended_at"] is None

    history = client.get("/api/conversations").json()
    assert history[0]["id"] == session["id"]


def test_conversation_segments_and_assist_cards(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)
    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    session = client.post(
        "/api/conversations",
        json={
            "title": "Roadmap call",
            "capture_mode": "microphone_only",
            "asr_provider": "parakeet-tdt",
            "diarization_provider": "mock",
            "external_processing_enabled": False,
        },
    ).json()

    segment_response = client.post(
        f"/api/conversations/{session['id']}/segments",
        json={
            "speaker_id": "speaker-1",
            "speaker_display_name": "Speaker 1",
            "start_ms": 18130,
            "end_ms": 21900,
            "text": "How many users did we have last year?",
            "state": "settled",
            "confidence": 0.91,
        },
    )
    card_response = client.post(
        f"/api/conversations/{session['id']}/assist-cards",
        json={
            "kind": "answer",
            "title": "Answer Found",
            "body": "Last year we had 18,420 active users.",
            "source_references": ["Obsidian/adoption-2025.md"],
            "confidence": 0.78,
        },
    )

    assert segment_response.status_code == 200
    assert card_response.status_code == 200

    detail = client.get(f"/api/conversations/{session['id']}").json()
    assert detail["session"]["id"] == session["id"]
    assert detail["segments"][0]["text"] == "How many users did we have last year?"
    assert detail["assist_cards"][0]["body"] == "Last year we had 18,420 active users."


def test_conversation_stop_sets_ended_at(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)
    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    session = client.post(
        "/api/conversations",
        json={
            "title": "Roadmap call",
            "capture_mode": "microphone_only",
            "asr_provider": "parakeet-tdt",
            "diarization_provider": "mock",
            "external_processing_enabled": False,
        },
    ).json()

    response = client.post(f"/api/conversations/{session['id']}/stop")

    assert response.status_code == 200
    assert response.json()["ended_at"] is not None
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd engine
uv run pytest tests/test_conversations.py -q
```

Expected: tests fail with `404 Not Found` because conversation endpoints do not exist.

- [ ] **Step 3: Add Pydantic schemas**

Modify `engine/omnivoice_engine/schemas.py` by adding these models after `TranscriptRecord`:

```python
class ConversationSessionCreateRequest(BaseModel):
    title: str = "Conversation"
    capture_mode: str = "microphone_only"
    asr_provider: str = "parakeet-tdt"
    diarization_provider: str = "mock"
    external_processing_enabled: bool = False


class ConversationSessionRecord(BaseModel):
    id: str
    title: str
    started_at: str
    ended_at: str | None = None
    capture_mode: str
    asr_provider: str
    diarization_provider: str
    external_processing_enabled: bool = False


class ConversationSegmentCreateRequest(BaseModel):
    speaker_id: str
    speaker_display_name: str
    start_ms: int
    end_ms: int | None = None
    text: str
    state: str = "settled"
    confidence: float | None = None


class ConversationSegmentRecord(BaseModel):
    id: str
    session_id: str
    speaker_id: str
    speaker_display_name: str
    start_ms: int
    end_ms: int | None = None
    text: str
    state: str = "settled"
    confidence: float | None = None


class ConversationAssistCardCreateRequest(BaseModel):
    kind: str
    title: str
    body: str
    source_references: list[str] = Field(default_factory=list)
    confidence: float | None = None


class ConversationAssistCardRecord(BaseModel):
    id: str
    session_id: str
    kind: str
    title: str
    body: str
    source_references: list[str] = Field(default_factory=list)
    confidence: float | None = None
    status: str = "active"
    created_at: str


class ConversationDetail(BaseModel):
    session: ConversationSessionRecord
    segments: list[ConversationSegmentRecord] = Field(default_factory=list)
    assist_cards: list[ConversationAssistCardRecord] = Field(default_factory=list)
```

- [ ] **Step 4: Add runtime persistence methods**

Modify `engine/omnivoice_engine/runtime_store.py`:

- import the new schema types
- add paths:

```python
self.conversation_sessions_path = self.data_dir / "conversation_sessions.jsonl"
self.conversation_segments_path = self.data_dir / "conversation_segments.jsonl"
self.conversation_assist_cards_path = self.data_dir / "conversation_assist_cards.jsonl"
```

- add these methods to `RuntimeStore`:

```python
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
    return [
        ConversationSessionRecord.model_validate(item)
        for item in self._read_recent(self.conversation_sessions_path, limit)
    ]


def conversation_session(self, session_id: str) -> ConversationSessionRecord | None:
    for item in self._parse_lines(self._read_lines(self.conversation_sessions_path)):
        session = ConversationSessionRecord.model_validate(item)
        if session.id == session_id:
            return session
    return None


def stop_conversation_session(self, session_id: str) -> ConversationSessionRecord | None:
    sessions = [ConversationSessionRecord.model_validate(item) for item in self._parse_lines(self._read_lines(self.conversation_sessions_path))]
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
    return [
        ConversationSegmentRecord.model_validate(item)
        for item in self._parse_lines(self._read_lines(self.conversation_segments_path))
        if item.get("session_id") == session_id
    ]


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
    return [
        ConversationAssistCardRecord.model_validate(item)
        for item in self._parse_lines(self._read_lines(self.conversation_assist_cards_path))
        if item.get("session_id") == session_id
    ]


def _rewrite_jsonl(self, path: Path, payloads: list[dict[str, object]]) -> None:
    with self._lock:
        self.data_dir.mkdir(parents=True, exist_ok=True)
        with path.open("w", encoding="utf-8") as handle:
            for payload in payloads:
                handle.write(json.dumps(payload, ensure_ascii=False, sort_keys=True))
                handle.write("\n")
```

- [ ] **Step 5: Add FastAPI routes**

Modify `engine/omnivoice_engine/main.py`:

- import new schema types
- add routes before `/api/events`:

```python
@app.post("/api/conversations", response_model=ConversationSessionRecord)
def create_conversation(request: ConversationSessionCreateRequest) -> ConversationSessionRecord:
    session = runtime_store.create_conversation_session(
        title=request.title,
        capture_mode=request.capture_mode,
        asr_provider=request.asr_provider,
        diarization_provider=request.diarization_provider,
        external_processing_enabled=request.external_processing_enabled,
    )
    runtime_store.record_event(
        "conversation.started",
        "Conversation session started",
        detail={"session_id": session.id, "capture_mode": session.capture_mode},
    )
    return session


@app.get("/api/conversations", response_model=list[ConversationSessionRecord])
def conversations(limit: int = Query(default=100, ge=1, le=1000)) -> list[ConversationSessionRecord]:
    return runtime_store.recent_conversation_sessions(limit)


@app.get("/api/conversations/{session_id}", response_model=ConversationDetail)
def conversation_detail(session_id: str) -> ConversationDetail:
    session = runtime_store.conversation_session(session_id)
    if session is None:
        raise HTTPException(status_code=404, detail=f"conversation not found: {session_id}")
    return ConversationDetail(
        session=session,
        segments=runtime_store.conversation_segments(session_id),
        assist_cards=runtime_store.conversation_assist_cards(session_id),
    )


@app.post("/api/conversations/{session_id}/segments", response_model=ConversationSegmentRecord)
def add_conversation_segment(session_id: str, request: ConversationSegmentCreateRequest) -> ConversationSegmentRecord:
    if runtime_store.conversation_session(session_id) is None:
        raise HTTPException(status_code=404, detail=f"conversation not found: {session_id}")
    return runtime_store.add_conversation_segment(
        session_id=session_id,
        speaker_id=request.speaker_id,
        speaker_display_name=request.speaker_display_name,
        start_ms=request.start_ms,
        end_ms=request.end_ms,
        text=request.text,
        state=request.state,
        confidence=request.confidence,
    )


@app.post("/api/conversations/{session_id}/assist-cards", response_model=ConversationAssistCardRecord)
def add_conversation_assist_card(session_id: str, request: ConversationAssistCardCreateRequest) -> ConversationAssistCardRecord:
    if runtime_store.conversation_session(session_id) is None:
        raise HTTPException(status_code=404, detail=f"conversation not found: {session_id}")
    return runtime_store.add_conversation_assist_card(
        session_id=session_id,
        kind=request.kind,
        title=request.title,
        body=request.body,
        source_references=request.source_references,
        confidence=request.confidence,
    )


@app.post("/api/conversations/{session_id}/stop", response_model=ConversationSessionRecord)
def stop_conversation(session_id: str) -> ConversationSessionRecord:
    session = runtime_store.stop_conversation_session(session_id)
    if session is None:
        raise HTTPException(status_code=404, detail=f"conversation not found: {session_id}")
    runtime_store.record_event(
        "conversation.stopped",
        "Conversation session stopped",
        detail={"session_id": session.id},
    )
    return session
```

- [ ] **Step 6: Verify tests pass**

Run:

```bash
cd engine
uv run pytest tests/test_conversations.py -q
```

Expected: all conversation endpoint tests pass.

- [ ] **Step 7: Run full engine tests**

Run:

```bash
cd engine
uv run pytest
```

Expected: all engine tests pass.

- [ ] **Step 8: Commit**

```bash
git add engine/omnivoice_engine/schemas.py engine/omnivoice_engine/runtime_store.py engine/omnivoice_engine/main.py engine/tests/test_conversations.py
git commit -m "feat: add conversation engine api"
```

---

### Task 3: Swift EngineClient Conversation API

**Files:**
- Modify: `Sources/OmniVoiceCore/EngineClient.swift`
- Modify: `Tests/OmniVoiceCoreTests/EngineClientTests.swift`

- [ ] **Step 1: Write failing client tests**

Append to `Tests/OmniVoiceCoreTests/EngineClientTests.swift`:

```swift
func testConversationSessionDecodesEnginePayload() throws {
    let data = #"{"id":"s1","title":"Roadmap call","started_at":"2026-05-17T08:00:00Z","ended_at":null,"capture_mode":"microphone_only","asr_provider":"parakeet-tdt","diarization_provider":"mock","external_processing_enabled":false}"#.data(using: .utf8)!

    let session = try EngineCoding.decoder.decode(ConversationSession.self, from: data)

    XCTAssertEqual(session.id, "s1")
    XCTAssertEqual(session.captureMode, .microphoneOnly)
    XCTAssertTrue(session.isActive)
}

func testConversationDetailDecodesEnginePayload() throws {
    let data = """
    {
      "session": {
        "id": "s1",
        "title": "Roadmap call",
        "started_at": "2026-05-17T08:00:00Z",
        "ended_at": null,
        "capture_mode": "microphone_only",
        "asr_provider": "parakeet-tdt",
        "diarization_provider": "mock",
        "external_processing_enabled": false
      },
      "segments": [
        {
          "id": "seg1",
          "session_id": "s1",
          "speaker_id": "speaker-1",
          "speaker_display_name": "Speaker 1",
          "start_ms": 18130,
          "end_ms": 21900,
          "text": "How many users did we have last year?",
          "state": "settled",
          "confidence": 0.91
        }
      ],
      "assist_cards": [
        {
          "id": "card1",
          "session_id": "s1",
          "kind": "answer",
          "title": "Answer Found",
          "body": "Last year we had 18,420 active users.",
          "source_references": ["Obsidian/adoption-2025.md"],
          "confidence": 0.78,
          "status": "active",
          "created_at": "2026-05-17T08:00:10Z"
        }
      ]
    }
    """.data(using: .utf8)!

    let detail = try EngineCoding.decoder.decode(ConversationDetail.self, from: data)

    XCTAssertEqual(detail.session.id, "s1")
    XCTAssertEqual(detail.segments[0].speakerDisplayName, "Speaker 1")
    XCTAssertEqual(detail.assistCards[0].copyText, "Last year we had 18,420 active users.")
}
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
swift test --filter EngineClientTests
```

Expected: compile fails because `ConversationDetail` does not exist.

- [ ] **Step 3: Add request/detail structs**

Add to `Sources/OmniVoiceCore/ConversationModels.swift`:

```swift
public struct ConversationSessionCreateRequest: Codable, Equatable, Sendable {
    public let title: String
    public let captureMode: ConversationCaptureMode
    public let asrProvider: String
    public let diarizationProvider: String
    public let externalProcessingEnabled: Bool

    public init(
        title: String,
        captureMode: ConversationCaptureMode,
        asrProvider: String,
        diarizationProvider: String,
        externalProcessingEnabled: Bool = false
    ) {
        self.title = title
        self.captureMode = captureMode
        self.asrProvider = asrProvider
        self.diarizationProvider = diarizationProvider
        self.externalProcessingEnabled = externalProcessingEnabled
    }
}

public struct ConversationSegmentCreateRequest: Codable, Equatable, Sendable {
    public let speakerID: String
    public let speakerDisplayName: String
    public let startMs: Int
    public let endMs: Int?
    public let text: String
    public let state: ConversationSegmentState
    public let confidence: Double?

    public init(
        speakerID: String,
        speakerDisplayName: String,
        startMs: Int,
        endMs: Int? = nil,
        text: String,
        state: ConversationSegmentState,
        confidence: Double? = nil
    ) {
        self.speakerID = speakerID
        self.speakerDisplayName = speakerDisplayName
        self.startMs = startMs
        self.endMs = endMs
        self.text = text
        self.state = state
        self.confidence = confidence
    }
}

public struct ConversationAssistCardCreateRequest: Codable, Equatable, Sendable {
    public let kind: ConversationAssistCardKind
    public let title: String
    public let body: String
    public let sourceReferences: [String]
    public let confidence: Double?

    public init(
        kind: ConversationAssistCardKind,
        title: String,
        body: String,
        sourceReferences: [String] = [],
        confidence: Double? = nil
    ) {
        self.kind = kind
        self.title = title
        self.body = body
        self.sourceReferences = sourceReferences
        self.confidence = confidence
    }
}

public struct ConversationDetail: Codable, Equatable, Sendable {
    public let session: ConversationSession
    public let segments: [ConversationSegment]
    public let assistCards: [ConversationAssistCard]

    public init(
        session: ConversationSession,
        segments: [ConversationSegment] = [],
        assistCards: [ConversationAssistCard] = []
    ) {
        self.session = session
        self.segments = segments
        self.assistCards = assistCards
    }
}
```

- [ ] **Step 4: Add EngineClient methods**

Add to `Sources/OmniVoiceCore/EngineClient.swift`:

```swift
public func createConversation(_ request: ConversationSessionCreateRequest) async throws -> ConversationSession {
    let endpoint = baseURL.appending(path: "api").appending(path: "conversations")
    var urlRequest = URLRequest(url: endpoint)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.httpBody = try EngineCoding.encoder.encode(request)

    let (data, response) = try await urlSession.data(for: urlRequest)
    try validate(response, data: data)
    return try EngineCoding.decoder.decode(ConversationSession.self, from: data)
}

public func conversations(limit: Int = 100) async throws -> [ConversationSession] {
    var components = URLComponents(url: baseURL.appending(path: "api").appending(path: "conversations"), resolvingAgainstBaseURL: false)
    components?.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
    guard let endpoint = components?.url else { throw EngineError.invalidURL }

    let (data, response) = try await urlSession.data(from: endpoint)
    try validate(response, data: data)
    return try EngineCoding.decoder.decode([ConversationSession].self, from: data)
}

public func conversationDetail(sessionID: String) async throws -> ConversationDetail {
    let endpoint = baseURL.appending(path: "api").appending(path: "conversations").appending(path: sessionID)
    let (data, response) = try await urlSession.data(from: endpoint)
    try validate(response, data: data)
    return try EngineCoding.decoder.decode(ConversationDetail.self, from: data)
}

public func addConversationSegment(sessionID: String, request: ConversationSegmentCreateRequest) async throws -> ConversationSegment {
    let endpoint = baseURL.appending(path: "api").appending(path: "conversations").appending(path: sessionID).appending(path: "segments")
    var urlRequest = URLRequest(url: endpoint)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.httpBody = try EngineCoding.encoder.encode(request)

    let (data, response) = try await urlSession.data(for: urlRequest)
    try validate(response, data: data)
    return try EngineCoding.decoder.decode(ConversationSegment.self, from: data)
}

public func addConversationAssistCard(sessionID: String, request: ConversationAssistCardCreateRequest) async throws -> ConversationAssistCard {
    let endpoint = baseURL.appending(path: "api").appending(path: "conversations").appending(path: sessionID).appending(path: "assist-cards")
    var urlRequest = URLRequest(url: endpoint)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.httpBody = try EngineCoding.encoder.encode(request)

    let (data, response) = try await urlSession.data(for: urlRequest)
    try validate(response, data: data)
    return try EngineCoding.decoder.decode(ConversationAssistCard.self, from: data)
}

public func stopConversation(sessionID: String) async throws -> ConversationSession {
    let endpoint = baseURL.appending(path: "api").appending(path: "conversations").appending(path: sessionID).appending(path: "stop")
    var urlRequest = URLRequest(url: endpoint)
    urlRequest.httpMethod = "POST"

    let (data, response) = try await urlSession.data(for: urlRequest)
    try validate(response, data: data)
    return try EngineCoding.decoder.decode(ConversationSession.self, from: data)
}
```

- [ ] **Step 5: Verify Swift tests pass**

Run:

```bash
swift test --filter EngineClientTests
```

Expected: `EngineClientTests` passes.

- [ ] **Step 6: Commit**

```bash
git add Sources/OmniVoiceCore/ConversationModels.swift Sources/OmniVoiceCore/EngineClient.swift Tests/OmniVoiceCoreTests/EngineClientTests.swift
git commit -m "feat: add conversation engine client"
```

---

### Task 4: App Conversation State And Actions

**Files:**
- Modify: `Sources/OmniVoiceApp/AppModel.swift`
- Create: `Tests/OmniVoiceCoreTests/ConversationAssistCardTests.swift`

- [ ] **Step 1: Write copy/speak-independent assist tests**

Create `Tests/OmniVoiceCoreTests/ConversationAssistCardTests.swift`:

```swift
import XCTest
@testable import OmniVoiceCore

final class ConversationAssistCardTests: XCTestCase {
    func testPinnedStatusRoundTrips() throws {
        let card = ConversationAssistCard(
            id: "card-1",
            sessionID: "session-1",
            kind: .timeZone,
            title: "Time Zone Assist",
            body: "3:00 PM Pacific = 6:00 PM Eastern.",
            status: .pinned,
            createdAt: "2026-05-17T08:00:00Z"
        )

        let data = try EngineCoding.encoder.encode(card)
        let decoded = try EngineCoding.decoder.decode(ConversationAssistCard.self, from: data)

        XCTAssertEqual(decoded.status, .pinned)
        XCTAssertEqual(decoded.copyText, "3:00 PM Pacific = 6:00 PM Eastern.")
    }
}
```

- [ ] **Step 2: Run tests**

Run:

```bash
swift test --filter ConversationAssistCardTests
```

Expected: passes after Task 1 models exist.

- [ ] **Step 3: Add AppModel conversation state**

Modify `Sources/OmniVoiceApp/AppModel.swift`:

- add stored properties:

```swift
var activeConversation: ConversationSession?
var conversationSegments: [ConversationSegment]
var conversationAssistCards: [ConversationAssistCard]
var conversationSessions: [ConversationSession]
var isConversationRecording: Bool
```

- add initializer defaults and assignments:

```swift
conversationSegments: [ConversationSegment] = [],
conversationAssistCards: [ConversationAssistCard] = [],
conversationSessions: [ConversationSession] = [],
isConversationRecording: Bool = false
```

- add methods:

```swift
func loadConversations() async {
    do {
        conversationSessions = try await engineClient.conversations(limit: 100)
    } catch {
        statusText = "Conversation history unavailable"
    }
}

func createConversationSession(captureMode: ConversationCaptureMode = .microphoneOnly) async -> ConversationSession? {
    do {
        let session = try await engineClient.createConversation(
            ConversationSessionCreateRequest(
                title: "Conversation",
                captureMode: captureMode,
                asrProvider: preferences.asrProvider.rawValue,
                diarizationProvider: "mock",
                externalProcessingEnabled: false
            )
        )
        activeConversation = session
        conversationSegments = []
        conversationAssistCards = []
        isConversationRecording = true
        statusText = "Conversation recording"
        return session
    } catch {
        statusText = "Conversation start failed"
        return nil
    }
}

func appendConversationSegment(_ request: ConversationSegmentCreateRequest) async {
    guard let activeConversation else { return }
    do {
        let segment = try await engineClient.addConversationSegment(sessionID: activeConversation.id, request: request)
        conversationSegments.append(segment)
    } catch {
        statusText = "Conversation segment failed"
    }
}

func appendConversationAssistCard(_ request: ConversationAssistCardCreateRequest) async {
    guard let activeConversation else { return }
    do {
        let card = try await engineClient.addConversationAssistCard(sessionID: activeConversation.id, request: request)
        conversationAssistCards.append(card)
    } catch {
        statusText = "Assist card failed"
    }
}

func stopConversationSession() async {
    guard let activeConversation else { return }
    do {
        let stopped = try await engineClient.stopConversation(sessionID: activeConversation.id)
        self.activeConversation = stopped
        isConversationRecording = false
        await loadConversations()
        statusText = "Conversation saved"
    } catch {
        isConversationRecording = false
        statusText = "Conversation stop failed"
    }
}
```

- [ ] **Step 4: Verify Swift build**

Run:

```bash
swift test
```

Expected: all Swift tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/OmniVoiceApp/AppModel.swift Tests/OmniVoiceCoreTests/ConversationAssistCardTests.swift
git commit -m "feat: track conversation app state"
```

---

### Task 5: Conversation Recorder Service

**Files:**
- Create: `Sources/OmniVoiceApp/ConversationRecorderService.swift`
- Modify: `Sources/OmniVoiceApp/AppModel.swift`

- [ ] **Step 1: Create recorder service**

Create `Sources/OmniVoiceApp/ConversationRecorderService.swift`:

```swift
import Foundation
import OmniVoiceCore

@MainActor
final class ConversationRecorderService {
    enum RecorderError: LocalizedError {
        case alreadyRecording
        case noActiveSession

        var errorDescription: String? {
            switch self {
            case .alreadyRecording: "Conversation recording is already active"
            case .noActiveSession: "No conversation session is active"
            }
        }
    }

    private let audioCapture: AudioCaptureService
    private let streamingClient: EngineStreamingClient
    private var startedAt = Date()
    private var segmentIndex = 0
    private var isRecording = false
    private var activeSessionID: String?
    private var onSegment: ((ConversationSegmentCreateRequest) -> Void)?
    private var onAssistCard: ((ConversationAssistCardCreateRequest) -> Void)?
    private let speakerCycler = MockConversationDiarizer()

    init(
        audioCapture: AudioCaptureService = AudioCaptureService(),
        streamingClient: EngineStreamingClient = EngineStreamingClient()
    ) {
        self.audioCapture = audioCapture
        self.streamingClient = streamingClient
    }

    func start(
        sessionID: String,
        provider: ASRProviderKind,
        microphoneID: String?,
        onSegment: @escaping (ConversationSegmentCreateRequest) -> Void,
        onAssistCard: @escaping (ConversationAssistCardCreateRequest) -> Void
    ) throws {
        guard !isRecording else { throw RecorderError.alreadyRecording }
        activeSessionID = sessionID
        self.onSegment = onSegment
        self.onAssistCard = onAssistCard
        startedAt = Date()
        segmentIndex = 0
        isRecording = true

        let sampleRate = try audioCapture.start(deviceUID: microphoneID)
        streamingClient.setOnUpdate { [weak self] update in
            Task { @MainActor in
                self?.handle(update)
            }
        }
        audioCapture.onPCMChunk = { [weak streamingClient] data in
            streamingClient?.sendPCMFloat32(data)
        }
        streamingClient.connect(provider: provider, sampleRate: sampleRate)
    }

    func stop() throws {
        guard isRecording else { return }
        _ = try audioCapture.stopWAVData()
        streamingClient.finish()
        audioCapture.onPCMChunk = nil
        streamingClient.setOnUpdate(nil)
        activeSessionID = nil
        onSegment = nil
        onAssistCard = nil
        isRecording = false
    }

    func cancel() {
        streamingClient.cancel()
        audioCapture.onPCMChunk = nil
        streamingClient.setOnUpdate(nil)
        activeSessionID = nil
        onSegment = nil
        onAssistCard = nil
        isRecording = false
    }

    private func handle(_ update: TranscriptUpdate) {
        let text = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let nowMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        let speaker = speakerCycler.speaker(forSegmentIndex: segmentIndex, text: text)
        let request = ConversationSegmentCreateRequest(
            speakerID: speaker.id,
            speakerDisplayName: speaker.displayName,
            startMs: max(0, nowMs - 2500),
            endMs: update.isFinal ? nowMs : nil,
            text: text,
            state: update.isFinal ? .settled : .live,
            confidence: nil
        )
        onSegment?(request)

        if update.isFinal {
            segmentIndex += 1
            if let card = ConversationAssistCardDetector.card(for: text) {
                onAssistCard?(card)
            }
        }
    }
}

private struct MockConversationDiarizer {
    private let speakers = [
        (id: "speaker-1", displayName: "Speaker 1"),
        (id: "speaker-2", displayName: "Speaker 2"),
        (id: "speaker-3", displayName: "Speaker 3"),
    ]

    func speaker(forSegmentIndex index: Int, text: String) -> (id: String, displayName: String) {
        if text.lowercased().hasPrefix("i ") || text.lowercased().hasPrefix("i'm ") {
            return (id: "you", displayName: "You")
        }
        return speakers[index % speakers.count]
    }
}

private enum ConversationAssistCardDetector {
    static func card(for text: String) -> ConversationAssistCardCreateRequest? {
        let normalized = text.lowercased()
        if normalized.contains("how many") || normalized.contains("?") {
            return ConversationAssistCardCreateRequest(
                kind: .question,
                title: "Question Detected",
                body: text,
                sourceReferences: [],
                confidence: 0.6
            )
        }
        if normalized.contains("pst") || normalized.contains("pacific") {
            return ConversationAssistCardCreateRequest(
                kind: .timeZone,
                title: "Time Zone Assist",
                body: "3:00 PM Pacific = 6:00 PM Eastern = 11:00 PM London.",
                sourceReferences: [],
                confidence: 0.75
            )
        }
        return nil
    }
}
```

- [ ] **Step 2: Wire service into AppModel**

Modify `Sources/OmniVoiceApp/AppModel.swift`:

- add:

```swift
@ObservationIgnored private let conversationRecorder = ConversationRecorderService()
```

- add methods:

```swift
func startConversationRecording() async {
    guard let session = await createConversationSession(captureMode: .microphoneOnly) else {
        return
    }

    do {
        try conversationRecorder.start(
            sessionID: session.id,
            provider: preferences.asrProvider,
            microphoneID: preferences.microphoneID,
            onSegment: { [weak self] request in
                Task { @MainActor in
                    await self?.appendConversationSegment(request)
                }
            },
            onAssistCard: { [weak self] request in
                Task { @MainActor in
                    await self?.appendConversationAssistCard(request)
                }
            }
        )
        statusText = "Conversation recording"
    } catch {
        isConversationRecording = false
        statusText = error.localizedDescription
    }
}

func stopConversationRecording() async {
    do {
        try conversationRecorder.stop()
    } catch {
        statusText = error.localizedDescription
    }
    await stopConversationSession()
}

func cancelConversationRecording() {
    conversationRecorder.cancel()
    isConversationRecording = false
    statusText = "Conversation cancelled"
}
```

- [ ] **Step 3: Verify Swift build**

Run:

```bash
swift test
```

Expected: all Swift tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/OmniVoiceApp/ConversationRecorderService.swift Sources/OmniVoiceApp/AppModel.swift
git commit -m "feat: add conversation recorder service"
```

---

### Task 6: Conversation Mode Window UI

**Files:**
- Create: `Sources/OmniVoiceApp/ConversationModeView.swift`
- Modify: `Sources/OmniVoiceApp/OmniVoiceApp.swift`

- [ ] **Step 1: Create the SwiftUI view**

Create `Sources/OmniVoiceApp/ConversationModeView.swift`:

```swift
import AppKit
import SwiftUI
import OmniVoiceCore

struct ConversationModeView: View {
    @Bindable var model: AppModel

    private var theme: OmniVoiceTheme { model.activeTheme }

    var body: some View {
        HStack(spacing: 14) {
            transcriptPanel
                .frame(minWidth: 520)

            assistRail
                .frame(width: 330)
        }
        .padding(16)
        .frame(minWidth: 920, minHeight: 620)
        .background(Color.black.opacity(0.88))
        .preferredColorScheme(model.preferences.appearanceMode.colorScheme)
        .task {
            await model.loadConversations()
        }
    }

    private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if model.conversationSegments.isEmpty {
                        emptyTranscript
                    } else {
                        ForEach(model.conversationSegments) { segment in
                            ConversationSegmentRow(segment: segment, theme: theme)
                        }
                    }
                }
                .padding(14)
            }
            .scrollIndicators(.hidden)
            .themeSurface(theme, cornerRadius: 16, strong: false)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Conversation")
                    .font(.title2.weight(.bold))
                Text("Microphone · \(model.conversationSegments.count) segments")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(model.isConversationRecording ? "REC" : "Ready")
                .font(.caption.weight(.bold))
                .foregroundStyle(model.isConversationRecording ? .yellow : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().stroke(model.isConversationRecording ? Color.yellow.opacity(0.5) : Color.secondary.opacity(0.25)))

            if model.isConversationRecording {
                Button("Stop") {
                    Task { await model.stopConversationRecording() }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Start") {
                    Task { await model.startConversationRecording() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var emptyTranscript: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "captions.bubble")
                .font(.title)
                .foregroundStyle(Color(themeColor: theme.accentColor))
            Text("Start a conversation recording")
                .font(.headline)
            Text("Live paragraph captions will appear here with speaker bars and timestamps.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
    }

    private var assistRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Assist")
                        .font(.headline)
                    Text("Copy · Speak · Sources")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if model.conversationAssistCards.isEmpty {
                        emptyAssist
                    } else {
                        ForEach(model.conversationAssistCards) { card in
                            ConversationAssistCardView(card: card, theme: theme)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(12)
        .themeSurface(theme, cornerRadius: 16, strong: true)
    }

    private var emptyAssist: some View {
        Text("Questions, answer cards, time zone conversions, and follow-up suggestions will appear here.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
    }
}

private struct ConversationSegmentRow: View {
    let segment: ConversationSegment
    let theme: OmniVoiceTheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 99)
                .fill(color(for: segment.speakerID))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 5) {
                Text("\(segment.speakerDisplayName) · \(segment.timestampLabel)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color(for: segment.speakerID))
                Text(segment.text)
                    .font(.system(size: 17))
                    .lineSpacing(3)
                    .foregroundStyle(segment.state == .live ? .secondary : .primary)
            }
        }
    }

    private func color(for speakerID: String) -> Color {
        switch speakerID {
        case "you": Color(themeColor: theme.accentColor)
        case "speaker-1": .yellow
        case "speaker-2": .purple
        default: .teal
        }
    }
}

private struct ConversationAssistCardView: View {
    let card: ConversationAssistCard
    let theme: OmniVoiceTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(card.title)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(themeColor: theme.accentColor))
                .textCase(.uppercase)
            Text(card.body)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            if !card.sourceReferences.isEmpty {
                Text(card.sourceReferences.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 7) {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(card.copyText, forType: .string)
                }
                Button("Speak") {
                    NSSpeechSynthesizer().startSpeaking(card.copyText)
                }
                Button("Sources") {}
                    .disabled(card.sourceReferences.isEmpty)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .themeSurface(theme, cornerRadius: 12, strong: false)
    }
}
```

- [ ] **Step 2: Add window scene**

Modify `Sources/OmniVoiceApp/OmniVoiceApp.swift`:

- add:

```swift
Window("Conversation", id: "conversation-mode") {
    ConversationModeView(model: model)
        .task {
            appDelegate.attach(model: model)
            await model.refreshEngineStatus()
        }
}
.defaultSize(width: 980, height: 680)
```

- [ ] **Step 3: Verify Swift build**

Run:

```bash
swift test
```

Expected: all Swift tests pass and the new window scene compiles.

- [ ] **Step 4: Commit**

```bash
git add Sources/OmniVoiceApp/ConversationModeView.swift Sources/OmniVoiceApp/OmniVoiceApp.swift
git commit -m "feat: add conversation mode window"
```

---

### Task 7: Open Conversation Mode From Menu And Settings

**Files:**
- Modify: `Sources/OmniVoiceApp/MenuBarControlsView.swift`
- Modify: `Sources/OmniVoiceApp/SettingsView.swift`
- Modify: `Sources/OmniVoiceApp/OmniVoiceApp.swift`

- [ ] **Step 1: Add open-window callbacks**

Modify `Sources/OmniVoiceApp/MenuBarControlsView.swift`:

- add stored property:

```swift
let openConversationMode: () -> Void
```

- add button above `Open Engine Dashboard`:

```swift
Button("Open Conversation Mode") {
    openConversationMode()
}
```

Modify `Sources/OmniVoiceApp/SettingsView.swift`:

- add stored property:

```swift
let openConversationMode: () -> Void
```

- add a button in the Overview or Help/Capabilities area:

```swift
Button {
    openConversationMode()
} label: {
    Label("Open Conversation Mode", systemImage: "bubble.left.and.text.bubble.right")
}
```

- [ ] **Step 2: Wire callbacks in the app scene**

Modify `Sources/OmniVoiceApp/OmniVoiceApp.swift`:

- add:

```swift
@Environment(\.openWindow) private var openWindow
```

- pass callbacks:

```swift
openConversationMode: {
    openWindow(id: "conversation-mode")
}
```

- [ ] **Step 3: Verify Swift build**

Run:

```bash
swift test
```

Expected: all Swift tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/OmniVoiceApp/MenuBarControlsView.swift Sources/OmniVoiceApp/SettingsView.swift Sources/OmniVoiceApp/OmniVoiceApp.swift
git commit -m "feat: expose conversation mode entry points"
```

---

### Task 8: Conversation Review And Export Basics

**Files:**
- Modify: `engine/omnivoice_engine/main.py`
- Modify: `engine/tests/test_conversations.py`
- Modify: `Sources/OmniVoiceApp/ConversationModeView.swift`

- [ ] **Step 1: Add export endpoint test**

Append to `engine/tests/test_conversations.py`:

```python
def test_conversation_export_returns_text(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)
    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    session = client.post(
        "/api/conversations",
        json={
            "title": "Roadmap call",
            "capture_mode": "microphone_only",
            "asr_provider": "parakeet-tdt",
            "diarization_provider": "mock",
            "external_processing_enabled": False,
        },
    ).json()
    client.post(
        f"/api/conversations/{session['id']}/segments",
        json={
            "speaker_id": "speaker-1",
            "speaker_display_name": "Speaker 1",
            "start_ms": 18130,
            "end_ms": 21900,
            "text": "How many users did we have last year?",
            "state": "settled",
            "confidence": 0.91,
        },
    )

    response = client.get(f"/api/conversations/{session['id']}/export")

    assert response.status_code == 200
    assert "Speaker 1 [00:18]" in response.text
    assert "How many users did we have last year?" in response.text
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
cd engine
uv run pytest tests/test_conversations.py::test_conversation_export_returns_text -q
```

Expected: fails with `404 Not Found`.

- [ ] **Step 3: Add export route**

Modify `engine/omnivoice_engine/main.py`:

```python
@app.get("/api/conversations/{session_id}/export")
def export_conversation(session_id: str) -> Response:
    session = runtime_store.conversation_session(session_id)
    if session is None:
        raise HTTPException(status_code=404, detail=f"conversation not found: {session_id}")
    lines = [f"# {session.title}", ""]
    for segment in runtime_store.conversation_segments(session_id):
        seconds = max(0, segment.start_ms // 1000)
        timestamp = f"{seconds // 60:02d}:{seconds % 60:02d}"
        lines.append(f"{segment.speaker_display_name} [{timestamp}]: {segment.text}")
    return Response(
        content="\n".join(lines).strip() + "\n",
        media_type="text/plain",
        headers={"Content-Disposition": f'attachment; filename="conversation-{session_id}.txt"'},
    )
```

- [ ] **Step 4: Add copy full transcript in UI**

Modify `Sources/OmniVoiceApp/ConversationModeView.swift` header button area:

```swift
Button("Copy Transcript") {
    let text = model.conversationSegments
        .map { "\($0.speakerDisplayName) [\($0.timestampLabel)]: \($0.text)" }
        .joined(separator: "\n")
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
.disabled(model.conversationSegments.isEmpty)
```

- [ ] **Step 5: Verify**

Run:

```bash
cd engine
uv run pytest tests/test_conversations.py -q
cd ..
swift test
```

Expected: engine conversation tests and Swift tests pass.

- [ ] **Step 6: Commit**

```bash
git add engine/omnivoice_engine/main.py engine/tests/test_conversations.py Sources/OmniVoiceApp/ConversationModeView.swift
git commit -m "feat: add conversation transcript export"
```

---

### Task 9: Docs And Feature Map

**Files:**
- Modify: `docs/OMNIVOICE_QUICK_REFERENCE.md`
- Modify: `docs/V2_FEATURE_GUI_MAP.md`
- Modify: `docs/superpowers/specs/2026-05-17-conversation-mode-design.md`

- [ ] **Step 1: Update quick reference**

Add to `docs/OMNIVOICE_QUICK_REFERENCE.md`:

```markdown
## Conversation Mode

Open Conversation Mode from the menu bar or Settings. Press Start to begin a microphone-only live meeting capture.

The live view shows paragraph-style captions with speaker bars and timestamps. The MVP uses mock/pluggable speaker labels until a real local diarization provider is installed.

The assist rail may show question, time zone, or follow-up cards. Cards never post into Teams, Zoom, Slack, or chat. Use Copy to place text on the clipboard or Speak to read it locally.
```

- [ ] **Step 2: Update feature map**

Update `docs/V2_FEATURE_GUI_MAP.md` conversation rows to mark:

- Conversation Mode window: implemented MVP
- Microphone-only recording: implemented MVP
- System/app audio: planned
- Real diarization provider: planned
- Assist rail Copy/Speak/Sources: implemented MVP
- Posting to meeting chat: out of scope

- [ ] **Step 3: Update spec status note**

Append to `docs/superpowers/specs/2026-05-17-conversation-mode-design.md`:

```markdown
## Implementation Status

The first implementation slice covers microphone-only live recording, paragraph-style captions, local persistence, mock/pluggable speaker labeling, and Copy/Speak assist cards. System/app audio capture, real local diarization, Obsidian/MCP retrieval, speaker rename/merge, and source-backed answer cards remain follow-up slices.
```

- [ ] **Step 4: Verify markdown whitespace**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add docs/OMNIVOICE_QUICK_REFERENCE.md docs/V2_FEATURE_GUI_MAP.md docs/superpowers/specs/2026-05-17-conversation-mode-design.md
git commit -m "docs: document conversation mode mvp"
```

---

### Task 10: Full Verification

**Files:**
- No source edits expected.

- [ ] **Step 1: Run Swift tests**

```bash
swift test
```

Expected: all Swift tests pass.

- [ ] **Step 2: Run engine tests**

```bash
cd engine
uv run pytest
```

Expected: all engine tests pass.

- [ ] **Step 3: Check diff whitespace**

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 4: Build app bundle**

```bash
script/build_and_run.sh --verify
```

Expected: build succeeds. If macOS emits the existing non-blocking `SecKeychainGetPath` warning while replacing the local signature, note it in the final status but do not treat it as a failure.

- [ ] **Step 5: Manual smoke test**

Run the app and verify:

1. Open Conversation Mode from menu bar.
2. Press Start.
3. Speak a sentence.
4. Confirm paragraph transcript appears.
5. Speak a question.
6. Confirm a Question Detected card appears.
7. Click Copy on an assist card and paste into a text editor.
8. Click Speak and confirm local TTS plays.
9. Press Stop.
10. Confirm conversation remains in post-call view.

If microphone permissions prevent recording, verify the UI enters a clear failure state and still compiles/tests.

---

## Follow-Up Slices

These should be separate plans after the MVP is stable:

1. System/app audio capture and source-separated meeting mode.
2. Real local diarization provider integration, likely Sortformer-compatible.
3. Speaker rename, merge, split, and identity confidence UI.
4. Obsidian/MCP retrieval-backed answer cards.
5. Source viewer and source citation previews.
6. Post-call summary and action item generation.
7. Optional external AI processing flags per conversation session.
