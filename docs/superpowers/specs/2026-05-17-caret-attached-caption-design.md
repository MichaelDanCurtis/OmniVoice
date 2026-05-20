# Caret-Attached Caption Design

## Goal

OmniVoice should avoid corrupting rich composer state, such as Codex plugin chips, by rendering live dictation in an overlay anchored near the caret and inserting only the final cleaned text with a paste-style commit.

## Behavior

- When dictation starts, OmniVoice captures the focused text target, selected range, app identity, and best available caret bounds.
- If caret bounds are available, the caption appears near the insertion point instead of the saved bottom caption location.
- If caret bounds are unavailable, the existing draggable bottom caption behavior remains the fallback.
- Rich/tokenized composers use pasteboard insertion for final text and do not use direct `AXValue` rewriting.
- Plain text fields may continue using direct Accessibility insertion and optional live draft behavior.
- The commit animation shrinks/fades toward the captured caret when available, otherwise it uses the current overlay-centered animation.

## Rich Composer Policy

Codex-style rich composers are not safe for direct full-value rewrites because Accessibility can expose UI tokens, plugin chips, mention chips, or placeholders as plain text. OmniVoice should treat these apps as pasteboard-only targets for final insertion:

- Codex
- Claude
- ChatGPT
- Slack
- Microsoft Teams
- common browser-hosted rich composers

This policy can expand over time as app-specific behavior is observed.

## Testing

- Unit test rich composer detection for Codex-style app names and bundle identifiers.
- Unit test plain native targets still default to direct Accessibility insertion.
- Unit test caret-anchored overlay placement chooses above-caret placement when space is available and clamps inside the visible screen.
- Keep the existing text insertion sanitizer tests unchanged.
