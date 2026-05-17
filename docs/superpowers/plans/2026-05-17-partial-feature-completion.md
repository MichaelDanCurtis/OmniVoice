# Partial Feature Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn finishable V2 partial features into working behavior and reclassify the remaining runtime/provider work as planned.

**Architecture:** Add a focused final-translation path that reuses the existing OpenAI-compatible engine client and app preferences. Keep ASR runtime swaps, local translation model execution, and native provider OAuth out of this pass because they need separate model/runtime work.

**Tech Stack:** SwiftUI/AppKit macOS app, OmniVoiceCore Swift client models, FastAPI engine, pytest, XCTest.

---

### Task 1: Engine Translation Route

**Files:**
- Modify: `engine/omnivoice_engine/schemas.py`
- Modify: `engine/omnivoice_engine/main.py`
- Test: `engine/tests/test_api.py`

- [ ] **Step 1: Write failing API tests**

Add tests proving `/api/translate` posts an OpenAI-compatible chat request, validates endpoint/model configuration, and records upstream failures.

- [ ] **Step 2: Run failing API tests**

Run: `cd engine && uv run pytest tests/test_api.py -k translate`
Expected: fail because `/api/translate` does not exist yet.

- [ ] **Step 3: Implement the route**

Add `TranslationRequest`, `TranslationResponse`, a translation prompt helper, and a `POST /api/translate` route that returns only translated text.

- [ ] **Step 4: Run API tests**

Run: `cd engine && uv run pytest tests/test_api.py -k translate`
Expected: pass.

### Task 2: Swift Translation Contract

**Files:**
- Modify: `Sources/OmniVoiceCore/Models.swift`
- Modify: `Sources/OmniVoiceCore/EngineClient.swift`
- Test: `Tests/OmniVoiceCoreTests/EngineClientTests.swift`

- [ ] **Step 1: Write failing Swift contract tests**

Add encoder/decoder tests for `TranslationRequest` and `TranslationResult`.

- [ ] **Step 2: Run failing Swift tests**

Run: `swift test --filter EngineClientTests`
Expected: fail because the translation models do not exist yet.

- [ ] **Step 3: Implement client support**

Add translation request/result models and `EngineClient.translate(_:)`.

- [ ] **Step 4: Run Swift contract tests**

Run: `swift test --filter EngineClientTests`
Expected: pass.

### Task 3: App Final Translation

**Files:**
- Modify: `Sources/OmniVoiceApp/AppDelegate.swift`
- Modify: `Sources/OmniVoiceApp/SettingsView.swift`

- [ ] **Step 1: Wire release-time translation**

After cleanup and command/rewrite handling, translate the final text when live translation is enabled and the OpenAI-compatible endpoint/model are configured. If translation is unavailable or fails, insert the original text and show a clear status.

- [ ] **Step 2: Update UI copy**

Make the Translation and Models tabs honest: AI-provider final translation is implemented, local model runtime selection is planned.

### Task 4: Feature Map Cleanup

**Files:**
- Modify: `docs/V2_FEATURE_GUI_MAP.md`

- [ ] **Step 1: Remove misleading partial statuses**

Mark translation as implemented for AI-provider final translation. Move Canary runtime, external STT runtime routing, external local translation runtime, and native OAuth integrations to planned.

### Task 5: Verification and Commit

**Files:**
- All modified files above.

- [ ] **Step 1: Run focused checks**

Run: `cd engine && uv run pytest tests/test_api.py -k translate`
Run: `swift test --filter EngineClientTests`

- [ ] **Step 2: Run full checks**

Run: `swift test`
Run: `uv run pytest`
Run: `git diff --check`
Run: `script/build_and_run.sh --verify`

- [ ] **Step 3: Commit scoped changes**

Stage only the plan, source, tests, and docs from this pass. Do not stage `.serena/project.yml` or `engine/uv.lock`.
