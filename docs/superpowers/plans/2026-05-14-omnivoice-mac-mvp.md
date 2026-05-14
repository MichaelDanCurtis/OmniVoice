# OmniVoice Mac MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS push-to-talk dictation MVP that shows live captions while recording, cleans the final utterance locally, and inserts the result into the focused app.

**Architecture:** The macOS app is Swift/SwiftUI with small testable core modules for session state, preferences, overlay state, audio capture, and text insertion. Local AI runs in a Python sidecar engine reached over `127.0.0.1`, so Parakeet TDT, Canary-Qwen-2.5B, and future Windows support can share the same provider contract. The first working path uses a fake ASR provider for app plumbing, then adds Parakeet TDT through sherpa-onnx as the real local provider.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI, AppKit, AVFoundation, Carbon global hotkeys, XCTest, Python 3.12, FastAPI, Pydantic, pytest, sherpa-onnx.

---

## Scope Check

The approved spec covers several subsystems. This plan builds the first macOS MVP vertical slice:

- menu bar app
- configurable push-to-talk state
- style switching
- live caption overlay fed by streaming engine updates
- audio capture boundary
- local engine contract
- deterministic cleanup baseline
- Parakeet TDT provider slot
- focused-app insertion

Windows client work, installer signing, billing, account sync, team dictionaries, and meeting transcription are outside this plan.

## File Structure

Create this structure from the empty workspace:

```text
Package.swift
Sources/
  OmniVoiceApp/
    OmniVoiceApp.swift
    AppDelegate.swift
    AppModel.swift
    CaptionOverlayWindow.swift
    CaptionOverlayView.swift
    HotkeyController.swift
    AudioCaptureService.swift
    TextInsertionService.swift
  OmniVoiceCore/
    Models.swift
    DictationSession.swift
    EngineClient.swift
    EngineStreamingClient.swift
    PreferencesStore.swift
Tests/
  OmniVoiceCoreTests/
    ModelsTests.swift
    DictationSessionTests.swift
    EngineClientTests.swift
    PreferencesStoreTests.swift
engine/
  pyproject.toml
  omnivoice_engine/
    __init__.py
    main.py
    schemas.py
    cleanup.py
    providers/
      __init__.py
      base.py
      fake.py
      parakeet_sherpa.py
      registry.py
  tests/
    test_cleanup.py
    test_api.py
    test_registry.py
scripts/
  run-engine.sh
  download-parakeet-tdt.sh
```

Responsibility boundaries:

- `OmniVoiceCore` contains pure Swift types and state machines with no AppKit dependency.
- `OmniVoiceApp` owns macOS permissions, UI, hotkeys, audio capture, overlay windows, and insertion.
- `engine/omnivoice_engine` owns local ASR and cleanup.
- `scripts/` contains repeatable developer commands for model download and engine startup.

---

## Task 1: Initialize Repo And Workspaces

**Files:**
- Create: `Package.swift`
- Create: `Sources/OmniVoiceApp/OmniVoiceApp.swift`
- Create: `Sources/OmniVoiceCore/Models.swift`
- Create: `Tests/OmniVoiceCoreTests/ModelsTests.swift`
- Create: `engine/pyproject.toml`
- Create: `engine/omnivoice_engine/__init__.py`
- Create: `engine/tests/test_smoke.py`

- [ ] **Step 1: Initialize git**

Run:

```bash
git init
```

Expected:

```text
Initialized empty Git repository
```

- [ ] **Step 2: Create Swift package manifest**

Write `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OmniVoice",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "OmniVoiceApp", targets: ["OmniVoiceApp"]),
        .library(name: "OmniVoiceCore", targets: ["OmniVoiceCore"])
    ],
    targets: [
        .target(name: "OmniVoiceCore"),
        .executableTarget(
            name: "OmniVoiceApp",
            dependencies: ["OmniVoiceCore"]
        ),
        .testTarget(
            name: "OmniVoiceCoreTests",
            dependencies: ["OmniVoiceCore"]
        )
    ]
)
```

- [ ] **Step 3: Create minimal Swift core model**

Write `Sources/OmniVoiceCore/Models.swift`:

```swift
import Foundation

public enum StyleProfile: String, CaseIterable, Codable, Equatable, Sendable {
    case neutral = "neutral"
    case professional = "professional"
    case concise = "concise"
    case expanded = "expanded"
    case raw = "raw"

    public var displayName: String {
        switch self {
        case .neutral: "Neutral"
        case .professional: "Professional"
        case .concise: "Concise"
        case .expanded: "Expanded"
        case .raw: "Raw Dictation"
        }
    }

    public func next() -> StyleProfile {
        let values = Self.allCases
        let index = values.firstIndex(of: self) ?? 0
        return values[(index + 1) % values.count]
    }
}
```

- [ ] **Step 4: Create minimal Swift app entry**

Write `Sources/OmniVoiceApp/OmniVoiceApp.swift`:

```swift
import SwiftUI
import OmniVoiceCore

@main
struct OmniVoiceApp: App {
    var body: some Scene {
        MenuBarExtra("OmniVoice", systemImage: "waveform") {
            Text("Style: \(StyleProfile.neutral.displayName)")
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
```

- [ ] **Step 5: Add first Swift test**

Write `Tests/OmniVoiceCoreTests/ModelsTests.swift`:

```swift
import XCTest
@testable import OmniVoiceCore

final class ModelsTests: XCTestCase {
    func testStyleProfilesCycleInExpectedOrder() {
        XCTAssertEqual(StyleProfile.neutral.next(), .professional)
        XCTAssertEqual(StyleProfile.professional.next(), .concise)
        XCTAssertEqual(StyleProfile.concise.next(), .expanded)
        XCTAssertEqual(StyleProfile.expanded.next(), .raw)
        XCTAssertEqual(StyleProfile.raw.next(), .neutral)
    }
}
```

- [ ] **Step 6: Create Python engine package metadata**

Write `engine/pyproject.toml`:

```toml
[project]
name = "omnivoice-engine"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = [
  "fastapi>=0.115.0",
  "uvicorn[standard]>=0.30.0",
  "pydantic>=2.8.0"
]

[project.optional-dependencies]
dev = [
  "pytest>=8.2.0",
  "httpx>=0.27.0"
]
asr = [
  "sherpa-onnx>=1.10.0",
  "soundfile>=0.12.1",
  "numpy>=1.26.0"
]

[tool.pytest.ini_options]
testpaths = ["tests"]
pythonpath = ["."]
```

- [ ] **Step 7: Add Python smoke test**

Write `engine/omnivoice_engine/__init__.py`:

```python
__all__ = ["__version__"]
__version__ = "0.1.0"
```

Write `engine/tests/test_smoke.py`:

```python
from omnivoice_engine import __version__


def test_engine_version_is_defined():
    assert __version__ == "0.1.0"
```

- [ ] **Step 8: Run initial verification**

Run:

```bash
swift test
cd engine && python3.12 -m venv .venv && . .venv/bin/activate && pip install -e ".[dev]" && pytest
```

Expected:

```text
Test Suite 'All tests' passed
1 passed
```

- [ ] **Step 9: Commit**

Run:

```bash
git add Package.swift Sources Tests engine
git commit -m "chore: scaffold OmniVoice workspaces"
```

Expected:

```text
[main ...] chore: scaffold OmniVoice workspaces
```

---

## Task 2: Core Dictation State Machine

**Files:**
- Modify: `Sources/OmniVoiceCore/Models.swift`
- Create: `Sources/OmniVoiceCore/DictationSession.swift`
- Create: `Tests/OmniVoiceCoreTests/DictationSessionTests.swift`

- [ ] **Step 1: Add transcript and provider models**

Append to `Sources/OmniVoiceCore/Models.swift`:

```swift
public enum ASRProviderKind: String, CaseIterable, Codable, Equatable, Sendable {
    case fake = "fake"
    case parakeetTDT = "parakeet-tdt"
    case canaryQwen25B = "canary-qwen-2.5b"
}

public struct TranscriptUpdate: Codable, Equatable, Sendable {
    public let text: String
    public let isFinal: Bool

    public init(text: String, isFinal: Bool) {
        self.text = text
        self.isFinal = isFinal
    }
}

public struct CleanupRequest: Codable, Equatable, Sendable {
    public let rawTranscript: String
    public let style: StyleProfile
    public let dictionaryTerms: [String]

    public init(rawTranscript: String, style: StyleProfile, dictionaryTerms: [String] = []) {
        self.rawTranscript = rawTranscript
        self.style = style
        self.dictionaryTerms = dictionaryTerms
    }
}

public struct CleanupResult: Codable, Equatable, Sendable {
    public let text: String
    public let cleanupApplied: Bool

    public init(text: String, cleanupApplied: Bool) {
        self.text = text
        self.cleanupApplied = cleanupApplied
    }
}
```

- [ ] **Step 2: Write failing state-machine tests**

Write `Tests/OmniVoiceCoreTests/DictationSessionTests.swift`:

```swift
import XCTest
@testable import OmniVoiceCore

final class DictationSessionTests: XCTestCase {
    func testPressHotkeyMovesFromIdleToListening() {
        var session = DictationSession()

        session.pressHotkey()

        XCTAssertEqual(session.state, .listening)
        XCTAssertEqual(session.partialTranscript, "")
    }

    func testPartialTranscriptUpdatesOnlyWhileListening() {
        var session = DictationSession()

        session.receivePartial("ignored")
        XCTAssertEqual(session.partialTranscript, "")

        session.pressHotkey()
        session.receivePartial("hello there")

        XCTAssertEqual(session.partialTranscript, "hello there")
    }

    func testReleaseMovesToCleaningWithFinalTranscript() {
        var session = DictationSession()
        session.pressHotkey()
        session.receivePartial("going to the store")

        session.releaseHotkey(finalTranscript: "going to the house")

        XCTAssertEqual(session.state, .cleaning)
        XCTAssertEqual(session.finalTranscript, "going to the house")
    }

    func testCleanupResultMovesToInserting() {
        var session = DictationSession()
        session.pressHotkey()
        session.releaseHotkey(finalTranscript: "raw")

        session.finishCleanup("Cleaned.")

        XCTAssertEqual(session.state, .inserting)
        XCTAssertEqual(session.finalTextToInsert, "Cleaned.")
    }

    func testResetReturnsToIdle() {
        var session = DictationSession()
        session.pressHotkey()
        session.releaseHotkey(finalTranscript: "raw")
        session.finishCleanup("Cleaned.")

        session.reset()

        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.partialTranscript, "")
        XCTAssertEqual(session.finalTranscript, "")
        XCTAssertEqual(session.finalTextToInsert, "")
    }
}
```

- [ ] **Step 3: Run tests to verify failure**

Run:

```bash
swift test --filter DictationSessionTests
```

Expected:

```text
error: cannot find 'DictationSession' in scope
```

- [ ] **Step 4: Implement state machine**

Write `Sources/OmniVoiceCore/DictationSession.swift`:

```swift
import Foundation

public struct DictationSession: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case listening
        case cleaning
        case inserting
        case failed(String)
    }

    public private(set) var state: State
    public private(set) var partialTranscript: String
    public private(set) var finalTranscript: String
    public private(set) var finalTextToInsert: String

    public init(
        state: State = .idle,
        partialTranscript: String = "",
        finalTranscript: String = "",
        finalTextToInsert: String = ""
    ) {
        self.state = state
        self.partialTranscript = partialTranscript
        self.finalTranscript = finalTranscript
        self.finalTextToInsert = finalTextToInsert
    }

    public mutating func pressHotkey() {
        state = .listening
        partialTranscript = ""
        finalTranscript = ""
        finalTextToInsert = ""
    }

    public mutating func receivePartial(_ text: String) {
        guard state == .listening else { return }
        partialTranscript = text
    }

    public mutating func releaseHotkey(finalTranscript: String) {
        guard state == .listening else { return }
        self.finalTranscript = finalTranscript
        state = .cleaning
    }

    public mutating func finishCleanup(_ text: String) {
        guard state == .cleaning else { return }
        finalTextToInsert = text
        state = .inserting
    }

    public mutating func fail(_ message: String) {
        state = .failed(message)
    }

    public mutating func reset() {
        state = .idle
        partialTranscript = ""
        finalTranscript = ""
        finalTextToInsert = ""
    }
}
```

- [ ] **Step 5: Verify tests pass**

Run:

```bash
swift test --filter DictationSessionTests
```

Expected:

```text
Test Suite 'DictationSessionTests' passed
```

- [ ] **Step 6: Commit**

Run:

```bash
git add Sources/OmniVoiceCore Tests/OmniVoiceCoreTests
git commit -m "feat: add dictation session state machine"
```

Expected:

```text
[main ...] feat: add dictation session state machine
```

---

## Task 3: Python Cleanup Baseline

**Files:**
- Create: `engine/omnivoice_engine/schemas.py`
- Create: `engine/omnivoice_engine/cleanup.py`
- Create: `engine/omnivoice_engine/main.py`
- Create: `engine/tests/test_cleanup.py`
- Create: `engine/tests/test_api.py`

- [ ] **Step 1: Write cleanup behavior tests**

Write `engine/tests/test_cleanup.py`:

```python
from omnivoice_engine.cleanup import clean_transcript
from omnivoice_engine.schemas import CleanupRequest


def clean(raw: str, style: str = "neutral") -> str:
    return clean_transcript(CleanupRequest(raw_transcript=raw, style=style)).text


def test_no_wait_replaces_abandoned_clause():
    assert clean("I'm going to go to the store. No wait, I'm going to go to the house.") == "I'm going to go to the house."


def test_actually_replaces_date():
    assert clean("Schedule it for Monday, actually Tuesday.") == "Schedule it for Tuesday."


def test_scratch_that_keeps_following_sentence():
    assert clean("Send the invoice to Mark. Scratch that, send it to Sara.") == "Send it to Sara."


def test_concise_removes_leading_filler():
    assert clean("um I just wanted to say that we should ship this today", "concise") == "We should ship this today."


def test_raw_style_only_trims_spacing():
    assert clean("  um I mean keep these words  ", "raw") == "um I mean keep these words"
```

- [ ] **Step 2: Write API behavior tests**

Write `engine/tests/test_api.py`:

```python
from fastapi.testclient import TestClient
from omnivoice_engine.main import app


client = TestClient(app)


def test_health_endpoint():
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_cleanup_endpoint():
    response = client.post(
        "/cleanup",
        json={
            "raw_transcript": "Schedule it for Monday, actually Tuesday.",
            "style": "neutral",
            "dictionary_terms": [],
        },
    )

    assert response.status_code == 200
    assert response.json() == {
        "text": "Schedule it for Tuesday.",
        "cleanup_applied": True,
    }
```

- [ ] **Step 3: Run tests to verify failure**

Run:

```bash
cd engine && . .venv/bin/activate && pytest tests/test_cleanup.py tests/test_api.py
```

Expected:

```text
ModuleNotFoundError: No module named 'omnivoice_engine.cleanup'
```

- [ ] **Step 4: Add schemas**

Write `engine/omnivoice_engine/schemas.py`:

```python
from pydantic import BaseModel, Field


class CleanupRequest(BaseModel):
    raw_transcript: str = Field(min_length=0)
    style: str = "neutral"
    dictionary_terms: list[str] = Field(default_factory=list)


class CleanupResponse(BaseModel):
    text: str
    cleanup_applied: bool


class ProviderInfo(BaseModel):
    id: str
    label: str
    available: bool
    reason: str | None = None


class TranscribeResponse(BaseModel):
    text: str
    provider: str
```

- [ ] **Step 5: Implement deterministic cleanup baseline**

Write `engine/omnivoice_engine/cleanup.py`:

```python
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
    text = _remove_leading_fillers(text)
    text = _normalize_capitalization(text)
    text = _ensure_terminal_punctuation(text)
    return CleanupResponse(text=text, cleanup_applied=True)


def _apply_clause_corrections(text: str) -> str:
    lower = text.lower()
    last_match_end: int | None = None
    for pattern in CORRECTION_PATTERNS:
        matches = list(re.finditer(pattern, lower, re.IGNORECASE))
        if matches:
            last_match_end = matches[-1].end()
    if last_match_end is None:
        return text
    return text[last_match_end:].strip(" ,.")


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
    if not text:
        return text
    if text[-1] in ".!?":
        return text
    return text + "."
```

- [ ] **Step 6: Add FastAPI app**

Write `engine/omnivoice_engine/main.py`:

```python
from fastapi import FastAPI

from .cleanup import clean_transcript
from .schemas import CleanupRequest, CleanupResponse

app = FastAPI(title="OmniVoice Local Engine")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/cleanup", response_model=CleanupResponse)
def cleanup(request: CleanupRequest) -> CleanupResponse:
    return clean_transcript(request)
```

- [ ] **Step 7: Verify cleanup and API tests pass**

Run:

```bash
cd engine && . .venv/bin/activate && pytest tests/test_cleanup.py tests/test_api.py
```

Expected:

```text
7 passed
```

- [ ] **Step 8: Commit**

Run:

```bash
git add engine/omnivoice_engine engine/tests
git commit -m "feat: add local cleanup engine baseline"
```

Expected:

```text
[main ...] feat: add local cleanup engine baseline
```

---

## Task 4: Engine Provider Registry And Fake ASR

**Files:**
- Create: `engine/omnivoice_engine/providers/__init__.py`
- Create: `engine/omnivoice_engine/providers/base.py`
- Create: `engine/omnivoice_engine/providers/fake.py`
- Create: `engine/omnivoice_engine/providers/registry.py`
- Modify: `engine/omnivoice_engine/main.py`
- Create: `engine/tests/test_registry.py`
- Modify: `engine/tests/test_api.py`

- [ ] **Step 1: Write provider tests**

Write `engine/tests/test_registry.py`:

```python
from omnivoice_engine.providers.registry import ProviderRegistry


def test_fake_provider_is_available():
    registry = ProviderRegistry()

    providers = registry.list_providers()

    fake = next(provider for provider in providers if provider.id == "fake")
    assert fake.available is True
    assert fake.reason is None


def test_fake_provider_transcribes_bytes():
    registry = ProviderRegistry()
    provider = registry.get("fake")

    result = provider.transcribe(b"hello world")

    assert result == "fake transcript"
```

Append to `engine/tests/test_api.py`:

```python

def test_providers_endpoint_includes_fake():
    response = client.get("/providers")

    assert response.status_code == 200
    assert {"id": "fake", "label": "Fake ASR", "available": True, "reason": None} in response.json()


def test_transcribe_endpoint_uses_fake_provider():
    response = client.post("/transcribe?provider=fake", content=b"audio-bytes")

    assert response.status_code == 200
    assert response.json() == {"text": "fake transcript", "provider": "fake"}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
cd engine && . .venv/bin/activate && pytest tests/test_registry.py tests/test_api.py
```

Expected:

```text
ModuleNotFoundError: No module named 'omnivoice_engine.providers'
```

- [ ] **Step 3: Add provider base types**

Write `engine/omnivoice_engine/providers/__init__.py`:

```python
from .registry import ProviderRegistry

__all__ = ["ProviderRegistry"]
```

Write `engine/omnivoice_engine/providers/base.py`:

```python
from __future__ import annotations

from abc import ABC, abstractmethod

from omnivoice_engine.schemas import ProviderInfo


class ASRProvider(ABC):
    id: str
    label: str

    @abstractmethod
    def info(self) -> ProviderInfo:
        raise NotImplementedError

    @abstractmethod
    def transcribe(self, audio_bytes: bytes) -> str:
        raise NotImplementedError
```

- [ ] **Step 4: Add fake provider and registry**

Write `engine/omnivoice_engine/providers/fake.py`:

```python
from omnivoice_engine.schemas import ProviderInfo

from .base import ASRProvider


class FakeASRProvider(ASRProvider):
    id = "fake"
    label = "Fake ASR"

    def info(self) -> ProviderInfo:
        return ProviderInfo(id=self.id, label=self.label, available=True)

    def transcribe(self, audio_bytes: bytes) -> str:
        return "fake transcript"
```

Write `engine/omnivoice_engine/providers/registry.py`:

```python
from __future__ import annotations

from omnivoice_engine.schemas import ProviderInfo

from .base import ASRProvider
from .fake import FakeASRProvider


class ProviderRegistry:
    def __init__(self) -> None:
        self._providers: dict[str, ASRProvider] = {
            "fake": FakeASRProvider(),
        }

    def list_providers(self) -> list[ProviderInfo]:
        return [provider.info() for provider in self._providers.values()]

    def get(self, provider_id: str) -> ASRProvider:
        if provider_id not in self._providers:
            raise KeyError(provider_id)
        return self._providers[provider_id]
```

- [ ] **Step 5: Add provider endpoints**

Replace `engine/omnivoice_engine/main.py` with:

```python
from fastapi import FastAPI, HTTPException, Query, Request

from .cleanup import clean_transcript
from .providers.registry import ProviderRegistry
from .schemas import CleanupRequest, CleanupResponse, ProviderInfo, TranscribeResponse

app = FastAPI(title="OmniVoice Local Engine")
registry = ProviderRegistry()


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/providers", response_model=list[ProviderInfo])
def providers() -> list[ProviderInfo]:
    return registry.list_providers()


@app.post("/cleanup", response_model=CleanupResponse)
def cleanup(request: CleanupRequest) -> CleanupResponse:
    return clean_transcript(request)


@app.post("/transcribe", response_model=TranscribeResponse)
async def transcribe(request: Request, provider: str = Query(default="fake")) -> TranscribeResponse:
    try:
        asr = registry.get(provider)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"unknown provider: {provider}") from exc

    info = asr.info()
    if not info.available:
        raise HTTPException(status_code=503, detail=info.reason or f"provider unavailable: {provider}")

    audio_bytes = await request.body()
    return TranscribeResponse(text=asr.transcribe(audio_bytes), provider=provider)
```

- [ ] **Step 6: Verify provider tests pass**

Run:

```bash
cd engine && . .venv/bin/activate && pytest tests/test_registry.py tests/test_api.py
```

Expected:

```text
6 passed
```

- [ ] **Step 7: Commit**

Run:

```bash
git add engine/omnivoice_engine engine/tests
git commit -m "feat: add local ASR provider registry"
```

Expected:

```text
[main ...] feat: add local ASR provider registry
```

---

## Task 5: Parakeet TDT Provider Slot

**Files:**
- Create: `engine/omnivoice_engine/providers/parakeet_sherpa.py`
- Modify: `engine/omnivoice_engine/providers/registry.py`
- Create: `scripts/download-parakeet-tdt.sh`
- Create: `scripts/run-engine.sh`
- Modify: `engine/tests/test_registry.py`

- [ ] **Step 1: Add provider availability tests**

Append to `engine/tests/test_registry.py`:

```python

def test_parakeet_provider_is_reported_even_when_model_is_absent(monkeypatch):
    monkeypatch.setenv("OMNIVOICE_PARAKEET_MODEL_DIR", "/tmp/omnivoice-missing-parakeet-model")
    registry = ProviderRegistry()

    providers = registry.list_providers()

    parakeet = next(provider for provider in providers if provider.id == "parakeet-tdt")
    assert parakeet.available is False
    assert "model files not found" in parakeet.reason
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
cd engine && . .venv/bin/activate && pytest tests/test_registry.py::test_parakeet_provider_is_reported_even_when_model_is_absent
```

Expected:

```text
StopIteration
```

- [ ] **Step 3: Implement Parakeet provider availability**

Write `engine/omnivoice_engine/providers/parakeet_sherpa.py`:

