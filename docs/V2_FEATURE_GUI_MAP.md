# OmniVoice V2 Feature GUI Map

Last updated: 2026-05-20

This file maps the V2 release feature set to the user-facing GUI. It is a release checkpoint, not a future-plan backlog.

## Primary Surfaces

| Surface | Purpose |
| --- | --- |
| Main Settings window | Stable configuration for dictation, personalization, models, translation, AI providers, storage, and help. |
| Caption overlay | Live listening feedback, translation status, draggable placement, and liquid-glass visual treatment. |
| Hot menu | Fast mode/style/translation/language switching without opening Settings. |
| Conversation window | Live conversation recording, diarized speaker blocks, conversation library, transcript editing/deletion, and transcript-aware AI chat. |
| Editor window | Notes and document editing with conversation/subject context. |
| Ask AI window | Provider/model-specific AI chat with file, image, audio, conversation, and transcript attachments. |
| Engine dashboard | Developer diagnostics: health, logs, transcripts, model controls, exports, and restart/start controls. |
| Menu bar extra | Fast status, current model/style, test caption, settings, history, conversation mode, and quit. |

## Feature Map

| Feature | Status | GUI Location | Notes |
| --- | --- | --- | --- |
| Push-to-talk dictation | Implemented | Dictation tab, menu bar, hotkey | Hold hotkey, speak, release to insert cleaned text. |
| Double-tap dictation latch | Implemented | Dictation tab | Double-tap keeps dictation open until the next hotkey press. |
| Configurable hotkeys | Implemented | Personalize tab | Record-button workflow supports modifier-only and chord hotkeys. |
| Microphone picker | Implemented | Dictation tab | Selected mic drives dictation and conversation capture. |
| Live captions | Implemented | Caption overlay | Draggable, theme-aware, translation-aware overlay. |
| Local STT | Implemented | Dictation and Models tabs | Parakeet TDT MLX is the default. Whisper Large v3 Turbo MLX 6-bit adds selectable multilingual ASR. Canary-Qwen is an optional NeMo-backed English accuracy provider. |
| Hugging Face integration | Implemented | Models tab | Token validation, gated-model guidance, downloads, update checks, and model deletion. |
| Grammar cleanup and correction handling | Implemented | Dictation tab, Help tab | Covers punctuation, quote handling, no-wait/scratch-that corrections, literal mode, and dictionary terms. |
| Hot menu | Implemented | Personalize tab, overlay | Up cycles modes, right controls translation, left cycles quick languages, down cycles dictation style. |
| Themes and waveform styles | Implemented | Personalize tab | Includes appearance mode, custom accent color, built-in themes, and waveform modes. |
| Live translation | Implemented | Translate tab, hot menu, caption overlay | Local translation model configuration with language dropdowns and quick target languages. |
| AI providers | Implemented | AI tab | Add/remove provider cards, OAuth/device flows where supported, custom OpenAI-compatible providers, custom headers, model refresh, web toggle, and MCP server configuration. |
| Ask AI workspace | Implemented | Ask AI window | Session provider/model selection plus file, image, audio, conversation, and transcript context attachments. |
| Editor and notes | Implemented | Editor window | Notes and editor share subject/conversation context. Markdown and DOCX export are supported. |
| Conversation recording | Implemented | Conversation window | Live transcript blocks, recording controls, library, bulk delete, edit, archive, editor handoff, and Ask AI handoff. |
| Local diarization | Implemented | Conversation window, Models tab | Optional MLX Sortformer path with FP16/FP32 selection. Off mode avoids diarization resource use. |
| Conversation AI chat | Implemented | Conversation window | Runs only when the user asks; current transcript is sent as context. |
| Conversation archive sync | Implemented | Overview Storage section | Imports archived conversation JSON files into the local engine database. |
| Clear local data buttons | Implemented | Overview Storage section | Separate actions for conversation database and Ask AI threads. |
| Engine dashboard | Implemented | `http://127.0.0.1:8765` | The app shows compact status; the website keeps the diagnostic depth. |
| Raycast integration | Implemented | Integrations files and AI tab entry point | External script-command integration remains file-based. |
| DMG/local distribution | Implemented | Build script and docs | Local development DMG is produced by `./script/build_and_run.sh --dmg`. Public distribution still needs Developer ID signing and notarization. |

## Release Notes

| Area | V2 Decision |
| --- | --- |
| Help | Help is now an interactive capability guide with animated demos and detail sheets. |
| Dictionary | Dictionary lives with dictation rather than as a standalone top-level tab. |
| Transcriber | Transcriber concepts were folded into the Editor/notes workflow. |
| Selection rewrite | Removed from the V2 GUI after the editor and AI workflows superseded it. |
| Conversation insights | Continuous AI monitoring is not active by default; transcript-aware chat runs only when asked. |
| Cursor-attached caption | Removed as a default behavior because cross-app cursor geometry was too brittle; the bottom/draggable overlay remains the reliable V2 path. |
