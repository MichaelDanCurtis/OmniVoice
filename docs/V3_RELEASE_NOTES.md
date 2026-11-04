# OmniSpeak V3 Release Notes

V3 is the multilingual, model-capability, and packaged-runtime release.

## Shipped

- Add Whisper Large v3 Turbo MLX 6-bit as the first selectable local Apple Silicon multilingual ASR backend.
- Keep Canary-Qwen-2.5B as an optional NeMo-backed English accuracy provider rather than a dead placeholder.
- Add model capability metadata for English ASR, multilingual ASR, Chinese ASR, translation, timestamps, streaming partials, diarization, and word confidence.
- Update the model UI so unsupported language/model combinations are visible before recording.
- Keep Parakeet as the fast English-first default and route non-English speech to a multilingual backend when selected.
- Add mouse push-to-talk, alternate dictation hotkeys, and a transcript cache picker.
- Add selectable recording cue sounds with independent start/stop timing.
- Package the local app with embedded Python, bundled engine source, and a bundled Python wheelhouse for the normal runtime dependencies.

## Multilingual Speech Input

V3 supports speech-to-text input beyond the English-first Parakeet path through Whisper Large v3 Turbo MLX 6-bit.

The caption overlay displays source-language text when translation is off. When translation is on, the overlay can show translated captions with the active target language.

Important architecture note:

- Translation cannot fix failed ASR. Chinese speech input requires a multilingual ASR model before the translation layer.

## Candidate Model Direction

Primary backend:

- Whisper Large v3 Turbo MLX 6-bit from `mlx-community/whisper-large-v3-turbo-asr-6bit`.

Future candidates:

- whisper.cpp multilingual models.
- SenseVoice-style local multilingual ASR if a stable Apple Silicon path is available.
- Future MLX-native multilingual speech models with streaming partial support.

## Follow-Up Candidates

- More direct source-plus-translation caption display modes.
- More local multilingual ASR candidates as stable MLX paths appear.
- Better production signing, notarization, and first-run installer polish.
