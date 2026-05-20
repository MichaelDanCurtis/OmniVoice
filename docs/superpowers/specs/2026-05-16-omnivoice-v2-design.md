# OmniVoice v2 Design Spec

Date: 2026-05-16
Branch: `codex/v2`
Status: Approved design direction

## v2 Product Goal

OmniVoice v2 should turn the v1 utility into a polished local-first voice control center. The first implementation slice is the visual/theme foundation. Live translation and live typed streaming are v2 capabilities, but they should build on the same settings, model-management, and theme infrastructure rather than arriving as isolated features.

The v2 default visual identity is dark blue/cyan glass with neon signal accents. Users can define their own accent color, and OmniVoice derives the matching glass, caption, hotkey, waveform, and engine-frame treatment from that color.

## Scope Order

1. Theme/glass system.
2. Themed app shell and embedded engine frame.
3. Theme presets, custom theme editor, and waveform/VU modes.
4. Live translation provider model and UI capability reporting.
5. Live typed streaming after provisional insertion and replacement behavior is proven.

## Theme System

The theme system is token-based. A shared theme model drives every visual surface instead of hardcoded one-off styles.

Theme tokens:

- `id`
- `name`
- `accentColor`
- `secondaryAccentColor`
- `surfaceTint`
- `glassOpacity`
- `captionOpacity`
- `glowStrength`
- `contrastMode`
- `waveformPalette`
- `waveformMode`
- `commitAnimationMode`
- `engineFrameSide`
- `motionIntensity`

The default theme is a blue/cyan glass theme. It should feel premium, dark, technical, and macOS-native without turning into a decorative landing page.

## Custom Theme Editing

The custom theme editor uses a simple-first, advanced-expandable model.

Default editing:

- user chooses one accent color
- OmniVoice derives secondary accent, glass tint, glow, caption border, waveform colors, and focus states
- preview updates immediately

Advanced editing:

- secondary accent
- surface tint
- glass opacity
- caption opacity
- glow strength
- waveform colors
- contrast mode
- motion intensity

The editor must include contrast guardrails. If a user-selected color creates unreadable captions or controls, OmniVoice should adjust text/border treatment and explain the adjustment in the preview rather than letting the user create a broken UI.

## Built-In Themes

v2 ships with 20 built-in presets. The exact names can change during implementation, but the set should cover these families:

- Aurora Blue
- Obsidian Cyan
- Deep Signal
- Arctic Glass
- Cobalt Pulse
- Neon Lime
- Acid Glass
- Emerald Voice
- Matrix Soft
- Prism Blue
- Prism Pink
- Violet Beam
- Magenta Glass
- Ember Wave
- Solar Trace
- Redline
- Graphite Ice
- Steel Whisper
- Mono Glass
- High Contrast

Every preset affects:

- main app window
- menu bar controls
- settings surfaces
- caption overlay
- hotkey recorder
- waveform/VU icon
- embedded engine web frame

## Waveform And VU Modes

v2 includes at least five waveform/VU types.

1. Bars: classic vertical VU bars. This is the default because it clearly communicates that the microphone is hearing the user.
2. Pulse Ring: circular breathing meter around the mic icon.
3. Spectrum Line: smooth EQ line for a quieter dashboard feel.
4. Orb Meter: glass orb that expands/contracts with input level.
5. Glyph Stream: animated letters or words flowing from the waveform icon.

Each waveform mode uses the active theme palette and motion intensity. The menu bar icon and caption overlay should both be able to reflect the selected VU mode.

## Caption-To-Cursor Commit Animation

v2 adds a themed commit animation for live typed streaming. When OmniVoice commits or updates provisional text, the caption overlay becomes the visible source and the caret or focused field becomes the destination.

The default commit animation is Glyph Stream:

- caption text breaks into small letters or word fragments
- fragments stream rapidly from the caption overlay toward the cursor
- fragments recombine as provisional or final inserted text
- the animation inherits the active theme color, glow, glass opacity, and motion intensity

Alternate commit animation presets:

- Beam Snap: caption collapses into a thin light beam and snaps into the cursor.
- Comet Collapse: caption compresses into a luminous streak and jumps to the cursor.
- None: disables the warp effect and uses a simple caption fade/scale.

Animation constraints:

- target duration is roughly 120-220 ms
- insertion must not wait for the animation to finish
- animation runs on provisional update commits and final replacement commits
- exact caret rectangle is preferred when macOS Accessibility exposes it
- focused text field or active window center is the fallback destination
- Reduce Motion uses the None behavior automatically
- unsupported target geometry falls back gracefully without blocking dictation

## App Shell And Embedded Engine Frame

OmniVoice remains a menu-bar app. The main window becomes a themed glass control center instead of a plain settings window.

The engine dashboard moves from a separate browser-first experience into an embedded app frame. The frame collapses from a user-selectable side: left or right. The default side is right because diagnostics and detail panels usually read better opposite the main settings/control area.

The embedded engine frame shows:

- engine health
- model downloads and updates
- transcripts
- event logs
- restart engine action
- copy diagnostics
- export links

The frame uses the same theme tokens as the native app. The Swift app sends generated CSS variables into the engine web view so the dashboard matches the active theme.

The app keeps an "Open in Browser" option for debugging. If the local engine is offline, the frame should show a native offline/restart panel instead of a dead web view.

## Live Translation

Live translation is bidirectional from day one and must run locally on the Mac. No cloud service and no LAN GPU server are part of v2's default design.

User flow:

- user enables Live Translation
- user chooses source language
- user chooses target language
- user chooses translation provider
- user chooses output mode

Output modes:

- Dictate translated text: source speech becomes target-language inserted text.
- Dual caption only: captions show source and target, but insertion remains original language.
- Bilingual insert: inserts source and target text together.

Provider strategy:

- Canary-1B V2 is the preferred research target for local speech translation if it can run acceptably on Apple Silicon.
- Fallback is ASR first, then local text translation.
- Parakeet remains the fast ASR path, not the translation engine.
- Canary-Qwen 2.5B remains an English ASR option, not the primary translation provider.

Model support evidence:

- NVIDIA NIM Canary documentation describes Canary as a multilingual encoder-decoder model that supports transcription and translation.
- NVIDIA ASR NIM model guidance lists Canary 1b as offline transcription plus bidirectional translation and lists Parakeet families primarily as transcription models.
- NVIDIA NeMo model guidance says Canary-Qwen 2.5B is for English ASR and directs translation use cases to Canary-1B V2.
- NVIDIA NeMo documents chunked/streaming Canary decoding for speech recognition and translation, which makes live translated captions a viable research path even if the first product implementation commits translation on hotkey release.

Capability reporting must be explicit:

- installed or missing
- supported directions
- release-only, caption-streaming, or live-insertion capable
- hardware or runtime limitation
- model download/update state

The first translation implementation should insert final translated text on hotkey release. Live translated captions can be experimental. Live translated insertion should wait until general live typing draft mode is stable.

## Live Typed Streaming

The live typed streaming design is speculative insertion with final replacement.

While the user holds the hotkey:

- the ASR stream produces partial text
- OmniVoice inserts a provisional draft into the target field
- each updated hypothesis replaces the previous provisional draft

When the user releases the hotkey:

- OmniVoice finalizes the transcript
- cleanup or translation runs
- the provisional range is replaced with the final cleaned output

This avoids duplicate words and lets the ASR revise earlier hypotheses. It also preserves v1's stronger final cleanup behavior.

If a target app does not expose reliable text range replacement through Accessibility, OmniVoice falls back to caption-only streaming and final insertion on release.

## Voice Operating Layer

v2 adds a voice operating layer on top of the v1 dictation workflow. These features are user-facing power tools, but they should be implemented as small, testable routing and action units rather than one large agent surface.

Selected v2 features:

- Per-app profiles: automatically switch style, model, theme, and insertion behavior based on the foreground app.
- Mode hotkeys: separate shortcuts for normal dictation, raw/code dictation, translation, command mode, and selected-text rewrite.
- Voice snippets: user-defined phrases such as "insert my signature" or "insert support reply" that expand into saved text or templates.
- Prompt presets and rewrite actions: user-defined transformations such as "make this a Slack reply", "format as email", "turn into a Jira ticket", or "make this a commit message".
- Selection command layer: select text anywhere, then dictate a transformation such as "make this shorter", "translate this to Spanish", or "turn this into bullets".
- Confidence and hearing quality UI: caption and waveform states show microphone level, silence, likely wrong input device, low ASR confidence, and fallback mode.
- Audio drop-in: drag an audio or video file into OmniVoice for local transcription, translation, cleanup, or summarization.
- Theme import/export: share custom theme JSON packs after the theme model is stable.

## AI Handoff And Foreground Context Actions

v2 adds optional AI handoff commands for users who connect external LLM providers. These commands are separate from local dictation and must be explicit because they can send foreground text or dictated instructions to a third-party API.

Example triggers:

- "Hey Claude, write a quick reply to Jane about how many people fly every day in the United States."
- "Ask OpenAI to summarize this email in one sentence."
- "Have OpenRouter take a look and rewrite this as a polite Slack message."
- "Read this email and write a response in Spanish telling them that we will not be coming."
- "Have Codex take a look at this error and explain the likely fix."

Invocation phrases such as "Hey Claude", "Ask Claude", "Ask OpenAI", "Have Codex take a look", or "Have OpenRouter take a look" are commands, not dictated content. They should be consumed by the router and excluded from the final inserted response.

The action router should parse:

- target provider
- foreground context policy
- requested action
- output destination
- confirmation requirement

Foreground context sources, in order:

1. selected text from the active app
2. focused text-field value
3. visible accessibility text in the active window
4. copied fallback text if direct Accessibility extraction fails
5. optional screenshot/OCR fallback if the user has granted screen recording permission

Context adapters should start generic and become app-aware over time. The first version can use macOS Accessibility APIs for selection, focused text, and visible text. Later adapters can add richer handling for Mail, Outlook, Slack, browsers, Claude Desktop, Codex, terminals, and IDEs where generic Accessibility text is incomplete.

Output destinations:

- insert response at cursor
- replace selected text
- append after selected text
- show preview in OmniVoice before insertion
- copy result to clipboard

The default for external LLM actions is preview-before-insert. Direct inline insertion can be a per-provider or per-action user preference.

Provider support:

- OpenAI: custom OpenAI API key and optional custom base URL. "Codex" can be a named OpenAI/Codex profile when an official API or local bridge path is available; OmniVoice should not scrape consumer session tokens.
- Anthropic Claude: API key or officially supported enterprise/workload authentication. Claude Desktop/Claude Code subscription OAuth is not the same as a general third-party app OAuth flow, so OmniVoice should only use it through documented local CLI/agent surfaces if the user deliberately enables that bridge.
- OpenRouter: API key and OAuth PKCE. OpenRouter's PKCE flow exchanges user authorization for a user-controlled API key, which fits a desktop "Connect OpenRouter" button well.
- GitHub Copilot: only through official supported SDK, CLI, MCP, extension, or API surfaces. GitHub's public Copilot direction increasingly exposes integrations through MCP, CLI, SDK, and official clients; OmniVoice should not depend on private Copilot endpoints.
- Custom OpenAI-compatible: user supplies base URL, API key, model id, and request style.

Provider setup UX:

- provider cards show Connected, Needs Key, Needs OAuth, Rate Limited, or Disabled
- credentials are stored in Keychain
- each provider declares whether it supports streaming, tool use, web retrieval, image input, long context, and local-only operation
- user can create named profiles such as "Claude Work", "OpenRouter Cheap", "OpenAI Fast", or "Local LM Studio"
- factual-response presets can require a provider with retrieval or citations; if unavailable, OmniVoice should preview the answer and warn that it is model-only text

Security and privacy rules:

- store credentials in Keychain
- show which provider receives each request
- allow per-provider history saving controls
- support Private Session mode that suppresses local transcript/action history
- never send foreground context unless the command explicitly asks for it or the action preset declares it
- require confirmation before sending large window extracts, files, or sensitive-looking content
- show a compact preview of the extracted context before the first send to a newly connected provider

Command examples:

- User says: "Hey Claude, write a quick reply to Jane about how many people fly every day in the United States."
- OmniVoice sends the task to the Claude profile without the invocation phrase.
- OmniVoice receives a response such as "Hi Jane, around 2.9 million passengers fly each day in the United States, depending on the dataset and time period."
- OmniVoice previews or inserts only the response text, not the command wrapper.

- User says: "Read this email and write a response in Spanish telling them that we will not be coming."
- OmniVoice extracts selected or visible foreground text, shows the extracted context if this is the first time for that app/provider, sends the context plus instruction, then inserts or previews the Spanish reply.

## Conversation Transcription And Speaker Labels

v2 adds a conversation transcription mode distinct from single-speaker push-to-talk dictation.

Use cases:

- record a meeting or phone call through a selected microphone
- identify speaker turns
- label speakers as Speaker 1, Speaker 2, etc.
- let the user rename labels to Joe, Mike, Jane, or another real name
- optionally infer names from the conversation when a speaker introduces themselves or another speaker addresses them
- produce transcript, summary, action items, and follow-up drafts

Important model distinction:

- base Parakeet TDT is an ASR model with timestamps; it should not be treated as the diarization engine by itself
- NVIDIA's model guidance points to Multitalker Parakeet Streaming for multi-speaker meeting transcription and Sortformer for "who spoke when" diarization
- OpenAI also exposes transcription models with diarization support, but that is an external API path and should only be used when the user has enabled external AI processing

Local-first conversation pipeline:

1. capture meeting audio
2. run voice activity detection and segmentation
3. run ASR with timestamps
4. run local diarization if a supported local diarization provider is installed
5. align diarization speaker turns with ASR words/segments
6. apply speaker-name inference as a post-process
7. let the user rename speakers and regenerate the formatted transcript

Conversation output:

- live caption mode shows the current speaker label when confidence is high enough
- transcript view stores speaker turns with timestamps, confidence, and source model
- rename speaker updates all matching turns without rewriting the words
- "infer names" is a separate post-process that can be rerun or cleared
- exported formats include plain text, Markdown, JSON, and SRT/VTT if timestamps are available

External-AI enhancement path:

- use an enabled LLM provider to improve speaker labels from conversational clues
- summarize the transcript
- extract action items
- write follow-up messages
- translate the transcript

The app should clearly separate diarization confidence from inferred real-world names. "Speaker 1" is a diarization label. "Joe" is an inferred or user-confirmed identity.

## External Reference Notes

These are design references, not implementation dependencies:

- NVIDIA NeMo model guidance lists Canary-1B V2 for multilingual transcription and translation, Parakeet-TDT V2/V3 for fast offline ASR, Multitalker Parakeet Streaming for multi-speaker meetings, and Sortformer for diarization.
- OpenAI's API authentication uses bearer API keys; OpenAI also lists GPT-4o Transcribe Diarize as a transcription model with built-in speaker diarization. "Codex" should be treated as an OpenAI/Codex profile only through official API or local bridge surfaces.
- Anthropic's Claude API supports API keys and workload identity; Claude Code subscription OAuth is documented for Claude Code/CLI workflows and should not be generalized into a consumer Claude OAuth integration unless Anthropic exposes that path.
- OpenRouter supports API-key authentication and OAuth PKCE that returns a user-controlled API key.
- GitHub's Copilot integration surface is moving through MCP, CLI, SDK, extensions, and official client paths. OmniVoice should integrate only with supported surfaces.

## Settings Model

v2 should add these preference groups:

- Appearance
- Theme Presets
- Custom Theme
- Caption Overlay
- Waveform/VU
- Commit Animation
- Engine Frame
- Translation
- Experimental Live Typing
- AI Providers
- AI Actions
- Voice Snippets
- Per-App Profiles
- Conversation Transcription
- Privacy