```python
from __future__ import annotations

import os
from pathlib import Path

from omnivoice_engine.schemas import ProviderInfo

from .base import ASRProvider


class ParakeetSherpaProvider(ASRProvider):
    id = "parakeet-tdt"
    label = "Parakeet TDT"

    def __init__(self, model_dir: str | None = None) -> None:
        configured = model_dir or os.environ.get("OMNIVOICE_PARAKEET_MODEL_DIR")
        self.model_dir = Path(configured or "models/parakeet-tdt").expanduser()

    def info(self) -> ProviderInfo:
        missing = [path.name for path in self._required_paths() if not path.exists()]
        if missing:
            return ProviderInfo(
                id=self.id,
                label=self.label,
                available=False,
                reason=f"model files not found in {self.model_dir}: {', '.join(missing)}",
            )
        try:
            import sherpa_onnx  # noqa: F401
        except Exception as exc:
            return ProviderInfo(
                id=self.id,
                label=self.label,
                available=False,
                reason=f"sherpa-onnx import failed: {exc}",
            )
        return ProviderInfo(id=self.id, label=self.label, available=True)

    def transcribe(self, audio_bytes: bytes) -> str:
        info = self.info()
        if not info.available:
            raise RuntimeError(info.reason)

        import tempfile
        import soundfile as sf
        import sherpa_onnx

        with tempfile.NamedTemporaryFile(suffix=".wav") as wav_file:
            wav_file.write(audio_bytes)
            wav_file.flush()
            samples, sample_rate = sf.read(wav_file.name, dtype="float32")

        recognizer = sherpa_onnx.OfflineRecognizer.from_transducer(
            encoder=str(self.model_dir / "encoder.onnx"),
            decoder=str(self.model_dir / "decoder.onnx"),
            joiner=str(self.model_dir / "joiner.onnx"),
            tokens=str(self.model_dir / "tokens.txt"),
            num_threads=4,
            sample_rate=16000,
            feature_dim=80,
            decoding_method="greedy_search",
        )
        stream = recognizer.create_stream()
        stream.accept_waveform(sample_rate, samples)
        recognizer.decode_stream(stream)
        return stream.result.text.strip()

    def _required_paths(self) -> list[Path]:
        return [
            self.model_dir / "encoder.onnx",
            self.model_dir / "decoder.onnx",
            self.model_dir / "joiner.onnx",
            self.model_dir / "tokens.txt",
        ]
```

- [ ] **Step 4: Register Parakeet provider**

Replace `engine/omnivoice_engine/providers/registry.py` with:

```python
from __future__ import annotations

from omnivoice_engine.schemas import ProviderInfo

from .base import ASRProvider
from .fake import FakeASRProvider
from .parakeet_sherpa import ParakeetSherpaProvider


class ProviderRegistry:
    def __init__(self) -> None:
        self._providers: dict[str, ASRProvider] = {
            "fake": FakeASRProvider(),
            "parakeet-tdt": ParakeetSherpaProvider(),
        }

    def list_providers(self) -> list[ProviderInfo]:
        return [provider.info() for provider in self._providers.values()]

    def get(self, provider_id: str) -> ASRProvider:
        if provider_id not in self._providers:
            raise KeyError(provider_id)
        return self._providers[provider_id]
```

- [ ] **Step 5: Add download script**

Write `scripts/download-parakeet-tdt.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_ROOT="${ROOT_DIR}/models"
MODEL_DIR="${MODEL_ROOT}/parakeet-tdt"
ARCHIVE="${MODEL_ROOT}/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8.tar.bz2"
URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8.tar.bz2"

mkdir -p "${MODEL_ROOT}"
curl -L "${URL}" -o "${ARCHIVE}"
tar -xjf "${ARCHIVE}" -C "${MODEL_ROOT}"
rm -rf "${MODEL_DIR}"
mv "${MODEL_ROOT}/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8" "${MODEL_DIR}"

echo "Parakeet TDT model ready at ${MODEL_DIR}"
```

Write `scripts/run-engine.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}/engine"

if [ ! -d ".venv" ]; then
  python3.12 -m venv .venv
fi

. .venv/bin/activate
pip install -e ".[dev,asr]"
export OMNIVOICE_PARAKEET_MODEL_DIR="${ROOT_DIR}/models/parakeet-tdt"
exec uvicorn omnivoice_engine.main:app --host 127.0.0.1 --port 8765
```

Run:

```bash
chmod +x scripts/download-parakeet-tdt.sh scripts/run-engine.sh
```

- [ ] **Step 6: Verify tests pass**

Run:

```bash
cd engine && . .venv/bin/activate && pytest tests/test_registry.py
```

Expected:

```text
3 passed
```

- [ ] **Step 7: Commit**

Run:

```bash
git add engine/omnivoice_engine/providers engine/tests scripts
git commit -m "feat: add Parakeet TDT provider slot"
```

Expected:

```text
[main ...] feat: add Parakeet TDT provider slot
```

---

## Task 6: Swift Engine Client

**Files:**
- Create: `Sources/OmniVoiceCore/EngineClient.swift`
- Create: `Sources/OmniVoiceCore/EngineStreamingClient.swift`
- Create: `Tests/OmniVoiceCoreTests/EngineClientTests.swift`

- [ ] **Step 1: Write engine client tests**

Write `Tests/OmniVoiceCoreTests/EngineClientTests.swift`:

```swift
import XCTest
@testable import OmniVoiceCore

final class EngineClientTests: XCTestCase {
    func testCleanupRequestEncodesSnakeCasePayload() throws {
        let request = CleanupRequest(rawTranscript: "Schedule it for Monday, actually Tuesday.", style: .neutral)
        let data = try EngineCoding.encoder.encode(request)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(json.contains("raw_transcript"))
        XCTAssertTrue(json.contains("dictionary_terms"))
        XCTAssertTrue(json.contains("neutral"))
    }

    func testCleanupResponseDecodesSnakeCasePayload() throws {
        let data = #"{"text":"Schedule it for Tuesday.","cleanup_applied":true}"#.data(using: .utf8)!

        let response = try EngineCoding.decoder.decode(CleanupResult.self, from: data)

        XCTAssertEqual(response, CleanupResult(text: "Schedule it for Tuesday.", cleanupApplied: true))
    }

    func testTranscribeResponseDecodesProviderPayload() throws {
        let data = #"{"text":"hello","provider":"fake"}"#.data(using: .utf8)!

        let response = try EngineCoding.decoder.decode(TranscribeResult.self, from: data)

        XCTAssertEqual(response.text, "hello")
        XCTAssertEqual(response.provider, .fake)
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
swift test --filter EngineClientTests
```

Expected:

```text
error: cannot find 'EngineCoding' in scope
```

- [ ] **Step 3: Add engine client coding types**

Write `Sources/OmniVoiceCore/EngineClient.swift`:

```swift
import Foundation

public enum EngineCoding {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

public struct TranscribeResult: Codable, Equatable, Sendable {
    public let text: String
    public let provider: ASRProviderKind

    public init(text: String, provider: ASRProviderKind) {
        self.text = text
        self.provider = provider
    }
}

public struct EngineClient: Sendable {
    public enum EngineError: Error, Equatable {
        case badStatus(Int)
        case invalidURL
    }

    public let baseURL: URL
    private let urlSession: URLSession

    public init(baseURL: URL = URL(string: "http://127.0.0.1:8765")!, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.urlSession = urlSession
    }

    public func cleanup(_ request: CleanupRequest) async throws -> CleanupResult {
        let endpoint = baseURL.appending(path: "cleanup")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try EngineCoding.encoder.encode(request)

        let (data, response) = try await urlSession.data(for: urlRequest)
        try validate(response)
        return try EngineCoding.decoder.decode(CleanupResult.self, from: data)
    }

    public func transcribe(audio: Data, provider: ASRProviderKind) async throws -> TranscribeResult {
        var components = URLComponents(url: baseURL.appending(path: "transcribe"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "provider", value: provider.rawValue)]
        guard let endpoint = components?.url else { throw EngineError.invalidURL }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = audio

        let (data, response) = try await urlSession.data(for: urlRequest)
        try validate(response)
        return try EngineCoding.decoder.decode(TranscribeResult.self, from: data)
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw EngineError.badStatus(http.statusCode)
        }
    }
}
```

