# Caret-Attached Caption Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Anchor live captions near the active caret and use pasteboard-only insertion for Codex-style rich composers.

**Architecture:** Add a small core insertion target policy and extend existing caption placement with caret anchoring. AppKit code captures caret bounds from Accessibility and routes rich composer targets away from direct `AXValue` rewriting.

**Tech Stack:** Swift 6, SwiftPM, AppKit Accessibility APIs, XCTest.

---

### Task 1: Core Policy And Placement Tests

**Files:**
- Create: `Sources/OmniVoiceCore/TextInsertionTargetPolicy.swift`
- Modify: `Sources/OmniVoiceCore/CaptionOverlayPlacement.swift`
- Create: `Tests/OmniVoiceCoreTests/TextInsertionTargetPolicyTests.swift`
- Modify: `Tests/OmniVoiceCoreTests/CaptionOverlayPlacementTests.swift`

- [ ] Write failing tests for Codex-style rich composer policy and caret placement.
- [ ] Run focused tests and confirm failure.
- [ ] Implement `TextInsertionStrategy` plus `TextInsertionTargetPolicy`.
- [ ] Add `CaptionOverlayPlacement.caretAnchoredOrigin`.
- [ ] Run focused tests and confirm pass.

### Task 2: AppKit Capture And Routing

**Files:**
- Modify: `Sources/OmniVoiceApp/TextInsertionService.swift`
- Modify: `Sources/OmniVoiceApp/AppDelegate.swift`

- [ ] Add `Target.insertionStrategy` and `Target.caretFrame`.
- [ ] Capture caret bounds through `AXBoundsForRange`.
- [ ] Disable live draft for pasteboard-only rich composer targets.
- [ ] Route final pasteboard-only targets through pasteboard insertion before direct AX rewrite.
- [ ] Pass captured caret frame into listening, transcript, error, and commit overlay calls.

### Task 3: Overlay Window Anchoring

**Files:**
- Modify: `Sources/OmniVoiceApp/CaptionOverlayWindow.swift`

- [ ] Extend `show` with an optional `anchorFrame`.
- [ ] Use `CaptionOverlayPlacement.caretAnchoredOrigin` when an anchor exists.
- [ ] Prevent programmatic caret anchoring from overwriting the saved draggable caption center.
- [ ] Animate commit toward the anchor frame when available.

### Task 4: Verification

**Files:**
- Verify all changed files.

- [ ] Run `swift test`.
- [ ] Run `cd engine && uv run pytest`.
- [ ] Run `git diff --check`.
- [ ] Run `script/build_and_run.sh --verify`.
- [ ] Commit the implementation if verification passes.
