# AI Handoff MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add an OpenAI-compatible AI handoff path so explicit dictated commands like "Ask Claude..." send the request to a configured LLM endpoint and insert only the model's response at the cursor.

**Architecture:** Command parsing stays in `OmniVoiceCore`, runtime insertion stays in `AppDelegate`, and network execution is delegated to the local engine. The first implementation uses an OpenAI-compatible chat-completions route with user-configured base URL, API key, and model; OAuth providers remain planned integration surfaces.

**Tech Stack:** Swift/SwiftUI app, XCTest, FastAPI, Pydantic, urllib-based OpenAI-compatible HTTP calls, pytest.

---

### Task 1: Command Parser And Preferences

**Files:**
- Modify: `Tests/OmniVoiceCoreTests/DictationCommandParserTests.swift`
- Modify: `Tests/OmniVoiceCoreTests/PreferencesStoreTests.swift`
- Modify: `Sources/OmniVoiceCore/DictationCommandParser.swift`
- Modify: `Sources/OmniVoiceCore/PreferencesStore.swift`

- [x] **Step 1: Write failing tests**

Add tests that parse `Ask Claude ...`, `Hey Codex ...`, `Have OpenRouter take a look ...`, and reject ordinary prose. Add preferences assertions for `openAICompatibleAPIKey` default, encoding, old-preference decoding, and round trip.

- [x] **Step 2: Run failing tests**

Run: `swift test --filter DictationCommandParserTests && swift test --filter PreferencesStoreTests`

Expected: compile or assertion failure because AI handoff types and API key preference do not exist yet.

- [x] **Step 3: Implement minimal code**

Add `AIHandoffTarget` and `.aiHandoff(target:prompt:)`, parse only explicit invocation prefixes, and add persisted `openAICompatibleAPIKey` with backward-compatible decode defaults.

- [x] **Step 4: Verify green**

Run: `swift test --filter DictationCommandParserTests && swift test --filter PreferencesStoreTests`

Expected: both test suites pass.

### Task 2: Engine Route And Client

**Files:**
- Modify: `engine/omnivoice_engine/schemas.py`
- Modify: `engine/omnivoice_engine/main.py`
- Modify: `engine/tests/test_api.py`
- Modify: `Sources/OmniVoiceCore/EngineClient.swift`
- Modify: `Tests/OmniVoiceCoreTests/EngineClientTests.swift`

- [x] **Step 1: Write failing tests**

Add engine tests for `POST /api/ai/handoff` success, missing endpoint validation, and upstream failure without real network calls. Add Swift encode/decode tests for `AIHandoffRequest` and `AIHandoffResult`.

- [x] **Step 2: Run failing tests**

Run: `uv run pytest tests/test_api.py -q && swift test --filter EngineClientTests`

Expected: failures because the route and Swift models do not exist yet.

- [x] **Step 3: Implement minimal code**

Add Pydantic request/response models, an OpenAI-compatible chat-completions helper, a FastAPI route, event logging, and Swift client structs/method.

- [x] **Step 4: Verify green**

Run: `uv run pytest tests/test_api.py -q && swift test --filter EngineClientTests`

Expected: tests pass without external network access.

### Task 3: App Integration And Settings

**Files:**
- Modify: `Sources/OmniVoiceApp/AppModel.swift`
- Modify: `Sources/OmniVoiceApp/AppDelegate.swift`
- Modify: `Sources/OmniVoiceApp/SettingsView.swift`
- Modify: `docs/OMNIVOICE_QUICK_REFERENCE.md`
- Modify: `docs/INTEGRATIONS.md`

- [x] **Step 1: Implement app glue**

Add an API-key setter, expose a secure field in Integrations, and handle `.aiHandoff` commands in `AppDelegate` by sending selected context plus prompt to the engine and inserting the response at the current target.

- [x] **Step 2: Verify build**

Run: `swift test`

Expected: Swift build and all tests pass.

- [x] **Step 3: Update user docs**

Document the OpenAI-compatible endpoint setup and voice phrases. Make clear OAuth-specific integrations are planned, not active.

### Task 4: Full Verification And Checkpoint

**Files:**
- No new source files expected.

- [x] **Step 1: Run full checks**

Run: `swift test`, `uv run pytest`, `git diff --check`, and `script/build_and_run.sh --verify`.

- [x] **Step 2: Commit**

Stage only the AI handoff source/test/docs files and commit as `feat: add openai-compatible ai handoff`.