- [ ] **Step 4: Verify tests pass**

Run:

```bash
swift test --filter EngineClientTests
```

Expected:

```text
Test Suite 'EngineClientTests' passed
```

- [ ] **Step 5: Commit**

Run:

```bash
git add Sources/OmniVoiceCore/EngineClient.swift Tests/OmniVoiceCoreTests/EngineClientTests.swift
git commit -m "feat: add Swift local engine client"
```

Expected:

```text
[main ...] feat: add Swift local engine client
```

---

## Task 7: Preferences And Style Switching

**Files:**
- Create: `Sources/OmniVoiceCore/PreferencesStore.swift`
- Create: `Tests/OmniVoiceCoreTests/PreferencesStoreTests.swift`
- Create: `Sources/OmniVoiceApp/AppModel.swift`

- [ ] **Step 1: Write preferences tests**

Write `Tests/OmniVoiceCoreTests/PreferencesStoreTests.swift`:

```swift
import XCTest
@testable import OmniVoiceCore

final class PreferencesStoreTests: XCTestCase {
    func testDefaultsUseParakeetAndNeutralStyle() {
        let preferences = OmniVoicePreferences.defaults

        XCTAssertEqual(preferences.asrProvider, .parakeetTDT)
        XCTAssertEqual(preferences.style, .neutral)
    }

    func testStyleCycleUpdatesPreference() {
        var preferences = OmniVoicePreferences.defaults

        preferences.cycleStyle()

        XCTAssertEqual(preferences.style, .professional)
    }

    func testProviderCycleUpdatesPreference() {
        var preferences = OmniVoicePreferences.defaults

        preferences.cycleASRProvider()

        XCTAssertEqual(preferences.asrProvider, .canaryQwen25B)
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
swift test --filter PreferencesStoreTests
```

Expected:

```text
error: cannot find 'OmniVoicePreferences' in scope
```

- [ ] **Step 3: Add preferences model**

Write `Sources/OmniVoiceCore/PreferencesStore.swift`:

```swift
import Foundation

public struct OmniVoicePreferences: Codable, Equatable, Sendable {
    public var asrProvider: ASRProviderKind
    public var style: StyleProfile
    public var dictionaryTerms: [String]

    public static let defaults = OmniVoicePreferences(
        asrProvider: .parakeetTDT,
        style: .neutral,
        dictionaryTerms: []
    )

    public init(asrProvider: ASRProviderKind, style: StyleProfile, dictionaryTerms: [String]) {
        self.asrProvider = asrProvider
        self.style = style
        self.dictionaryTerms = dictionaryTerms
    }

    public mutating func cycleStyle() {
        style = style.next()
    }

    public mutating func cycleASRProvider() {
        switch asrProvider {
        case .parakeetTDT:
            asrProvider = .canaryQwen25B
        case .canaryQwen25B:
            asrProvider = .fake
        case .fake:
            asrProvider = .parakeetTDT
        }
    }
}
```

- [ ] **Step 4: Add app model**

Write `Sources/OmniVoiceApp/AppModel.swift`:

```swift
import Foundation
import Observation
import OmniVoiceCore

@MainActor
@Observable
final class AppModel {
    var preferences: OmniVoicePreferences
    var session: DictationSession
    var captionText: String
    var statusText: String

    init(
        preferences: OmniVoicePreferences = .defaults,
        session: DictationSession = DictationSession(),
        captionText: String = "",
        statusText: String = "Ready"
    ) {
        self.preferences = preferences
        self.session = session
        self.captionText = captionText
        self.statusText = statusText
    }

    func cycleStyle() {
        preferences.cycleStyle()
        statusText = "Style: \(preferences.style.displayName)"
    }

    func cycleASRProvider() {
        preferences.cycleASRProvider()
        statusText = "ASR: \(preferences.asrProvider.rawValue)"
    }
}
```

- [ ] **Step 5: Verify tests pass**

Run:

```bash
swift test --filter PreferencesStoreTests
```

Expected:

```text
Test Suite 'PreferencesStoreTests' passed
```

- [ ] **Step 6: Commit**

Run:

```bash
git add Sources/OmniVoiceCore/PreferencesStore.swift Sources/OmniVoiceApp/AppModel.swift Tests/OmniVoiceCoreTests/PreferencesStoreTests.swift
git commit -m "feat: add preferences and style switching state"
```

Expected:

```text
[main ...] feat: add preferences and style switching state
```

---

## Task 8: Menu Bar App Shell

**Files:**
- Modify: `Sources/OmniVoiceApp/OmniVoiceApp.swift`
- Create: `Sources/OmniVoiceApp/AppDelegate.swift`

- [ ] **Step 1: Replace app entry with shared app model**

Write `Sources/OmniVoiceApp/OmniVoiceApp.swift`:

```swift
import SwiftUI
import OmniVoiceCore

@main
struct OmniVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("OmniVoice", systemImage: "waveform") {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.statusText)
                Divider()
                Text("ASR: \(model.preferences.asrProvider.rawValue)")
                Text("Style: \(model.preferences.style.displayName)")
                Button("Cycle Style") {
                    model.cycleStyle()
                }
                Button("Cycle ASR Provider") {
                    model.cycleASRProvider()
                }
                Divider()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(8)
            .task {
                appDelegate.attach(model: model)
            }
        }
    }
}
```

- [ ] **Step 2: Add app delegate permission hooks**

Write `Sources/OmniVoiceApp/AppDelegate.swift`:

```swift
import AppKit
import AVFoundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    func attach(model: AppModel) {
        self.model = model
        updatePermissionStatus()
    }

    private func updatePermissionStatus() {
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let accessibilityEnabled = AXIsProcessTrusted()

        switch (micStatus, accessibilityEnabled) {
        case (.authorized, true):
            model?.statusText = "Ready"
        case (.notDetermined, _):
            model?.statusText = "Microphone permission required"
        case (_, false):
            model?.statusText = "Accessibility permission required"
        default:
            model?.statusText = "Permissions required"
        }
    }
}
```

- [ ] **Step 3: Build app shell**

Run:

```bash
swift build
```

Expected:

```text
Build complete
```

- [ ] **Step 4: Commit**

Run:

```bash
git add Sources/OmniVoiceApp
git commit -m "feat: add menu bar app shell"
```

Expected:

```text
[main ...] feat: add menu bar app shell
```

---

## Task 9: Caption Overlay

**Files:**
- Create: `Sources/OmniVoiceApp/CaptionOverlayView.swift`
- Create: `Sources/OmniVoiceApp/CaptionOverlayWindow.swift`
- Modify: `Sources/OmniVoiceApp/AppDelegate.swift`

- [ ] **Step 1: Add overlay view**

Write `Sources/OmniVoiceApp/CaptionOverlayView.swift`:

```swift
import SwiftUI

struct CaptionOverlayView: View {
    let text: String
    let styleName: String

    var body: some View {
        VStack(spacing: 6) {
            Text(styleName)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text.isEmpty ? "Listening..." : text)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(minWidth: 320, maxWidth: 760)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(radius: 18)
    }
}
```

- [ ] **Step 2: Add non-activating overlay window**

Write `Sources/OmniVoiceApp/CaptionOverlayWindow.swift`:

```swift
import AppKit
import SwiftUI

@MainActor
final class CaptionOverlayWindow {
    private var window: NSWindow?

    func show(text: String, styleName: String) {
        let content = NSHostingView(rootView: CaptionOverlayView(text: text, styleName: styleName))
        let targetSize = content.fittingSize
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let origin = CGPoint(
            x: screenFrame.midX - targetSize.width / 2,
            y: screenFrame.minY + 72
        )

        if window == nil {
            let created = NSWindow(
                contentRect: CGRect(origin: origin, size: targetSize),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            created.isOpaque = false
            created.backgroundColor = .clear
            created.level = .floating
            created.ignoresMouseEvents = true
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window = created
        }

        window?.contentView = content
        window?.setFrame(CGRect(origin: origin, size: targetSize), display: true)
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }
}
```

