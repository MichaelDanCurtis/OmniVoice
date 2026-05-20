# V2 Feature Surface Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move V2 features marked partial or planned into visible, testable app surfaces without destabilizing the working dictation path.

**Architecture:** Keep the local engine as the transcript/model source of truth, persist user-facing V2 configuration in `OmniVoicePreferences`, and expose the app UI as tabbed settings plus a non-resizing transcript drawer. Runtime-heavy features such as cursor-flight animation and LLM handoff stay explicitly tracked until their lower-level services are wired.

**Tech Stack:** Swift 6, SwiftUI/AppKit, OmniVoiceCore Codable models, FastAPI engine endpoints, XCTest, uv/pytest.

---

### Task 1: Persist Missing V2 Configuration

**Files:**
- Modify: `Tests/OmniVoiceCoreTests/PreferencesStoreTests.swift`
- Modify: `Sources/OmniVoiceCore/PreferencesStore.swift`
- Modify: `Sources/OmniVoiceApp/AppModel.swift`
- Modify: `Sources/OmniVoiceApp/SettingsView.swift`

- [x] **Step 1: Write failing tests**

Add assertions for custom STT model path, custom translation model path, translation source/target languages, translation enabled state, and OpenAI-compatible provider settings.

- [x] **Step 2: Run tests to verify failure**

Run: `swift test --filter PreferencesStoreTests`

- [x] **Step 3: Implement preferences and setters**

Add Codable fields with defaults and app model mutators.

- [x] **Step 4: Add Models, Translation, and Integrations controls**

Expose local model pickers, language controls, and OpenAI-compatible endpoint/API/model fields in tabs.

- [x] **Step 5: Run tests to verify pass**

Run: `swift test --filter PreferencesStoreTests`

### Task 2: Add App Transcript History

**Files:**
- Modify: `Tests/OmniVoiceCoreTests/EngineClientTests.swift`
- Modify: `Sources/OmniVoiceCore/EngineClient.swift`
- Modify: `Sources/OmniVoiceApp/AppModel.swift`
- Replace: `Sources/OmniVoiceApp/EngineFrameView.swift`
- Modify: `Sources/OmniVoiceApp/OmniVoiceApp.swift`

- [x] **Step 1: Write failing transcript decoding test**

Decode the `/api/transcripts` shape into a Swift model with cleaned/raw text and provider metadata.

- [x] **Step 2: Implement transcript model and fetch method**

Add `EngineTranscriptRecord` and `EngineClient.transcripts(limit:)`.

- [x] **Step 3: Load transcripts into `AppModel`**

Refresh history with engine status and expose a manual refresh action.

- [x] **Step 4: Replace resizing engine panel**

Use a fixed-width control window with a glass transcript drawer overlay that slides from the selected side without changing the main window width.

- [x] **Step 5: Add copy and insert actions**

Copy transcript text to pasteboard or insert at the current cursor through `AppDelegate`.

### Task 3: Consolidate Help And Capabilities

**Files:**
- Modify: `Sources/OmniVoiceApp/SettingsView.swift`
- Modify: `Sources/OmniVoiceApp/QuickReferenceView.swift`

- [x] **Step 1: Remove standalone Help tab**

Keep the main settings tabs focused and place capability education under Dictionary.

- [x] **Step 2: Add clickable capability cards**

Each capability opens a sheet with usage examples and current availability.

- [x] **Step 3: Preserve quick reference content**

Reuse current quick reference guidance inside capability details.

### Task 4: Restart Engine From App

**Files:**
- Modify: `Sources/OmniVoiceApp/EngineSupervisor.swift`
- Modify: `Sources/OmniVoiceApp/AppModel.swift`
- Modify: `Sources/OmniVoiceApp/SettingsView.swift`

- [x] **Step 1: Add restart method**

Stop an app-started engine process when present, clear start-attempt state, then call `startIfNeeded()`.

- [x] **Step 2: Expose action in Overview**

Add a Restart Engine button next to Refresh and Dashboard.

- [x] **Step 3: Refresh model/transcript state after restart**

Reload status, models, and transcripts after restart finishes.

### Task 5: Verify

**Files:**
- Read: entire modified diff

- [ ] **Step 1: Swift build**

Run: `swift build`

- [ ] **Step 2: Swift tests**

Run: `swift test`

- [ ] **Step 3: Engine tests**

Run: `cd engine && uv run pytest`

- [ ] **Step 4: Relaunch app**

Run: `script/build_and_run.sh --verify`

- [ ] **Step 5: Update feature map**

Mark completed surfaces in `docs/V2_FEATURE_GUI_MAP.md` and leave runtime-only gaps explicit.
