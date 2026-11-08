# Dictation and Streaming Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix destructive dictation undo, streaming error/readiness handling, blocking HTTP inference, and unbounded streaming audio copies and partial decodes.

**Architecture:** Keep the existing ASR provider API. Add a pure undo guard in OmniVoiceCore, explicit WebSocket message decoding shared with an engine `ready` frame, thread-offloaded HTTP transcription, and optional recent-audio windows for conversation partials only.

**Tech Stack:** Swift 6, XCTest, Python 3.12, FastAPI, pytest, asyncio.

**Git:** Do not commit or stage changes; the user has not requested git mutations.

---

### Task 1: Guard dictation undo against later edits

**Files:**
- Modify: `Sources/OmniVoiceCore/TextInsertionEdit.swift`
- Modify: `Sources/OmniVoiceApp/TextInsertionService.swift`
- Test: `Tests/OmniVoiceCoreTests/TextInsertionEditTests.swift`

- [ ] **Step 1: Write failing undo-guard tests**

Append to `TextInsertionEditTests`:

```swift
func testRestoresPreviousValueWhenInsertedValueIsUnchanged() {
    let restored = TextInsertionEdit.restoredPreviousValue(
        currentValue: "Hello dictated",
        insertedValue: "Hello dictated",
        previousValue: "Hello "
    )

    XCTAssertEqual(restored, "Hello ")
}

func testRefusesRestoreWhenFieldChangedAfterInsertion() {
    let restored = TextInsertionEdit.restoredPreviousValue(
        currentValue: "Hello dictated plus later typing",
        insertedValue: "Hello dictated",
        previousValue: "Hello "
    )

    XCTAssertNil(restored)
}
```

- [ ] **Step 2: Run the tests and verify they fail**

Run: `swift test --filter TextInsertionEditTests`

Expected: compilation fails because `restoredPreviousValue` is not defined.

- [ ] **Step 3: Implement the pure undo guard**

Add to `TextInsertionEdit`:

```swift
public static func restoredPreviousValue(
    currentValue: String,
    insertedValue: String,
    previousValue: String
) -> String? {
    guard currentValue == insertedValue else { return nil }
    return previousValue
}
```

- [ ] **Step 4: Run the core tests and verify they pass**

Run: `swift test --filter TextInsertionEditTests`

Expected: all `TextInsertionEditTests` pass.

- [ ] **Step 5: Apply the guard to accessibility undo**

Add `case insertionChanged` to `TextInsertionService.InsertionError` with description `"Text changed after dictation; nothing was undone."`.

Add `let insertedValue: String` to `DirectInsertionRecord`. Set `insertedValue: edit.text` in both record initializers.

At the start of `undoLastInsertion`, after resolving `record`, read `Self.textState(for: record.element)?.currentValue`. Throw `syntheticTypingUnavailable` if it cannot be read. Then use:

```swift
guard let restoredValue = TextInsertionEdit.restoredPreviousValue(
    currentValue: currentValue,
    insertedValue: record.insertedValue,
    previousValue: record.previousText
) else {
    throw InsertionError.insertionChanged
}
```

Pass `restoredValue` to `AXUIElementSetAttributeValue` instead of `record.previousText`.

Run: `swift test --filter TextInsertionEditTests`

Expected: tests pass and the app target compiles.

### Task 2: Decode streaming errors and readiness explicitly

**Files:**
- Modify: `Sources/OmniVoiceCore/EngineStreamingClient.swift`
- Modify: `engine/omnivoice_engine/main.py`
- Test: `Tests/OmniVoiceCoreTests/EngineClientTests.swift`
- Test: `engine/tests/test_api.py`

- [ ] **Step 1: Write failing message-decoding tests**

Append to `EngineClientTests`:

