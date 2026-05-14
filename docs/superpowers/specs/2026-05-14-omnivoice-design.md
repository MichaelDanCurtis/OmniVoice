# OmniVoice Design Spec

Date: 2026-05-14
Status: Draft for user review
Target platform: macOS first, Windows later

## Product Intent

OmniVoice is a local-first desktop dictation app inspired by Wispr Flow's core interaction model: the user holds a chosen keyboard shortcut, speaks naturally, sees live transcription feedback, releases the shortcut, and the app inserts cleaned text wherever the cursor is active.

The first version has one clear job: make high-quality voice typing work across normal desktop apps without sending audio or text to a cloud service.

## User Experience

The app runs as a background/menu bar utility.

The user chooses a primary push-to-talk hotkey. While the hotkey is held, OmniVoice records microphone audio and shows a small closed-caption overlay near the bottom of the screen. The overlay displays provisional live transcription so the user can see that speech is being heard and understood.

When the user releases the hotkey, OmniVoice finalizes the utterance, runs a local cleanup pass, and injects the cleaned output into the currently focused text field.

The provisional caption overlay is not inserted into the target application. It is only confidence feedback. The committed output is created after release from the full utterance context.

## Core Behaviors

### Push-To-Talk Dictation

- The user presses and holds the configured dictation hotkey.
- OmniVoice captures audio until the key is released.
- A floating caption overlay appears while audio is active.
- Releasing the hotkey commits one cleaned text insertion.

### Live Caption Overlay

The overlay should be fast, unobtrusive, and visually stable. It should sit near the bottom center of the active display and avoid covering the insertion target when possible.

It should show provisional text from the real-time ASR provider. Because streaming ASR hypotheses can change, the overlay may revise recent words while the user is still speaking.

The overlay disappears after the final text is inserted or after a short success/error state.

### Final Text Insertion

On hotkey release, OmniVoice sends the full utterance transcript to the cleanup layer. The result is inserted at the current cursor location using macOS Accessibility APIs, pasteboard fallback, or synthetic keyboard events depending on what the target application supports.

The app should preserve user workflow by inserting text into the already-focused app rather than forcing the user to copy/paste manually.

## Model Strategy

### Default ASR: Parakeet TDT

The default real-time speech-to-text provider is NVIDIA Parakeet TDT. It is the preferred first target for fast English dictation because the user wants a real-time local experience and English-only support is acceptable for v1.

Parakeet TDT is used for the live caption stream and can also provide the initial final transcript.

### Accuracy Mode: Canary-Qwen-2.5B

OmniVoice should support switching to NVIDIA Canary-Qwen-2.5B as an alternate high-accuracy English ASR provider.

Canary-Qwen-2.5B is treated as an accuracy mode, not the default live mode. It is larger and better suited to cases where the user is willing to trade a little latency for higher transcription quality.

### Future ASR Providers

The ASR layer must be provider-based from the start so new engines can be added without changing the app workflow.

Future provider candidates:

- Qwen3-ASR for multilingual or alternate high-quality local ASR.
- WhisperKit or whisper.cpp for mature local Whisper-based fallback.
- Moonshine or Nemotron Speech Streaming for low-latency streaming experiments.

## Cleanup And Intent Layer

ASR produces a transcript. OmniVoice's value comes from turning that transcript into text the user actually meant to type.

The cleanup layer is a local text model, separate from ASR. It receives:

- raw transcript
- active style profile
- user dictionary terms
- optional recent app/context hints
- correction-handling rules

It returns only the final text to insert.

The first implementation should target a quantized local instruction model such as Qwen3 4B or Qwen3 8B, running in a low-latency non-reasoning mode. The cleanup provider interface should keep this replaceable because the exact local runtime may differ between Apple Silicon and Windows.

### Default Cleanup Behavior

The default style is Neutral/Natural.

The cleanup model should:

- fix grammar and punctuation
- remove filler words
- preserve the user's meaning
- preserve the user's voice
- avoid inventing facts
- handle spoken corrections and backtracking
- apply user vocabulary and spelling preferences
- respect simple formatting commands when supported

### Spoken Self-Correction

Self-correction handling is a core requirement.

Examples:

Raw speech:

> I'm going to go to the store. No wait, I'm going to go to the house.

Final output:

> I'm going to go to the house.

Raw speech:

> Schedule it for Monday, actually Tuesday.

Final output:

> Schedule it for Tuesday.

Raw speech:

> Send it to Sarah with an H, no, Sara without the H.

Final output:

> Send it to Sara.

Correction markers include phrases such as:

- no wait
- actually
- scratch that
- I mean
- make that
- instead
- correction
- rather

The cleanup layer should treat earlier abandoned clauses as draft intent, not literal text to preserve.

## Style Profiles

The default style is Neutral/Natural. The user can switch style with a configurable hotkey.

Initial style profiles:

- Neutral/Natural: clean grammar while sounding like normal speech.
- Professional: make the output polished and business-appropriate.
- Concise: reduce wordiness while preserving meaning.
- Expanded: make terse speech more complete and readable.
- Raw Dictation: minimal cleanup, useful when exact wording matters.

