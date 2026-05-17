# OmniVoice V2 Feature GUI Map

Last updated: 2026-05-16

This file maps OmniVoice features to the GUI surface where a user should discover, configure, or use them. It also marks gaps where a feature exists in code but is hard to find, or where a planned V2 feature has no GUI yet.

## Recommended GUI Structure

| Surface | Purpose | Direction |
| --- | --- | --- |
| Main window tabs | Stable configuration and feature education | Keep Overview, Dictation, Appearance, Models, Dictionary, and Help/Capabilities as tabbed sections. |
| Conversation side modal | Transcript and conversation history | Implemented as a modal/drawer that slides over the app from the selected side without changing the main window size. |
| Caption overlay | Listening feedback | Keep the overlay window transparent; only the active caption text should have a subtle dark backing. |
| Engine website | Developer/diagnostic dashboard | Keep health, logs, raw transcripts, stream counters, model downloads, JSON export, and restart/start controls here. Do not duplicate the full website inside the app. |
| Menu bar extra | Fast status and actions | Keep compact health, current model/style, show test caption, open settings, open history, and quit. |

## Feature Map

| Feature | Status | Current GUI Location | Proposed GUI Location | Notes |
| --- | --- | --- | --- | --- |
| Push-to-talk dictation | Implemented | Dictation tab, menu bar status, Quick Reference | Dictation tab plus Overview capability card | Core workflow: hold hotkey, speak, release to insert cleaned text. |
| Configurable dictation hotkey | Implemented | Dictation tab, Hotkeys section | Dictation tab | Keep record-button workflow for modifier-only and chord hotkeys. |
| Configurable style hotkey | Implemented | Dictation tab, Hotkeys section | Dictation tab | Also show current style in menu bar. |
| Microphone picker | Implemented | Dictation tab | Dictation tab | Good location. Add input meter preview later. |
| Microphone permission status | Implemented | Overview tab, Status section | Overview tab | Keep permission remediation button near status. |
| Accessibility permission status | Implemented | Overview tab, Status section | Overview tab | Keep permission remediation button near status. |
| Local engine status | Implemented | Overview tab, menu bar, engine website, current side panel | Overview tab and menu bar | Overview shows compact status plus local websocket diagnostics; side panel should not be an engine diagnostics duplicate. |
| Start/restart engine | Implemented | Overview tab; engine website start app button; app auto-starts engine | Overview tab and engine website | App restart handles app-managed engine processes and refreshes status after restart. |
| Parakeet TDT STT provider | Implemented | Dictation tab ASR picker; Models tab | Dictation tab and Models tab | Current default. |
| Canary-Qwen-2.5B provider slot | Partially implemented | Dictation tab ASR picker; Models tab | Dictation tab and Models tab | Provider appears, but runtime is unavailable in MVP. |
| External STT model selection | Partially implemented | Models tab | Models tab | Custom local speech model path can be selected and persisted; runtime execution selector is still planned. |
| Hugging Face model download | Implemented | Models tab, engine website | Models tab and engine website | Good location. |
| Hugging Face update check | Implemented | Models tab, engine website | Models tab and engine website | Good location. |
| Live caption streaming | Implemented | Caption overlay while listening; Overview stream diagnostics | Caption overlay | Websocket connects before capture starts, app tracks dropped chunks/bytes, and engine website shows active streams/audio/partials. |
| Draggable caption placement | Implemented | Directly dragging caption overlay | Appearance tab | Add a reset position button and maybe a placement preview. |
| Caption themes | Implemented | Appearance tab theme picker | Appearance tab | Keep theme controls here. |
| System/Dark/Light mode | Implemented | Appearance tab | Appearance tab | Good location. |
| Custom accent color | Implemented | Appearance tab | Appearance tab | Good location. |
| 20 visual themes | Implemented | Appearance tab | Appearance tab | Good location. Could benefit from preview grid instead of picker. |
| Waveform styles | Implemented | Appearance tab, Waveform section | Appearance tab | Keep with visual preview. |
| Commit/caption exit effect | Reduced | Internal caption overlay behavior | Not user-facing | Destination-aware cursor flight was removed as too brittle across apps and displays. Keep only subtle caption-local exit behavior. |
| Grammar cleanup | Implemented | Dictation style picker; implicit workflow | Dictation tab and Overview capability card | Also document in Help/Capabilities. |
| "No wait" correction handling | Implemented | Help/Quick Reference | Help/Capabilities | Should appear as a clickable capability with examples. |
| Quote handling | Implemented | Help/Quick Reference | Help/Capabilities | Should appear as a clickable capability with examples. |
| Punctuation handling | Implemented | Help/Quick Reference | Help/Capabilities | Should appear as a clickable capability with examples. |
| Literal/raw mode | Implemented | Dictation style picker; Help/Quick Reference | Dictation tab and Help/Capabilities | Keep style picker, add usage examples. |
| Per-app style profiles | Implemented | Help/Quick Reference | Dictation tab or Help/Capabilities | Expose as a visible "Automatic app profiles" section. |
| Personal dictionary | Implemented | Dictionary tab | Dictionary tab with Help/Capabilities merged below | Help and capabilities are now merged under Dictionary. |
| Command mode | Implemented | Help/Quick Reference | Help/Capabilities | Add clickable examples and supported apps list. |
| App-opening commands | Implemented | Help/Quick Reference | Help/Capabilities | Current command executor supports safe app opening. |
| Undo last dictation command | Implemented | Help/Quick Reference | Help/Capabilities | Also add to menu bar quick actions. |
| Selection rewrite MVP | Implemented | Overview capabilities; Help/Quick Reference | Help/Capabilities | Needs a stronger GUI explanation and examples. |
| Read foreground text and respond | Planned | Integrations/AI tab capability surface | Integrations/AI tab | Requires foreground selection/context capture plus LLM provider configuration. |
| "Ask Claude/Codex/OpenRouter" inline replies | Implemented MVP | Integrations/AI tab capability surface | Integrations/AI tab | Explicit voice patterns route to the OpenAI-compatible handoff endpoint and insert the AI response inline. Provider-native OAuth remains planned. |
| OpenAI-compatible custom API integration | Implemented MVP | Integrations/AI tab | Integrations/AI tab | Base URL, model, and API key are configurable and persisted. Test prompt controls remain planned. |
| Claude Desktop integration | Partial utility support | Integrations/AI tab; docs/INTEGRATIONS.md | Integrations/AI tab and Help/Capabilities | Current support strips Claude placeholder text and can open Claude. No Claude API/OAuth GUI yet. |
| Codex integration | Partial utility support | Integrations/AI tab; docs/INTEGRATIONS.md | Integrations/AI tab and Help/Capabilities | Current support strips Codex placeholder text and works through normal insertion. No Codex OAuth GUI yet. |
| Copilot OAuth integration | Planned | Not available | Integrations/AI tab | Need to validate API/OAuth feasibility before implementation. |
| OpenRouter integration | Implemented MVP | Integrations/AI tab | Integrations/AI tab | Works through OpenRouter's OpenAI-compatible API when configured with base URL, model, and API key. Native account/OAuth setup remains planned. |
| Raycast integration | Implemented externally | Integrations/AI tab; integrations/raycast README | Integrations tab | App-visible entry point now opens the Raycast files. |
| Live translation | Partially implemented | Translation tab | Translation tab | Source/target language, enabled flag, and model path are persisted; runtime translation route remains planned. |
| External translation model selection | Partially implemented | Models tab and Translation tab | Translation tab or Models tab | Local translation model path can be selected and persisted; runtime execution selector is still planned. |
| Inline live streaming into active field | Implemented, optional | Dictation tab advanced setting | Dictation tab | Live type draft uses direct Accessibility replacement while listening and commits the cleaned final text on release. Falls back to normal insertion when unavailable. |
| Conversation transcription | Planned | Not available | Conversation side modal | Should support meeting-style transcript capture and export. |
| Speaker diarization | Research/planned | Not available | Conversation side modal | Need model support confirmation; may require post-processing with LLM if STT provider cannot identify speakers. |
| Conversation history | Implemented | Conversation side modal; engine website transcripts | Conversation side modal | Side drawer now loads recent engine transcripts without resizing the main window. |
| Copy transcript to cursor | Implemented | Conversation side modal | Conversation side modal | Transcript entries have Copy and Insert actions. |
| Transcript export | Implemented | Engine website JSONL links | Conversation side modal and engine website | App should expose friendly export path, website keeps raw export. |
| Engine event log | Implemented | Engine website | Engine website | Diagnostic only; keep out of main app unless troubleshooting. |
| Engine health dashboard | Implemented | Engine website | Engine website, compact Overview status | App should show summary, website should show details. |
| Desktop app launch from website | Implemented | Engine website Start App button | Engine website | Useful diagnostic bridge. |
| DMG/local distribution | Implemented for local dev | Build script, docs/LOCAL_DISTRIBUTION.md | About/Distribution section later | Not needed in daily settings. |