```swift
func testStreamingMessageDecodesReady() throws {
    let message = try XCTUnwrap(EngineStreamingClient.decode(#"{"type":"ready","text":""}"#))
    XCTAssertEqual(message, .ready)
}

func testStreamingMessageDecodesErrorSeparatelyFromTranscript() throws {
    let message = try XCTUnwrap(EngineStreamingClient.decode(
        #"{"type":"error","text":"transcription failed: decoder exploded"}"#
    ))
    XCTAssertEqual(message, .error("transcription failed: decoder exploded"))
}

func testStreamingMessageDecodesPartialAndFinal() throws {
    let partial = try XCTUnwrap(EngineStreamingClient.decode(#"{"type":"partial","text":"hello"}"#))
    let final = try XCTUnwrap(EngineStreamingClient.decode(#"{"type":"final","text":"hello"}"#))

    XCTAssertEqual(partial, .update(TranscriptUpdate(text: "hello", isFinal: false)))
    XCTAssertEqual(final, .update(TranscriptUpdate(text: "hello", isFinal: true)))
}

func testStreamingMessageRejectsMalformedPayload() {
    XCTAssertNil(EngineStreamingClient.decode("not json"))
}
```

- [ ] **Step 2: Run the tests and verify they fail**

Run: `swift test --filter EngineClientTests`

Expected: compilation fails because the typed message decoder is not defined.

- [ ] **Step 3: Implement typed decoding without emitting errors as transcripts**

Add an internal enum outside `EngineStreamingClient`:

```swift
enum EngineStreamingMessage: Equatable {
    case ready
    case update(TranscriptUpdate)
    case error(String)
}
```

Change `decode` to internal visibility and return `EngineStreamingMessage?`:

```swift
static func decode(_ json: String) -> EngineStreamingMessage? {
    struct StreamingPayload: Decodable {
        let type: String
        let text: String
    }

    guard
        let data = json.data(using: .utf8),
        let payload = try? streamingDecoder.decode(StreamingPayload.self, from: data)
    else {
        return nil
    }

    switch payload.type {
    case "ready":
        return .ready
    case "partial", "final":
        return .update(TranscriptUpdate(text: payload.text, isFinal: payload.type == "final"))
    case "error":
        return .error(payload.text)
    default:
        return nil
    }
}
```

Remove the unconditional `.open` update immediately after `task.resume()` in `connect`.

Replace the successful string-message branch in `receiveNext` with typed handling:

```swift
if case let .success(message) = result, case let .string(json) = message {
    if let message = Self.decode(json) {
        switch message {
        case .ready:
            if diagnostics.state == .connecting {
                updateDiagnostics { $0.state = .open }
            }
        case let .update(update):
            if diagnostics.state == .connecting {
                updateDiagnostics { $0.state = .open }
            }
            updateDiagnostics {
                $0.updatesReceived += 1
                if update.isFinal {
                    $0.finalsReceived += 1
                } else {
                    $0.partialsReceived += 1
                }
                $0.lastText = update.text
            }
            onUpdate?(update)
        case let .error(message):
            updateDiagnostics {
                $0.state = .failed
                $0.lastError = message
            }
        }
    }
    receiveNext(task: task, token: token)
}
```

Keep the existing binary-message and cleanup branches. In the receive-failure branch, do not replace a server-provided error when state is already `.failed`; add `.failed` to the states excluded from transport-error overwriting.

- [ ] **Step 4: Change the engine readiness frame and tests**

In `stream`, replace:

```python
await websocket.send_json({"type": "partial", "text": "listening"})
```

with:

```python
await websocket.send_json({"type": "ready", "text": ""})
```

In both stream success tests, replace the initial expected payload with:

```python
assert websocket.receive_json() == {"type": "ready", "text": ""}
```

Keep the provider-failure test's initial expectation unchanged until it reaches the failure frame; if that test currently expects `listening` after ASR initialization, change only that initial expectation to `ready`.

- [ ] **Step 5: Run focused tests and verify they pass**

Run: `swift test --filter EngineClientTests`

Expected: all `EngineClientTests` pass.

Run: `uv run --extra dev --extra asr python -m pytest tests/test_api.py -k stream`

Expected: all selected engine stream tests pass.

### Task 3: Offload blocking HTTP transcription