- [ ] **Step 3: Attach overlay to delegate**

Modify `Sources/OmniVoiceApp/AppDelegate.swift` to add:

```swift
private let overlay = CaptionOverlayWindow()

func showOverlay(text: String, styleName: String) {
    overlay.show(text: text, styleName: styleName)
}

func hideOverlay() {
    overlay.hide()
}
```

- [ ] **Step 4: Build overlay**

Run:

```bash
swift build
```

Expected:

```text
Build complete
```

- [ ] **Step 5: Commit**

Run:

```bash
git add Sources/OmniVoiceApp/CaptionOverlayView.swift Sources/OmniVoiceApp/CaptionOverlayWindow.swift Sources/OmniVoiceApp/AppDelegate.swift
git commit -m "feat: add caption overlay window"
```

Expected:

```text
[main ...] feat: add caption overlay window
```

---

## Task 10: Hotkey Controller

**Files:**
- Create: `Sources/OmniVoiceApp/HotkeyController.swift`
- Modify: `Sources/OmniVoiceApp/AppDelegate.swift`

- [ ] **Step 1: Add Carbon hotkey controller**

Write `Sources/OmniVoiceApp/HotkeyController.swift`:

```swift
import Carbon
import Foundation

@MainActor
final class HotkeyController {
    enum Event {
        case dictationPressed
        case dictationReleased
        case stylePressed
    }

    var onEvent: ((Event) -> Void)?

    private var dictationHotkey: EventHotKeyRef?
    private var styleHotkey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    func register() {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]

        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, userData in
            guard let userData else { return noErr }
            let controller = Unmanaged<HotkeyController>.fromOpaque(userData).takeUnretainedValue()
            return controller.handle(eventRef: eventRef)
        }, UInt32(eventTypes.count), &eventTypes, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)

        var dictationID = EventHotKeyID(signature: OSType(0x4F4D4E49), id: 1)
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(cmdKey | optionKey), dictationID, GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &dictationHotkey)

        var styleID = EventHotKeyID(signature: OSType(0x4F4D4E49), id: 2)
        RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(cmdKey | optionKey), styleID, GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &styleHotkey)
    }

    private func handle(eventRef: EventRef?) -> OSStatus {
        guard let eventRef else { return noErr }
        var hotkeyID = EventHotKeyID()
        GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotkeyID
        )

        let kind = GetEventKind(eventRef)
        if hotkeyID.id == 1 {
            onEvent?(kind == UInt32(kEventHotKeyPressed) ? .dictationPressed : .dictationReleased)
        } else if hotkeyID.id == 2 && kind == UInt32(kEventHotKeyPressed) {
            onEvent?(.stylePressed)
        }
        return noErr
    }
}
```

- [ ] **Step 2: Wire hotkeys into delegate**

Modify `Sources/OmniVoiceApp/AppDelegate.swift`:

```swift
private let hotkeys = HotkeyController()
```

Inside `attach(model:)`, after `updatePermissionStatus()`:

```swift
hotkeys.onEvent = { [weak self] event in
    self?.handleHotkey(event)
}
hotkeys.register()
```

Add:

```swift
private func handleHotkey(_ event: HotkeyController.Event) {
    guard let model else { return }
    switch event {
    case .dictationPressed:
        model.session.pressHotkey()
        showOverlay(text: "", styleName: model.preferences.style.displayName)
    case .dictationReleased:
        model.session.releaseHotkey(finalTranscript: model.captionText)
        hideOverlay()
    case .stylePressed:
        model.cycleStyle()
        showOverlay(text: model.statusText, styleName: model.preferences.style.displayName)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.hideOverlay()
        }
    }
}
```

- [ ] **Step 3: Build hotkeys**

Run:

```bash
swift build
```

Expected:

```text
Build complete
```

- [ ] **Step 4: Commit**

Run:

```bash
git add Sources/OmniVoiceApp/HotkeyController.swift Sources/OmniVoiceApp/AppDelegate.swift
git commit -m "feat: add dictation and style hotkeys"
```

Expected:

```text
[main ...] feat: add dictation and style hotkeys
```

---

## Task 11: Audio Capture Service

**Files:**
- Create: `Sources/OmniVoiceApp/AudioCaptureService.swift`
- Modify: `Sources/OmniVoiceApp/AppDelegate.swift`

- [ ] **Step 1: Add microphone capture service**

Write `Sources/OmniVoiceApp/AudioCaptureService.swift`:

```swift
import AVFoundation
import Foundation

final class AudioCaptureService {
    private let engine = AVAudioEngine()
    private var buffers: [AVAudioPCMBuffer] = []
    private let queue = DispatchQueue(label: "omnivoice.audio.capture")

    var onLevel: ((Float) -> Void)?

    func start() throws {
        buffers.removeAll()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.queue.async {
                self?.buffers.append(buffer.copy() as! AVAudioPCMBuffer)
                self?.onLevel?(Self.level(buffer: buffer))
            }
        }

        engine.prepare()
        try engine.start()
    }

    func stopWAVData() throws -> Data {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)

        let captured = queue.sync { buffers }
        guard let first = captured.first else { return Data() }

        let tempURL = FileManager.default.temporaryDirectory.appending(path: "omnivoice-\(UUID().uuidString).wav")
        let file = try AVAudioFile(forWriting: tempURL, settings: first.format.settings)
        for buffer in captured {
            try file.write(from: buffer)
        }
        let data = try Data(contentsOf: tempURL)
        try? FileManager.default.removeItem(at: tempURL)
        return data
    }

    private static func level(buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<frameCount {
            sum += abs(channel[index])
        }
        return sum / Float(frameCount)
    }
}
```

- [ ] **Step 2: Wire capture lifecycle to hotkeys**

Modify `Sources/OmniVoiceApp/AppDelegate.swift`:

```swift
private let audioCapture = AudioCaptureService()
private let engineClient = EngineClient()
```

Replace `.dictationPressed` branch:

```swift
case .dictationPressed:
    model.session.pressHotkey()
    model.captionText = ""
    do {
        try audioCapture.start()
        showOverlay(text: "", styleName: model.preferences.style.displayName)
    } catch {
        model.session.fail("Microphone failed: \(error.localizedDescription)")
        model.statusText = "Microphone failed"
    }
```

Replace `.dictationReleased` branch:

```swift
case .dictationReleased:
    Task { [weak self] in
        await self?.finishDictation()
    }
```

Add:

```swift
private func finishDictation() async {
    guard let model else { return }
    do {
        let audio = try audioCapture.stopWAVData()
        let transcript = try await engineClient.transcribe(audio: audio, provider: model.preferences.asrProvider)
        model.session.releaseHotkey(finalTranscript: transcript.text)
        model.captionText = transcript.text
        showOverlay(text: transcript.text, styleName: model.preferences.style.displayName)
    } catch {
        model.session.fail("Transcription failed: \(error.localizedDescription)")
        model.statusText = "Transcription failed"
        hideOverlay()
    }
}
```

- [ ] **Step 3: Build capture**

Run:

```bash
swift build
```

Expected:

```text
Build complete
```

- [ ] **Step 4: Commit**

Run:

```bash
git add Sources/OmniVoiceApp/AudioCaptureService.swift Sources/OmniVoiceApp/AppDelegate.swift
git commit -m "feat: capture push-to-talk audio"
```

Expected:

```text
[main ...] feat: capture push-to-talk audio
```

---

## Task 12: Streaming Caption Transport

**Files:**
- Create: `Sources/OmniVoiceCore/EngineStreamingClient.swift`
- Modify: `Sources/OmniVoiceApp/AudioCaptureService.swift`
- Modify: `Sources/OmniVoiceApp/AppDelegate.swift`
- Modify: `engine/omnivoice_engine/main.py`
- Modify: `engine/omnivoice_engine/providers/base.py`
- Modify: `engine/omnivoice_engine/providers/fake.py`
- Modify: `engine/omnivoice_engine/providers/parakeet_sherpa.py`

- [ ] **Step 1: Add streaming provider contract in Python**

