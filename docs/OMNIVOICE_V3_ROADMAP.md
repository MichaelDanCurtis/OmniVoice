# OmniVoice V3 Roadmap

V3 is the multilingual and advanced model-capability release. V2 should finish local translation, AI provider configuration, conversation mode, and the local model-management surfaces first.

## Multilingual Speech Input

Goal: support speech-to-text input beyond the current English-first Parakeet path.

Planned work:

- Add a multilingual ASR provider interface that reports language coverage by model.
- Add at least one local Apple Silicon multilingual ASR backend that can recognize Chinese speech and emit Chinese characters in live captions.
- Add model capability flags for English ASR, multilingual ASR, Chinese ASR, translation, timestamps, streaming partials, diarization, and word confidence.
- Update the UI so unsupported language/model combinations are obvious before the user records.
- Keep Parakeet as the fast English-first default and route non-English speech to a multilingual backend when selected.

## Chinese ASR And Captions

Requirement:

- Mandarin/Cantonese speech should transcribe into Chinese characters before translation.
- The caption overlay should display source-language text when translation is off.
- When translation is on, the caption overlay should be able to show source text, translated text, or both depending on user preference.

Important architecture note:

- Translation cannot fix failed ASR. Chinese speech input requires a multilingual ASR model before the translation layer.

## Candidate Model Direction

Research candidates:

- Whisper MLX or whisper.cpp multilingual models.
- SenseVoice-style local multilingual ASR if a stable Apple Silicon path is available.
- Future MLX-native multilingual speech models with streaming partial support.

Acceptance bar:

- Local-only execution.
- Chinese character output from spoken Chinese.
- Usable partial captions while recording.
- Final transcript quality good enough for downstream translation and cleanup.
- Clear fallback behavior when a selected model does not support the detected input language.