**Files:**
- Modify: `engine/omnivoice_engine/main.py`
- Test: `engine/tests/test_api.py`

- [ ] **Step 1: Write a failing offload test**

Append to `engine/tests/test_api.py`:

```python
def test_transcribe_endpoint_offloads_blocking_inference(monkeypatch):
    captured = {}

    class OffloadASR:
        def info(self):
            return ProviderInfo(id="offload", label="Offload", available=True)

        def transcribe(self, audio_bytes):
            captured["audio_bytes"] = audio_bytes
            return "offloaded transcript"

    class OffloadRegistry:
        def get(self, provider_id):
            assert provider_id == "offload"
            return OffloadASR()

    async def fake_to_thread(function, *args):
        captured["function_name"] = function.__name__
        return function(*args)

    monkeypatch.setattr("omnivoice_engine.main.registry", OffloadRegistry(), raising=False)
    monkeypatch.setattr(engine_main.asyncio, "to_thread", fake_to_thread)

    response = client.post("/transcribe?provider=offload", content=b"audio-bytes")

    assert response.status_code == 200
    assert response.json() == {"text": "offloaded transcript", "provider": "offload"}
    assert captured == {
        "audio_bytes": b"audio-bytes",
        "function_name": "transcribe",
    }
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `uv run --extra dev --extra asr python -m pytest tests/test_api.py::test_transcribe_endpoint_offloads_blocking_inference -v`

Expected: the captured dictionary lacks `function_name`.

- [ ] **Step 3: Offload the synchronous provider call**

In the async `/transcribe` endpoint, replace:

```python
text = asr.transcribe(audio_bytes)
```

with:

```python
text = await asyncio.to_thread(asr.transcribe, audio_bytes)
```

- [ ] **Step 4: Run focused tests and verify they pass**

Run: `uv run --extra dev --extra asr python -m pytest tests/test_api.py -k transcribe`

Expected: all transcription endpoint tests pass.

### Task 4: Use linear audio accumulation and bounded conversation partials

**Files:**
- Modify: `Sources/OmniVoiceCore/EngineStreamingClient.swift`
- Modify: `Sources/OmniVoiceApp/ConversationRecorderService.swift`
- Modify: `engine/omnivoice_engine/main.py`
- Test: `Tests/OmniVoiceCoreTests/EngineClientTests.swift`
- Test: `engine/tests/test_api.py`

- [ ] **Step 1: Write a failing URL test**

Append to `EngineClientTests`:

```swift
func testStreamingURLIncludesPartialWindowWhenConfigured() {
    let url = EngineStreamingClient.streamURL(
        baseURL: URL(string: "ws://127.0.0.1:8765")!,
        provider: .parakeetTDTMLX,
        sampleRate: 16_000,
        partialWindowSeconds: 30
    )
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let items = components?.queryItems ?? []
    let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })

    XCTAssertEqual(query["partial_window_seconds"], "30")
}
```

- [ ] **Step 2: Run the URL test and verify it fails**

Run: `swift test --filter EngineClientTests.testStreamingURLIncludesPartialWindowWhenConfigured`

Expected: compilation fails because `partialWindowSeconds` is not an argument.

- [ ] **Step 3: Add the optional client parameter and request it for conversations**

Add `partialWindowSeconds: Int? = nil` after `translation` in both `connect` and `streamURL`. Forward it from `connect` to `streamURL`. When non-nil, append:

```swift
queryItems.append(
    URLQueryItem(
        name: "partial_window_seconds",
        value: String(max(1, partialWindowSeconds))
    )
)
```

In `ConversationRecorderService.start`, change its streaming connection call to:

```swift
streamingClient.connect(
    provider: provider,
    sampleRate: Double(sampleRate),
    partialWindowSeconds: 30
)
```

Leave the dictation call in `AppDelegate` unchanged.

- [ ] **Step 4: Write a failing bounded-partial engine test**

Append to `engine/tests/test_api.py`:

```python
def test_stream_endpoint_bounds_partial_audio_but_finishes_with_full_audio(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)
    decoded_lengths = []

    class RecordingASR:
        def info(self):
            return ProviderInfo(id="recording", label="Recording", available=True)

        def transcribe_pcm_float32(self, pcm_bytes, sample_rate):
            assert sample_rate == 16_000
            decoded_lengths.append(len(pcm_bytes))
            return "recorded transcript"

    class RecordingRegistry:
        def get(self, provider_id):
            assert provider_id == "recording"
            return RecordingASR()

    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    monkeypatch.setattr("omnivoice_engine.main.registry", RecordingRegistry(), raising=False)

    with client.websocket_connect(
        "/stream?provider=recording&sample_rate=16000&partial_window_seconds=1"
    ) as websocket:
        assert websocket.receive_json() == {"type": "ready", "text": ""}
        websocket.send_bytes(b"0" * 128_000)
        assert websocket.receive_json()["type"] == "partial"
        websocket.send_text("__finish__")
        assert websocket.receive_json()["type"] == "final"

    assert decoded_lengths == [64_000, 128_000]