Style switching should be immediate and visible in the overlay or menu bar state. The selected style applies to the next committed utterance.

## Architecture

### Main App

Native macOS app built with Swift/SwiftUI for the first version.

Responsibilities:

- menu bar UI
- preferences window
- global hotkey registration
- microphone permission flow
- Accessibility permission flow
- active display detection
- overlay window management
- local model process lifecycle

### Audio Capture

Responsibilities:

- open the selected microphone
- capture 16 kHz mono-compatible audio
- buffer utterance audio while push-to-talk is active
- stream frames to the ASR provider
- expose final utterance audio/transcript on release

Voice activity detection can help trim leading/trailing silence, but the push-to-talk key remains the primary session boundary.

### ASR Provider Interface

All speech engines implement one local interface:

```swift
protocol ASRProvider {
    func startSession(config: ASRSessionConfig) throws -> ASRSession
}

protocol ASRSession {
    func acceptAudio(_ frames: AudioFrameBuffer)
    func partialTranscript() async -> TranscriptUpdate
    func finish() async throws -> FinalTranscript
    func cancel()
}
```

The app should not know whether the active provider is Parakeet, Canary, Whisper, or another engine.

### Cleanup Provider Interface

The cleanup engine implements a separate local text transformation interface:

```swift
protocol CleanupProvider {
    func rewrite(_ request: CleanupRequest) async throws -> CleanupResult
}
```

The cleanup layer should be testable with text fixtures independent of audio capture.

### Text Insertion Service

The insertion service owns final text delivery to the focused application.

Preferred insertion order:

1. Accessibility API insertion when available.
2. Pasteboard-based insert with paste event.
3. Synthetic keystrokes for fallback cases.

The service should restore the user's clipboard when pasteboard fallback is used.

### Overlay Service

The overlay service displays partial transcripts and status:

- listening
- transcribing
- cleaning
- inserted
- failed

It must not steal focus from the active application.

## Data And Local State

Local state should include:

- hotkey bindings
- selected ASR provider
- selected cleanup style
- microphone choice
- user dictionary
- app-specific style preferences, after v1
- recent local diagnostics, with privacy controls

Audio should be discarded after final text insertion unless the user explicitly enables debug capture.

The transcript history should default to off or local-only with an explicit preference. Since the product is local-first, privacy should be visible in the design, not bolted on later.

## Error Handling

Microphone permission missing:

- Show a clear prompt and open macOS permission settings.

Accessibility permission missing:

- Allow dictation preview but block insertion until permission is granted.

ASR provider unavailable:

- Show a local model error and offer to switch provider if another provider is installed.

Cleanup model unavailable:

- Fall back to lightly punctuated ASR output and show that cleanup was skipped.

Insertion failed:

- Keep final text available in the overlay with a copy action and explain that the target app rejected insertion.

## Testing Strategy

### Unit Tests

- correction-marker rewrite fixtures
- style profile rewrite fixtures
- ASR provider lifecycle state
- hotkey state transitions
- text insertion fallback ordering

### Integration Tests

- record simulated audio into ASR provider
- final transcript into cleanup provider
- cleanup result into a test text field
- permission-disabled states

### Manual Verification

Verify dictation into:

- TextEdit
- Safari/Chrome text areas
- Slack or Messages
- email compose fields
- Cursor or VS Code text editor

Manual tests must include false starts and corrections such as "no wait" and "actually".

## Non-Goals For V1

- Cloud transcription
- Mobile apps
- Team dictionaries
- Account system
- Sync
- Meeting transcription
- Diarization
- Full voice control of arbitrary UI
- Streaming provisional text directly into the focused app

## Open Decisions

These are intentionally deferred until implementation planning:

- Exact local runtime for Parakeet TDT on macOS.
- Whether the cleanup model should run through llama.cpp, MLX, Ollama, or an embedded runtime.
- Exact cleanup model size and quantization, with Qwen3 4B or Qwen3 8B as the first candidate family.
- Whether Canary-Qwen-2.5B should be bundled, downloaded on demand, or treated as an advanced install.
- Exact default hotkeys.
- Exact overlay visual design.

## Source Notes

- Wispr Flow describes the reference behavior as a background app where pressing a hotkey transcribes speech into any text field, with AI commands and vocabulary adaptation: https://docs.wisprflow.ai/articles/2772472373-what-is-flow
- Wispr Flow's public feature page emphasizes cleanup, filler removal, formatting, and real-time correction behavior: https://wisprflow.ai/features
- NVIDIA documents Parakeet TDT as a fast English ASR model family with punctuation/capitalization and strong benchmark performance: https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2
- NVIDIA documents Canary-Qwen-2.5B as an English ASR model with punctuation/capitalization and high accuracy: https://huggingface.co/nvidia/canary-qwen-2.5b
- NVIDIA's NeMo model guide frames Canary-Qwen-2.5B as best-accuracy English ASR and Parakeet TDT as a very fast near-SOTA alternative: https://docs.nvidia.com/nemo/speech/nightly/starthere/choosing_a_model.html
- Qwen3 provides local open-weight text models in small dense sizes suitable for testing the cleanup layer: https://qwenlm.github.io/blog/qwen3/