Add this method inside the `ASRProvider` class in `engine/omnivoice_engine/providers/base.py`:

```python

    def transcribe_pcm_float32(self, pcm_bytes: bytes, sample_rate: int) -> str:
        return self.transcribe(pcm_bytes)
```

Add this method inside the `FakeASRProvider` class in `engine/omnivoice_engine/providers/fake.py`:

```python

    def transcribe_pcm_float32(self, pcm_bytes: bytes, sample_rate: int) -> str:
        if len(pcm_bytes) < 4096:
            return "listening"
        return "fake transcript"
```

Add this method inside the `ParakeetSherpaProvider` class in `engine/omnivoice_engine/providers/parakeet_sherpa.py`:

```python

    def transcribe_pcm_float32(self, pcm_bytes: bytes, sample_rate: int) -> str:
        info = self.info()
        if not info.available:
            raise RuntimeError(info.reason)

        import numpy as np
        import sherpa_onnx

        samples = np.frombuffer(pcm_bytes, dtype=np.float32)
        recognizer = sherpa_onnx.OfflineRecognizer.from_transducer(
            encoder=str(self.model_dir / "encoder.onnx"),
            decoder=str(self.model_dir / "decoder.onnx"),
            joiner=str(self.model_dir / "joiner.onnx"),
            tokens=str(self.model_dir / "tokens.txt"),
            num_threads=4,
            sample_rate=16000,
            feature_dim=80,
            decoding_method="greedy_search",
        )
        stream = recognizer.create_stream()
        stream.accept_waveform(sample_rate, samples)
        recognizer.decode_stream(stream)
        return stream.result.text.strip()
```

- [ ] **Step 2: Add WebSocket caption endpoint**

Append to `engine/omnivoice_engine/main.py`:

```python

from fastapi import WebSocket, WebSocketDisconnect


@app.websocket("/stream")
async def stream(websocket: WebSocket, provider: str = "fake", sample_rate: int = 16000) -> None:
    await websocket.accept()
    try:
        asr = registry.get(provider)
    except KeyError:
        await websocket.send_json({"type": "error", "text": f"unknown provider: {provider}"})
        await websocket.close()
        return

    chunks: list[bytes] = []
    await websocket.send_json({"type": "partial", "text": "listening"})

    try:
        while True:
            message = await websocket.receive()
            text_message = message.get("text")
            bytes_message = message.get("bytes")

            if text_message == "__finish__":
                combined = b"".join(chunks)
                final_text = asr.transcribe_pcm_float32(combined, sample_rate)
                await websocket.send_json({"type": "final", "text": final_text})
                await websocket.close()
                return

            if bytes_message:
                chunks.append(bytes_message)
                combined = b"".join(chunks)
                if len(combined) >= 4096:
                    partial = asr.transcribe_pcm_float32(combined, sample_rate)
                    await websocket.send_json({"type": "partial", "text": partial})
    except WebSocketDisconnect:
        return
```

- [ ] **Step 3: Add Swift streaming client**

Write `Sources/OmniVoiceCore/EngineStreamingClient.swift`:

```swift
import Foundation

public final class EngineStreamingClient: @unchecked Sendable {
    public var onUpdate: (@Sendable (TranscriptUpdate) -> Void)?

    private let baseURL: URL
    private let session: URLSession
    private var task: URLSessionWebSocketTask?

    public init(baseURL: URL = URL(string: "ws://127.0.0.1:8765")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func connect(provider: ASRProviderKind) {
        var components = URLComponents(url: baseURL.appending(path: "stream"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "provider", value: provider.rawValue),
            URLQueryItem(name: "sample_rate", value: "16000"),
        ]
        task = session.webSocketTask(with: components.url!)
        task?.resume()
        receiveNext()
    }

    public func sendPCMFloat32(_ data: Data) {
        task?.send(.data(data)) { _ in }
    }

    public func finish() {
        task?.send(.string("__finish__")) { _ in }
    }

    public func cancel() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    private func receiveNext() {
        task?.receive { [weak self] result in
            guard let self else { return }
            if case let .success(message) = result, case let .string(json) = message {
                if let update = Self.decode(json) {
                    self.onUpdate?(update)
                }
            }
            self.receiveNext()
        }
    }

    private static func decode(_ json: String) -> TranscriptUpdate? {
        guard
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
            let type = object["type"],
            let text = object["text"]
        else {
            return nil
        }
        return TranscriptUpdate(text: text, isFinal: type == "final")
    }
}
```

- [ ] **Step 4: Emit audio chunks from capture service**

Modify `Sources/OmniVoiceApp/AudioCaptureService.swift`:

```swift
var onPCMChunk: ((Data) -> Void)?
```

Inside the `installTap` closure, after `self?.onLevel?(Self.level(buffer: buffer))`:

```swift
if let data = Self.float32MonoData(buffer: buffer) {
    self?.onPCMChunk?(data)
}
```

Add:

```swift
private static func float32MonoData(buffer: AVAudioPCMBuffer) -> Data? {
    guard let channel = buffer.floatChannelData?[0] else { return nil }
    let frameCount = Int(buffer.frameLength)
    return Data(bytes: channel, count: frameCount * MemoryLayout<Float>.size)
}
```

- [ ] **Step 5: Wire streaming partials into overlay**

Modify `Sources/OmniVoiceApp/AppDelegate.swift`:

```swift
private let streamingClient = EngineStreamingClient()
```

Inside `.dictationPressed`, before `try audioCapture.start()`:

```swift
streamingClient.onUpdate = { [weak self] update in
    Task { @MainActor [weak self] in
        guard let self, let model = self.model else { return }
        model.captionText = update.text
        model.session.receivePartial(update.text)
        self.showOverlay(text: update.text, styleName: model.preferences.style.displayName)
    }
}
streamingClient.connect(provider: model.preferences.asrProvider)
audioCapture.onPCMChunk = { [weak self] data in
    self?.streamingClient.sendPCMFloat32(data)
}
```

Inside `.dictationReleased`, before starting `finishDictation()`:

```swift
streamingClient.finish()
```

Inside the failure path in `finishDictation()`:

```swift
streamingClient.cancel()
```

- [ ] **Step 6: Verify streaming pieces build and engine starts**

Run:

```bash
swift build
cd engine && . .venv/bin/activate && pytest tests/test_api.py tests/test_registry.py
```

Expected:

```text
Build complete
passed
```

- [ ] **Step 7: Commit**

Run:

```bash
git add Sources/OmniVoiceCore/EngineStreamingClient.swift Sources/OmniVoiceApp engine/omnivoice_engine
git commit -m "feat: stream live caption updates"
```

Expected:

```text
[main ...] feat: stream live caption updates
```

---

## Task 13: Final Cleanup And Text Insertion

**Files:**
- Create: `Sources/OmniVoiceApp/TextInsertionService.swift`
- Modify: `Sources/OmniVoiceApp/AppDelegate.swift`

- [ ] **Step 1: Add text insertion service**

Write `Sources/OmniVoiceApp/TextInsertionService.swift`:

```swift
import AppKit

@MainActor
final class TextInsertionService {
    enum InsertionError: Error {
        case pasteboardUnavailable
    }

    func insert(_ text: String) throws {
        if insertWithAccessibility(text) {
            return
        }
        try insertWithPasteboard(text)
    }

    private func insertWithAccessibility(_ text: String) -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else {
            return false
        }

        let element = focused as! AXUIElement
        var valueRef: CFTypeRef?
        var rangeRef: CFTypeRef?

        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let currentValue = valueRef as? String,
              let rangeValue = rangeRef else {
            return false
        }

        var selectedRange = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &selectedRange) else {
            return false
        }

        let nsValue = currentValue as NSString
        guard selectedRange.location <= nsValue.length,
              selectedRange.location + selectedRange.length <= nsValue.length else {
            return false
        }

        let updated = nsValue.replacingCharacters(in: NSRange(location: selectedRange.location, length: selectedRange.length), with: text)
        guard AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, updated as CFString) == .success else {
            return false
        }

        var newRange = CFRange(location: selectedRange.location + (text as NSString).length, length: 0)
        guard let newRangeValue = AXValueCreate(.cfRange, &newRange) else {
            return true
        }
        AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, newRangeValue)
        return true
    }

    private func insertWithPasteboard(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        let previousItems = pasteboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        } ?? []

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            restore(previousItems, to: pasteboard)
            throw InsertionError.pasteboardUnavailable
        }

        let source = CGEventSource(stateID: .combinedSessionState)
        let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        commandDown?.flags = .maskCommand
        commandUp?.flags = .maskCommand
        commandDown?.post(tap: .cghidEventTap)
        commandUp?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.restore(previousItems, to: pasteboard)
        }
    }

    private func restore(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}
```

