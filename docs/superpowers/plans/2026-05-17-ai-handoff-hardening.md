# AI Handoff Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Make AI handoff usable and safer by adding provider presets, a test connection button, Keychain-backed API key storage, and retry/copy/insert-original actions for failed AI requests.

**Architecture:** Keep provider preset and pending-command value types in `OmniVoiceCore` so they are testable. Keep the Keychain implementation and insertion retry actions in `OmniVoiceApp`, with `AppModel` owning UI state and `AppDelegate` owning cursor insertion.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Security/Keychain Services, XCTest, FastAPI route already added in the previous checkpoint.

---

### Task 1: Core Presets, Pending State, And Preference Cleanup

**Files:**
- Modify: `Tests/OmniVoiceCoreTests/PreferencesStoreTests.swift`
- Create: `Tests/OmniVoiceCoreTests/AIHandoffConfigurationTests.swift`
- Modify: `Sources/OmniVoiceCore/PreferencesStore.swift`
- Create: `Sources/OmniVoiceCore/AIHandoffConfiguration.swift`

- [x] **Step 1: Write failing tests**

Assert that preferences persist the selected AI preset but do not encode `open_ai_compatible_api_key`. Assert built-in presets exist for OpenRouter, LM Studio, Ollama, and Custom. Assert pending commands preserve target, prompt, context, and insert-original text.

- [x] **Step 2: Implement minimal code**

Add `AIProviderPresetID`, `AIProviderPreset`, `PendingAIHandoffCommand`, and `aiProviderPresetID` preference persistence. Remove API-key storage from `OmniVoicePreferences`.

- [x] **Step 3: Run focused tests**

Run: `swift test --filter AIHandoffConfigurationTests && swift test --filter PreferencesStoreTests`

### Task 2: Keychain Secret Storage And AppModel State

**Files:**
- Create: `Sources/OmniVoiceApp/KeychainSecretStore.swift`
- Modify: `Sources/OmniVoiceApp/AppModel.swift`
- Modify: `Sources/OmniVoiceApp/AppDelegate.swift`

- [x] **Step 1: Implement secret store**

Add a `SecretStore` protocol and `KeychainSecretStore` implementation. `AppModel` loads `openAICompatibleAPIKey` from the store, writes changes to Keychain, deletes the item when cleared, and uses this property for AI handoff requests.

- [x] **Step 2: Add AI test action**

Add `testAIHandoffConnection()` to `AppModel`, using the configured endpoint/model/key and a small fixed prompt. Set `lastTestResult` and `statusText` on success/failure.

### Task 3: UI Presets, Test Button, And Retry Actions

**Files:**
- Modify: `Sources/OmniVoiceApp/SettingsView.swift`
- Modify: `Sources/OmniVoiceApp/OmniVoiceApp.swift`
- Modify: `Sources/OmniVoiceApp/AppDelegate.swift`

- [x] **Step 1: Add controls**

In Settings -> Integrations, add provider preset buttons/menu, Test AI Connection, and pending failure actions: Retry, Copy Prompt, and Insert Original.

- [x] **Step 2: Wire actions**

Let retry reuse the current pending command and insertion target capture. Let copy write the prompt to pasteboard. Let insert original insert the original dictated command text at the current cursor.

### Task 4: Verification And Commit

**Files:**
- Modify docs if user-visible behavior changes need documentation.

- [x] **Step 1: Run verification**

Run: `swift test`, `uv run pytest`, `git diff --check`, and `script/build_and_run.sh --verify`.

- [x] **Step 2: Commit**

Stage only intended source/test/docs files and commit as `feat: harden ai handoff setup`.