The model should remain serializable through the existing preferences store. New settings must have defaults so existing v1 users migrate without losing hotkeys, microphone selection, dictionary terms, or ASR provider choices.

## Engine/Web Theme Bridge

The native app owns the active theme. The web dashboard consumes CSS custom properties generated from that theme.

Initial variables:

- `--ov-accent`
- `--ov-accent-secondary`
- `--ov-bg`
- `--ov-surface`
- `--ov-surface-strong`
- `--ov-text`
- `--ov-muted`
- `--ov-border`
- `--ov-glow`
- `--ov-caption-bg`

The engine should remain usable in a standalone browser. If no theme is supplied by the native app, it uses the default blue/cyan theme.

## Error Handling

Theme errors:

- invalid custom colors fall back to the current preset
- low-contrast combinations trigger automatic contrast correction
- missing theme data falls back to the default theme
- unsupported commit animation geometry falls back to a simple fade/scale
- system Reduce Motion disables warp-style commit animations

Engine frame errors:

- offline engine shows native restart panel
- failed web frame load offers retry and open-in-browser
- theme bridge failure leaves dashboard on default theme

Translation errors:

- unsupported language pair is disabled in the picker
- missing model shows install action
- unsupported local runtime shows a clear disabled state
- translation failure falls back to original transcript only if the user has enabled fallback insertion

Live typing errors:

- unreliable target range replacement falls back to caption-only streaming
- final replacement failure copies final text to clipboard and shows recovery UI

AI handoff errors:

- missing provider credentials opens the matching provider card
- invalid or expired credentials mark the provider Needs Key or Needs OAuth without losing the dictated command
- foreground context extraction failure offers selection, clipboard, or screenshot/OCR fallback
- provider timeout leaves the original text untouched and preserves the pending command for retry
- unsupported output destination falls back to preview-before-insert
- external send blocked by Private Session explains that the provider action is disabled until Private Session is turned off or explicitly overridden

Conversation transcription errors:

- diarization model missing shows speaker labeling as unavailable while keeping ASR transcript capture enabled
- low diarization confidence marks turns as uncertain instead of pretending speaker labels are reliable
- overlapping speech that cannot be separated uses overlapping/unknown speaker tags
- speaker-name inference failure leaves generic speaker labels intact
- export failure leaves the transcript in history and offers copy-to-clipboard recovery

## Testing

Swift tests:

- theme token defaults
- custom accent derivation
- contrast correction
- preference migration
- waveform mode selection
- commit animation mode selection
- commit animation destination fallback
- engine frame side selection
- translation language-pair capability filtering
- live typing provisional range replacement logic
- AI command invocation stripping
- AI action routing by provider name
- foreground context source priority
- output destination selection
- Private Session suppression of local history and external actions
- conversation speaker rename propagation
- speaker-name inference can be cleared without changing transcript words

Python tests:

- model/provider capability schema
- translation provider status
- theme CSS variable endpoint or payload generation if implemented engine-side
- dashboard fallback to default theme
- AI provider capability schema
- AI provider credential status mapping
- AI action request schema
- conversation transcript record schema
- diarization capability status
- transcript export format generation

Runtime smoke checks:

- app launches as menu-bar accessory
- default blue theme renders in app
- caption overlay uses selected theme
- hotkey recorder uses selected theme
- engine frame opens on selected side
- dashboard still works in browser
- model status remains accurate
- connected provider can complete a preview-only AI action
- disabled provider produces recovery UI instead of inserting an error
- conversation transcription can record, label or gracefully omit speakers, and export a transcript

## Open Implementation Notes

The visual system should be implemented before live translation or AI handoff. Translation, AI actions, and conversation transcription remain in this spec so the settings model and provider capability model are shaped correctly, but they should not block the first theme/glass milestone.

Public distribution status is unchanged from v1: the local DMG is development-signed, while public release still requires Developer ID signing and notarization.
