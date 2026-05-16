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

Python tests:

- model/provider capability schema
- translation provider status
- theme CSS variable endpoint or payload generation if implemented engine-side
- dashboard fallback to default theme

Runtime smoke checks:

- app launches as menu-bar accessory
- default blue theme renders in app
- caption overlay uses selected theme
- hotkey recorder uses selected theme
- engine frame opens on selected side
- dashboard still works in browser
- model status remains accurate

## Open Implementation Notes

The visual system should be implemented before live translation. Translation remains in this spec so the settings model and provider capability model are shaped correctly, but it should not block the first theme/glass milestone.

Public distribution status is unchanged from v1: the local DMG is development-signed, while public release still requires Developer ID signing and notarization.