## Help And Capabilities Merge

The current Quick Reference and Capabilities sections should become one "Capabilities" experience, likely inside the Dictionary/Help tab:

| Capability Card | Modal Content |
| --- | --- |
| Dictation | Hotkey workflow, insert behavior, live captions, accessibility requirement. |
| Corrections | "No wait", "scratch that", "oops correction" examples. |
| Quotes and punctuation | Quote phrases, punctuation words, new line/new paragraph examples. |
| Command mode | Supported commands, supported app names, safety limits. |
| Selection rewrite | How to select text first, supported rewrite instructions. |
| Literal/raw mode | How to preserve exact terms, commands, code, and file paths. |
| Personal dictionary | How casing preservation works and when to add terms. |
| Translation | Input/output language controls and model requirements once implemented. |
| AI handoff | Configure an OpenAI-compatible endpoint, then use "Ask Claude/OpenAI/OpenRouter" commands. |
| Conversation mode | Transcript, speaker labels, copy/insert, and export once implemented. |

## Immediate UI Decisions

| Area | Decision |
| --- | --- |
| Side panel | Implemented as an overlay modal/drawer. It does not change the main window width. |
| Side panel content | Implemented as conversation/transcript history with Copy and Insert at Cursor actions. |
| Engine details | Keep detailed engine information on the website and show only compact status in the app. |
| Help tab | Implemented: merged with Dictionary into a combined Dictionary/Capabilities area. |
| Capabilities | Implemented: each capability opens an example modal. |
| Animation | Removed the destination-aware cursor-flight concept; keep subtle caption-local show/hide behavior only. |
| Models | Implemented configuration selectors for speech-to-text and translation model paths; runtime routing remains planned. |
| Integrations | Implemented a dedicated Integrations/AI tab for AI handoff patterns, OpenAI-compatible endpoint/model settings, and Raycast entry points. |