- [ ] **Step 2: Wire cleanup and insertion**

Modify `Sources/OmniVoiceApp/AppDelegate.swift`:

```swift
private let insertionService = TextInsertionService()
```

Replace the success path inside `finishDictation()` after `model.captionText = transcript.text`:

```swift
let cleanup = try await engineClient.cleanup(
    CleanupRequest(
        rawTranscript: transcript.text,
        style: model.preferences.style,
        dictionaryTerms: model.preferences.dictionaryTerms
    )
)
model.session.finishCleanup(cleanup.text)
try insertionService.insert(cleanup.text)
model.statusText = "Inserted"
hideOverlay()
model.session.reset()
```

- [ ] **Step 3: Build insertion flow**

Run:

```bash
swift build
```

Expected:

```text
Build complete
```

- [ ] **Step 4: Commit**

Run:

```bash
git add Sources/OmniVoiceApp/TextInsertionService.swift Sources/OmniVoiceApp/AppDelegate.swift
git commit -m "feat: insert cleaned dictation text"
```

Expected:

```text
[main ...] feat: insert cleaned dictation text
```

---

## Task 14: End-To-End Local Verification

**Files:**
- Modify: `docs/superpowers/specs/2026-05-14-omnivoice-design.md`
- Create: `docs/verification/2026-05-14-mac-mvp.md`

- [ ] **Step 1: Run Python engine tests**

Run:

```bash
cd engine && . .venv/bin/activate && pytest
```

Expected:

```text
passed
```

- [ ] **Step 2: Run Swift tests**

Run:

```bash
swift test
```

Expected:

```text
Test Suite 'All tests' passed
```

- [ ] **Step 3: Run full build**

Run:

```bash
swift build
```

Expected:

```text
Build complete
```

- [ ] **Step 4: Start local engine**

Run in one terminal:

```bash
scripts/run-engine.sh
```

Expected:

```text
Uvicorn running on http://127.0.0.1:8765
```

- [ ] **Step 5: Check engine health**

Run in a second terminal:

```bash
curl -s http://127.0.0.1:8765/health
```

Expected:

```json
{"status":"ok"}
```

- [ ] **Step 6: Verify cleanup behavior over HTTP**

Run:

```bash
curl -s http://127.0.0.1:8765/cleanup \
  -H 'Content-Type: application/json' \
  -d '{"raw_transcript":"I am going to the store. No wait, I am going to the house.","style":"neutral","dictionary_terms":[]}'
```

Expected:

```json
{"text":"I am going to the house.","cleanup_applied":true}
```

- [ ] **Step 7: Run app**

Run:

```bash
swift run OmniVoiceApp
```

Expected:

```text
Build complete
```

Manual check:

- Menu bar item appears.
- Pressing `Option+Command+S` cycles the visible style state.
- Pressing and releasing `Option+Command+Space` shows the caption overlay and attempts local transcription.
- With fake provider selected in code, the inserted text is `Fake transcript.` after cleanup.
- With Parakeet selected and model files installed, the inserted text reflects spoken audio.

- [ ] **Step 8: Record verification notes**

Write `docs/verification/2026-05-14-mac-mvp.md`:

```markdown
# OmniVoice Mac MVP Verification

Date: 2026-05-14

## Automated Checks

- `cd engine && . .venv/bin/activate && pytest`
- `swift test`
- `swift build`

## Manual Checks

- Menu bar item appears.
- Style hotkey cycles style.
- Dictation hotkey opens caption overlay.
- Release hotkey sends audio to the local engine.
- Cleanup removes spoken correction markers.
- Final text inserts into TextEdit.

## Model Checks

- Fake ASR provider works.
- Parakeet TDT provider reports available when model files and sherpa-onnx are installed.
- Parakeet TDT provider reports a clear unavailable reason when model files are absent.
```

- [ ] **Step 9: Commit**

Run:

```bash
git add docs/verification docs/superpowers/specs/2026-05-14-omnivoice-design.md
git commit -m "test: document Mac MVP verification"
```

Expected:

```text
[main ...] test: document Mac MVP verification
```

---

## Task 15: Canary-Qwen-2.5B Planning Hook

**Files:**
- Modify: `engine/omnivoice_engine/providers/registry.py`
- Modify: `engine/omnivoice_engine/providers/base.py`
- Modify: `engine/tests/test_registry.py`

- [ ] **Step 1: Add Canary registry test**

Append to `engine/tests/test_registry.py`:

```python

def test_canary_qwen_provider_is_visible_as_installable_accuracy_mode():
    registry = ProviderRegistry()

    providers = registry.list_providers()

    canary = next(provider for provider in providers if provider.id == "canary-qwen-2.5b")
    assert canary.available is False
    assert canary.reason == "Canary-Qwen-2.5B runtime is not installed in this MVP build"
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
cd engine && . .venv/bin/activate && pytest tests/test_registry.py::test_canary_qwen_provider_is_visible_as_installable_accuracy_mode
```

Expected:

```text
StopIteration
```

- [ ] **Step 3: Add unavailable provider type**

Append to `engine/omnivoice_engine/providers/base.py`:

```python

class UnavailableASRProvider(ASRProvider):
    def __init__(self, provider_id: str, label: str, reason: str) -> None:
        self.id = provider_id
        self.label = label
        self._reason = reason

    def info(self) -> ProviderInfo:
        return ProviderInfo(id=self.id, label=self.label, available=False, reason=self._reason)

    def transcribe(self, audio_bytes: bytes) -> str:
        raise RuntimeError(self._reason)
```

- [ ] **Step 4: Register Canary as visible accuracy mode**

Modify `engine/omnivoice_engine/providers/registry.py` imports:

```python
from .base import ASRProvider, UnavailableASRProvider
```

Add to `_providers`:

```python
"canary-qwen-2.5b": UnavailableASRProvider(
    "canary-qwen-2.5b",
    "Canary-Qwen-2.5B",
    "Canary-Qwen-2.5B runtime is not installed in this MVP build",
),
```

- [ ] **Step 5: Verify registry tests**

Run:

```bash
cd engine && . .venv/bin/activate && pytest tests/test_registry.py
```

Expected:

```text
5 passed
```

- [ ] **Step 6: Commit**

Run:

```bash
git add engine/omnivoice_engine/providers engine/tests/test_registry.py
git commit -m "feat: expose Canary-Qwen accuracy mode"
```

Expected:

```text
[main ...] feat: expose Canary-Qwen accuracy mode
```

---

## Final Verification

Run:

```bash
swift test
swift build
cd engine && . .venv/bin/activate && pytest
```

Expected:

```text
Test Suite 'All tests' passed
Build complete
passed
```

Run:

```bash
git status --short
```

Expected:

```text

```

The empty output means every planned change is committed.

## Implementation Risks

- SwiftPM GUI apps can run as development executables, but production permission prompts and distribution will need an app bundle plan.
- The Parakeet provider depends on sherpa-onnx API compatibility with the chosen model artifact. If the exact constructor signature differs, keep the registry contract unchanged and adapt only `parakeet_sherpa.py`.
- Accessibility insertion works only for text elements that expose value and selected-range attributes. The pasteboard path covers common fields that reject direct AX value editing.
- Streaming captions use WebSocket updates from the local engine. Parakeet partial quality depends on sherpa-onnx decode speed on the user's Mac and may need throttling after the first live test.
