# Dictation and Streaming Fixes

## Context

Five defects affect dictation undo, streaming error handling, stream readiness, engine responsiveness, and long-conversation performance. The implementation will preserve existing provider interfaces and final-transcription behavior.

## Design

### Safe dictation undo

Record the accessibility field's post-insertion value with each direct insertion. Before undoing, read the field's current value and compare it with that recorded value. Restore the previous snapshot only when they match. If the user or another process changed the field, throw a dedicated error and leave the field untouched. Apply the same guard to insertions committed through live drafts.

### Typed streaming messages and readiness

Decode engine WebSocket messages into explicit ready, transcript-update, and error cases. A `ready` message moves a current connection from connecting to open without producing transcript text. An error message sets failed diagnostics and its server-provided error text without calling the transcript-update handler. For compatibility with older engines, the first valid partial or final message also proves that the stream is open.

The engine emits `ready` only after validating the ASR provider and optional translation provider. It no longer uses the synthetic `listening` partial as its readiness signal. Existing transcript accumulator behavior remains unchanged for any older engine that still sends `listening`.

### Responsive HTTP transcription

Offload synchronous `asr.transcribe(audio_bytes)` calls from the async HTTP endpoint with `asyncio.to_thread`. Keep existing response payloads, errors, and provider selection unchanged.

### Bounded conversation partial decoding

Replace the stream's chunk list with a `bytearray`, extending it as audio arrives. Do not join or copy the full recording on every chunk. Final transcription still consumes the complete recording.

Conversation recorders request a 30-second partial decode window through a new optional stream query parameter. When configured, partial ASR receives only the most recent window; final ASR still receives all audio. Dictation does not set the parameter and retains whole-utterance partial behavior. Copy only the selected partial window on decode ticks.

## Error handling

- Undo after an external edit fails without modifying the field.
- Stream errors appear in diagnostics and are excluded from live and settled transcript segments.
- A stream remains connecting until a ready or valid transcript message arrives; transport failures still produce failed diagnostics.
- HTTP transcription failures retain their existing 502 responses and event logging.

## Verification

Add regression coverage for:

- Undo succeeding on an unchanged field and refusing a changed field.
- Ready, partial, final, malformed, and error stream-message decoding.
- Optional partial-window URL encoding.
- Engine readiness and error behavior.
- HTTP transcription running through `asyncio.to_thread`.
- Bounded partial audio with complete final audio.
- Existing Swift and engine suites passing in full.

## Scope

No incremental ASR provider API, new UI, persistence migration, or unrelated refactoring is included.