```

- [ ] **Step 5: Run the engine test and verify the partial length fails**

Run: `uv run --extra dev --extra asr python -m pytest tests/test_api.py::test_stream_endpoint_bounds_partial_audio_but_finishes_with_full_audio -v`

Expected: partial and final lengths are both `128_000`, so the assertion fails.

- [ ] **Step 6: Implement bytearray accumulation and optional windows**

Add `partial_window_seconds: int = 0` to the `/stream` WebSocket parameters.

Replace `chunks: list[bytes] = []` with `chunks = bytearray()` and define:

```python
partial_window_bytes = (
    max(4096, sample_rate * 4 * partial_window_seconds)
    if partial_window_seconds > 0
    else None
)
```

At finalization, use `combined = bytes(chunks)`. For each binary message, replace `chunks.append(bytes_message)` with `chunks.extend(bytes_message)` and remove the per-chunk full join. Calculate `enough_new_audio` from `len(chunks)`.

Only when a partial decode is due, construct its input:

```python
partial_audio = (
    bytes(chunks[-partial_window_bytes:])
    if partial_window_bytes is not None
    else bytes(chunks)
)
partial = await asyncio.to_thread(
    asr.transcribe_pcm_float32,
    partial_audio,
    sample_rate,
)
```

Update `last_decode_size` and event byte counts from `len(chunks)`. Final transcription and its logging continue to use complete `combined` audio.

- [ ] **Step 7: Run focused tests and verify they pass**

Run: `swift test --filter EngineClientTests`

Expected: all streaming client tests pass.

Run: `uv run --extra dev --extra asr python -m pytest tests/test_api.py -k stream`

Expected: all stream tests pass, including bounded partial and full final lengths.

### Task 5: Full verification and cleanup

**Files:**
- Verify all modified source and test files.
- Remove test-generated `engine/.venv` and `engine/uv.lock` if this run created them and they were absent initially.

- [ ] **Step 1: Run the complete Swift suite**

Run: `swift test`

Expected: all tests pass with zero failures.

- [ ] **Step 2: Run the complete engine suite**

Run from `engine/`: `uv run --extra dev --extra asr python -m pytest`

Expected: all engine tests pass.

- [ ] **Step 3: Exercise protocol behavior end to end**

Run the focused engine stream tests and Swift decoding tests together:

```bash
swift test --filter EngineClientTests
cd engine && uv run --extra dev --extra asr python -m pytest tests/test_api.py -k 'stream or transcribe'
```

Expected: readiness, errors, HTTP transcription, partial windows, and final transcription all pass through their real endpoint/client protocol tests.

- [ ] **Step 4: Check repository state and remove only generated artifacts**

Run from the repository root: `git status --short`

Expected: only intended source, test, spec, and plan changes plus the pre-existing `.omc/project-memory.json` and `.serena/project.yml` modifications. Remove `engine/.venv` and `engine/uv.lock` when created by these test runs; do not alter the pre-existing metadata edits.
