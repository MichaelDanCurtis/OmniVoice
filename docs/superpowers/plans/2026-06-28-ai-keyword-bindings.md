# AI keyword bindings + AI-tab reorg — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every spoken keyword ("ask Claude", "ask AI") map to exactly one configured provider — API, OAuth, or agent — all routed through the Ask bubble; reorganize the AI settings tab; remove the unused MCP section.

**Architecture:** A keyword→target binding model + pure resolver live in `OmniVoiceCore` (unit-tested). `AskController` becomes the single router: agent targets stream via the CLI, text-LLM targets call the engine `aiHandoff`, both feed the same bubble. The AI tab is regrouped into API / OAuth / Agent sections with a keyword-binding editor in Voice Patterns. MCP is removed.

**Tech Stack:** Swift 6, SwiftPM, AppKit + SwiftUI, XCTest.

## Global Constraints

- Swift tools 6.0; platform macOS 14. New pure logic in `OmniVoiceCore` with XCTest coverage in `Tests/OmniVoiceCoreTests`.
- `AskTarget` is modeled as a struct `{ kind, id }` (synthesized Codable) — NOT an enum with associated values (avoids custom Codable).
- Removing a persisted preferences field must keep old saved JSON decodable (unknown keys are ignored; new optional fields use `decodeIfPresent`).
- Follow existing `OmniVoicePreferences` Codable style (explicit `CodingKeys` + `ConvertedCodingKeys`, two `init(from:)` decode sites, `decodeIfPresent ?? default`) and the `customAgents`/`mcpServers` field wiring as the analog.
- Sentence-case UI text. Commit after every task. Run the full `swift test` before each commit.

---

### Task 1: `AskTarget` + `AskKeywordBinding`

**Files:**
- Create: `Sources/OmniVoiceCore/AskKeywordBinding.swift`
- Test: `Tests/OmniVoiceCoreTests/AskKeywordBindingTests.swift`

**Interfaces:**
- Produces: `AskTargetKind` (enum `.textLLM`/`.agent`, String-Codable), `AskTarget` (struct `{ kind: AskTargetKind, id: String }`), `AskKeywordBinding` (struct `{ id: String, keyword: String, target: AskTarget }`). `id` holds a `TextLLMProviderKind.rawValue` for `.textLLM`, or a built-in agent id / `AgentConfiguration.id` for `.agent`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import OmniVoiceCore

final class AskKeywordBindingTests: XCTestCase {
    func testBindingRoundTripsThroughCodable() throws {
        let b = AskKeywordBinding(id: "1", keyword: "claude",
            target: AskTarget(kind: .agent, id: "claude"))
        let data = try JSONEncoder().encode(b)
        XCTAssertEqual(try JSONDecoder().decode(AskKeywordBinding.self, from: data), b)
    }

    func testTextLLMTargetCarriesProviderID() {
        let t = AskTarget(kind: .textLLM, id: "anthropic")
        XCTAssertEqual(t.kind, .textLLM)
        XCTAssertEqual(t.id, "anthropic")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AskKeywordBindingTests`
Expected: FAIL — types undefined.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public enum AskTargetKind: String, Codable, Equatable, Sendable {
    case textLLM
    case agent
}

public struct AskTarget: Codable, Equatable, Sendable {
    public var kind: AskTargetKind
    public var id: String
    public init(kind: AskTargetKind, id: String) { self.kind = kind; self.id = id }
}

public struct AskKeywordBinding: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var keyword: String
    public var target: AskTarget
    public init(id: String, keyword: String, target: AskTarget) {
        self.id = id; self.keyword = keyword; self.target = target
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AskKeywordBindingTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/OmniVoiceCore/AskKeywordBinding.swift Tests/OmniVoiceCoreTests/AskKeywordBindingTests.swift
git commit -m "feat(askai): AskKeywordBinding + AskTarget model"
```

---

### Task 2: `AskKeywordResolver`

**Files:**
- Create: `Sources/OmniVoiceCore/AskKeywordResolver.swift`
- Test: `Tests/OmniVoiceCoreTests/AskKeywordResolverTests.swift`

**Interfaces:**
- Consumes: `AskKeywordBinding`, `AskTarget`.
- Produces: `enum AskKeywordResolver { static func resolve(_ keyword: String, in bindings: [AskKeywordBinding]) -> AskTarget? }` (case-insensitive, trimmed; first match wins).

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import OmniVoiceCore

final class AskKeywordResolverTests: XCTestCase {
    let bindings = [
        AskKeywordBinding(id: "1", keyword: "claude", target: AskTarget(kind: .agent, id: "claude")),
        AskKeywordBinding(id: "2", keyword: "ai", target: AskTarget(kind: .textLLM, id: "custom")),
    ]

    func testResolvesCaseInsensitivelyAndTrimmed() {
        XCTAssertEqual(AskKeywordResolver.resolve("  Claude ", in: bindings),
                       AskTarget(kind: .agent, id: "claude"))
        XCTAssertEqual(AskKeywordResolver.resolve("AI", in: bindings),
                       AskTarget(kind: .textLLM, id: "custom"))
    }

    func testReturnsNilWhenUnbound() {
        XCTAssertNil(AskKeywordResolver.resolve("frank", in: bindings))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AskKeywordResolverTests`
Expected: FAIL — `AskKeywordResolver` undefined.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public enum AskKeywordResolver {
    public static func resolve(_ keyword: String, in bindings: [AskKeywordBinding]) -> AskTarget? {
        let needle = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return bindings.first {
            $0.keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == needle
        }?.target
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AskKeywordResolverTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/OmniVoiceCore/AskKeywordResolver.swift Tests/OmniVoiceCoreTests/AskKeywordResolverTests.swift
git commit -m "feat(askai): AskKeywordResolver (keyword -> target)"
```

---

### Task 3: Persist `askKeywordBindings` with seeded defaults

**Files:**
- Modify: `Sources/OmniVoiceCore/PreferencesStore.swift`
- Test: `Tests/OmniVoiceCoreTests/PreferencesStoreTests.swift` (append)

**Interfaces:**
- Produces: `OmniVoicePreferences.askKeywordBindings: [AskKeywordBinding]`, `static let defaultAskKeywordBindings: [AskKeywordBinding]`.

- [ ] **Step 1: Write the failing test** (append)

```swift
func testDefaultsSeedAskKeywordBindings() {
    let kws = OmniVoicePreferences.defaults.askKeywordBindings.map(\.keyword)
    XCTAssertEqual(kws, ["ai", "claude", "gemini"])
    let ai = OmniVoicePreferences.defaults.askKeywordBindings.first { $0.keyword == "ai" }
    XCTAssertEqual(ai?.target.kind, .textLLM)
    let claude = OmniVoicePreferences.defaults.askKeywordBindings.first { $0.keyword == "claude" }
    XCTAssertEqual(claude?.target, AskTarget(kind: .agent, id: "claude"))
}

func testOldPreferencesWithoutBindingsDecodeToSeededDefaults() throws {
    let json = """
    { "asr_provider": "parakeet-tdt-mlx", "style": "neutral", "dictionary_terms": [],
      "microphone_id": null, "dictation_hotkey": { "key_code": 49, "modifiers": 2304 },
      "style_hotkey": { "key_code": 1, "modifiers": 2304 } }
    """.data(using: .utf8)!
    let prefs = try EngineCoding.decoder.decode(OmniVoicePreferences.self, from: json)
    XCTAssertEqual(prefs.askKeywordBindings.map(\.keyword), ["ai", "claude", "gemini"])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PreferencesStoreTests`
Expected: FAIL — no member `askKeywordBindings`.

- [ ] **Step 3: Write minimal implementation**

Add the static default near `OmniVoicePreferences`'s other statics:
```swift
    public static let defaultAskKeywordBindings: [AskKeywordBinding] = [
        AskKeywordBinding(id: "seed-ai", keyword: "ai",
            target: AskTarget(kind: .textLLM, id: TextLLMProviderKind.custom.rawValue)),
        AskKeywordBinding(id: "seed-claude", keyword: "claude",
            target: AskTarget(kind: .agent, id: "claude")),
        AskKeywordBinding(id: "seed-gemini", keyword: "gemini",
            target: AskTarget(kind: .agent, id: "gemini")),
    ]
```
Then wire `askKeywordBindings` exactly like `customAgents` (mirror every site): stored property after `customAgents`; `defaults` call `askKeywordBindings: OmniVoicePreferences.defaultAskKeywordBindings,`; memberwise `init` param `askKeywordBindings: [AskKeywordBinding] = OmniVoicePreferences.defaultAskKeywordBindings,` + body `self.askKeywordBindings = askKeywordBindings`; `CodingKeys` `case askKeywordBindings = "ask_keyword_bindings"`; `ConvertedCodingKeys` `case askKeywordBindings`; **both** decode sites `askKeywordBindings: try container.decodeIfPresent([AskKeywordBinding].self, forKey: .askKeywordBindings) ?? OmniVoicePreferences.defaultAskKeywordBindings,`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PreferencesStoreTests`
Expected: PASS (existing + 2 new).

- [ ] **Step 5: Commit**

```bash
git add Sources/OmniVoiceCore/PreferencesStore.swift Tests/OmniVoiceCoreTests/PreferencesStoreTests.swift
git commit -m "feat(askai): persist askKeywordBindings with seeded defaults"
```

---

### Task 4: Drop "ask <name>" prefixes from `DictationCommandParser`

The binding keywords now own "ask &lt;keyword&gt;". Keep only the "have ai take a look" selection-style handoff in the parser.

**Files:**
- Modify: `Sources/OmniVoiceCore/DictationCommandParser.swift` (`parseAIHandoff`)
- Test: `Tests/OmniVoiceCoreTests/DictationCommandParserTests.swift` (append; create if absent)

**Interfaces:**
- Produces: `DictationCommandParser.parse("ask claude …")` returns `nil` (no longer an aiHandoff command); `parse("have ai take a look …")` still returns `.aiHandoff(target: .custom, …)`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import OmniVoiceCore

final class AskHandoffParsingTests: XCTestCase {
    func testAskNameIsNoLongerAHandoffCommand() {
        XCTAssertNil(DictationCommandParser.parse("ask claude what rhymes with bill"))
    }
    func testHaveAITakeALookStillHandsOff() {
        let cmd = DictationCommandParser.parse("have ai take a look at this")
        guard case .aiHandoff(let target, _)? = cmd?.action else { return XCTFail() }
        XCTAssertEqual(target, .custom)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AskHandoffParsingTests`
Expected: FAIL — "ask claude" still parses to a handoff.

- [ ] **Step 3: Write minimal implementation**

In `parseAIHandoff`, delete the `for target in AIHandoffTarget.allCases { … aiPrefixes(for: target) … }` loop and the `"ask ai"`/`"hey ai"` entries; keep only the selection-style prefixes:
```swift
    private static func parseAIHandoff(_ text: String) -> DictationCommand? {
        guard !text.isEmpty else { return nil }
        for prefix in ["have ai take a look", "have the ai take a look"] {
            if let prompt = prompt(after: prefix, in: text) {
                return DictationCommand(action: .aiHandoff(target: .custom, prompt: prompt),
                                        displayText: "Asking AI")
            }
        }
        return nil
    }
```
(Leave `AIHandoffTarget`, `aiPrefixes`, and `.aiHandoff` otherwise intact — they remain the transport for `.custom`.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AskHandoffParsingTests` then `swift test`
Expected: PASS; full suite green (fix/remove any existing parser tests that asserted "ask claude" → handoff).

- [ ] **Step 5: Commit**

```bash
git add Sources/OmniVoiceCore/DictationCommandParser.swift Tests/OmniVoiceCoreTests/DictationCommandParserTests.swift
git commit -m "feat(askai): keyword bindings own 'ask <name>'; parser keeps only 'have ai take a look'"
```

---

### Task 5: Remove MCP (UI + model)

**Files:**
- Modify/Remove: `Sources/OmniVoiceCore/PreferencesStore.swift` (mcpServers property, defaults, init, CodingKeys×2, decode×2, `setMCPServer`/`removeMCPServer`), `Sources/OmniVoiceCore/Models.swift` (`MCPServerConfiguration`, `MCPEnvironmentVariable`, `normalizedTextLLMConfigurations` only if MCP-coupled — leave LLM code), `Sources/OmniVoiceApp/AppModel.swift` (`addMCPServer`/`setMCPServer`/`removeMCPServer`), `Sources/OmniVoiceApp/SettingsView.swift` (the `Section("MCP Servers")` block + `mcpServerCard` + helpers)
- Tests: remove MCP cases from `Tests/OmniVoiceCoreTests/PreferencesStoreTests.swift` and `ModelsTests.swift`

**Interfaces:**
- Produces: no `mcpServers` anywhere; old prefs JSON with `mcp_servers` still decodes (key ignored).

- [ ] **Step 1: Enumerate every reference**

Run: `grep -rnE "mcpServers|mcp_servers|MCPServer|MCPEnvironmentVariable|addMCPServer|setMCPServer|removeMCPServer|mcpServerCard" Sources Tests`
Record the full list — every hit must be removed or its enclosing test deleted.

- [ ] **Step 2: Remove the model + preference field**

Delete `MCPServerConfiguration` and `MCPEnvironmentVariable` from `Models.swift`. In `PreferencesStore.swift` delete the `mcpServers` stored property, its `defaults` entry, its `init` param + body line, its `CodingKeys` + `ConvertedCodingKeys` cases, both `decodeIfPresent` decode lines, and the `setMCPServer`/`removeMCPServer` methods. (Removing the key means old `mcp_servers` JSON is ignored on decode — that is the intended back-compat.)

- [ ] **Step 3: Remove app + UI references**

Delete `addMCPServer`/`setMCPServer`/`removeMCPServer` from `AppModel.swift`; delete the `Section("MCP Servers")` block, `mcpServerCard`, and any MCP-only helpers from `SettingsView.swift`. Delete MCP test methods from `PreferencesStoreTests.swift` and `ModelsTests.swift`.

- [ ] **Step 4: Build + test green**

Run: `swift build && swift test`
Expected: Build complete; full suite green; `grep -rn "MCPServer\|mcpServers" Sources` returns nothing.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(askai): remove unused MCP settings (UI + preference model)"
```

---

### Task 6: `AskController` unified dispatch (agent + text-LLM → bubble)

**Files:**
- Modify: `Sources/OmniVoiceApp/AskController.swift`

**Interfaces:**
- Consumes: `AskKeywordResolver`, `AskTarget`, `AgentRegistry`, `AgentRunner`, `AskPromptBuilder`, `AskBubbleWindow`, `TextInsertionService`, `EngineClient.aiHandoff`, `OmniVoicePreferences.textLLMConfiguration(for:)`.
- Produces: `AskController.init(insertion:engineClient:)`, `func updateConfiguration(_ prefs: OmniVoicePreferences)`, unchanged `func handle(transcript:captureTarget:) -> Bool`.

- [ ] **Step 1: Replace `updateAgents` with `updateConfiguration` and add text-LLM dispatch**

Store `private var bindings: [AskKeywordBinding] = []`, `private var preferences = OmniVoicePreferences.defaults`, `private let engineClient: EngineClient`. New init:
```swift
init(insertion: TextInsertionService, engineClient: EngineClient) {
    self.insertion = insertion
    self.engineClient = engineClient
    bubble.onInsert = { [weak self] in self?.insertAnswer() }
    bubble.onCopy = { [weak self] in self?.copyAnswer() }
    bubble.onDismiss = { [weak self] in self?.dismiss() }
}

func updateConfiguration(_ prefs: OmniVoicePreferences) {
    preferences = prefs
    bindings = prefs.askKeywordBindings
    registry = AgentRegistry(custom: prefs.customAgents)
}
```
Change `handle` to use bound keywords + resolver:
```swift
func handle(transcript: String, captureTarget: TextInsertionService.Target?) -> Bool {
    let keywords = bindings.map(\.keyword)
    switch AskAICommandParser.parse(transcript, knownKeywords: keywords, bubbleOpen: bubbleOpen) {
    case .ask(let keyword, let question):
        guard let target = AskKeywordResolver.resolve(keyword, in: bindings) else { return false }
        history = []
        activeTarget = target
        activeKeyword = keyword
        capturedTarget = captureTarget
        ask(target: target, question: question)
        return true
    case .followUp(let question):
        guard let target = activeTarget else { return false }
        ask(target: target, question: question)
        return true
    case .action(.insert): insertAnswer(); return true
    case .action(.copy): copyAnswer(); return true
    case .action(.dismiss): dismiss(); return true
    case .none: return false
    }
}
```
Add `private var activeTarget: AskTarget?` and `private var activeKeyword = ""`. Replace `ask(agent:question:)` with a target-dispatching `ask`:
```swift
private func ask(target: AskTarget, question: String) {
    switch target.kind {
    case .agent:
        guard let agent = registry.all.first(where: { $0.id == target.id }) else {
            bubbleOpen = true
            bubble.show(question: question, agentName: "Agent")
            bubble.showError("Agent \"\(target.id)\" is no longer configured.")
            return
        }
        askAgent(agent, question: question)
    case .textLLM:
        askTextLLM(providerID: target.id, question: question)
    }
}
```
Keep the existing streaming body as `askAgent(_:question:)` (the previous `ask(agent:question:)` renamed). Add the text-LLM path:
```swift
private func askTextLLM(providerID: String, question: String) {
    guard let kind = TextLLMProviderKind(rawValue: providerID) else { return }
    let config = preferences.textLLMConfiguration(for: kind)
    bubbleOpen = true
    lastAnswer = ""
    bubble.show(question: question, agentName: kind.displayName)
    guard config.isConfigured else {
        bubble.showError("Configure \(kind.displayName) in Settings → AI.")
        return
    }
    let prompt = AskPromptBuilder.build(history: history, question: question)
    history.append(AskTurn(role: .user, text: question))
    runToken += 1; let token = runToken
    Task { @MainActor in
        do {
            let result = try await engineClient.aiHandoff(AIHandoffRequest(
                prompt: prompt, provider: config.provider.rawValue,
                baseURL: config.resolvedBaseURL, model: config.trimmedModel,
                apiKey: config.trimmedAPIKey, transport: config.transport,
                oauthAccessToken: config.trimmedOAuthAccessToken,
                headers: config.resolvedHeaders, context: ""))
            guard runToken == token else { return }
            let text = TextInsertionEdit.sanitizedInsertionText(result.text)
            bubble.setStreaming(false)
            bubble.appendAnswer(text)
            lastAnswer = text.trimmingCharacters(in: .whitespacesAndNewlines)
            history.append(AskTurn(role: .assistant, text: lastAnswer))
        } catch {
            guard runToken == token else { return }
            bubble.showError("\(kind.displayName) failed: \(error.localizedDescription)")
        }
    }
}
```
(Match the exact `AIHandoffRequest` parameter labels to `handleAIHandoff` in `AppDelegate.swift` — copy them verbatim.)

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 3: Commit**

```bash
git add Sources/OmniVoiceApp/AskController.swift
git commit -m "feat(askai): AskController routes agent + text-LLM keywords through the bubble"
```

---

### Task 7: Wire `AppDelegate` to the unified controller

**Files:**
- Modify: `Sources/OmniVoiceApp/AppDelegate.swift`

**Interfaces:**
- Consumes: `AskController.init(insertion:engineClient:)`, `updateConfiguration(_:)`.

- [ ] **Step 1: Update construction + config refresh**

Change the property to `private lazy var askController = AskController(insertion: insertionService, engineClient: engineClient)`. In `attach(model:)` replace `askController.updateAgents(model.preferences.customAgents)` with `askController.updateConfiguration(model.preferences)`, and change the `onCustomAgentsChanged` wiring to refresh on any preference change that affects bindings — set `model.onCustomAgentsChanged = { [weak self, weak model] _ in guard let model else { return }; self?.askController.updateConfiguration(model.preferences) }` and also call `askController.updateConfiguration(model.preferences)` after the bindings editor saves (Task 8 calls a model method that triggers this).

- [ ] **Step 2: Build + manual smoke**

Run: `swift build`, then `./script/build_and_run.sh`. Say "ask claude …" (agent → bubble streams) and bind a keyword to an API provider, say "ask &lt;that&gt; …" (engine → bubble shows answer). Confirm both Insert with `I`.

- [ ] **Step 3: Commit**

```bash
git add Sources/OmniVoiceApp/AppDelegate.swift
git commit -m "feat(askai): wire AppDelegate to unified AskController (engine + bindings)"
```

---

### Task 8: AI tab reorg + keyword-binding editor

**Files:**
- Modify: `Sources/OmniVoiceApp/SettingsView.swift`, `Sources/OmniVoiceApp/AppModel.swift`

**Interfaces:**
- Consumes: `model.preferences.askKeywordBindings`, `TextLLMProviderConfiguration.authMode`, `AgentRegistry.defaultBuiltIns`, `model.preferences.customAgents`.
- Produces: AppModel `addKeywordBinding(_:)`, `updateKeywordBinding(_:)`, `removeKeywordBinding(id:)` (persist + `onCustomAgentsChanged?` to refresh the controller).

- [ ] **Step 1: AppModel mutators** (mirror the custom-agent mutators added earlier)

```swift
func addKeywordBinding(_ binding: AskKeywordBinding) {
    preferences.askKeywordBindings.append(binding)
    guard persistPreferences() else { return }
    onCustomAgentsChanged?(preferences.customAgents)
}
func updateKeywordBinding(_ binding: AskKeywordBinding) {
    if let i = preferences.askKeywordBindings.firstIndex(where: { $0.id == binding.id }) {
        preferences.askKeywordBindings[i] = binding
    }
    guard persistPreferences() else { return }
    onCustomAgentsChanged?(preferences.customAgents)
}
func removeKeywordBinding(id: String) {
    preferences.askKeywordBindings.removeAll { $0.id == id }
    guard persistPreferences() else { return }
    onCustomAgentsChanged?(preferences.customAgents)
}
```

- [ ] **Step 2: Split provider sections by authMode**

In the text-LLM settings body, replace the single `Section("Text LLM Providers")` with two sections driven by `authMode`:
```swift
Section("API configurations") {
    ForEach(visibleTextLLMProviders.filter {
        model.preferences.textLLMConfiguration(for: $0).authMode == .apiKey
    }, id: \.self) { textLLMProviderCard($0) }
}
Section("OAuth configurations") {
    ForEach(visibleTextLLMProviders.filter {
        model.preferences.textLLMConfiguration(for: $0).authMode == .oauth
    }, id: \.self) { textLLMProviderCard($0) }
}
```
Rename the existing "Ask AI agents" section to `Section("Agent configurations")` and ensure it renders immediately after OAuth. (The MCP section is already gone from Task 5.)

- [ ] **Step 3: Keyword-binding editor in Voice Patterns**

Replace the static `CapabilityMiniRow` hints in `Section("Voice Patterns")` with an editor over `model.preferences.askKeywordBindings`, plus an Add button. Each row: a keyword `TextField` (commits via `model.updateKeywordBinding`) and a provider `Picker` whose options are every selectable provider (API + OAuth `TextLLMProviderKind` + built-in agents + `customAgents`), each tagged with its `AskTarget`:
```swift
ForEach(model.preferences.askKeywordBindings) { binding in
    KeywordBindingRow(binding: binding, options: providerOptions,
        onChange: { model.updateKeywordBinding($0) },
        onRemove: { model.removeKeywordBinding(id: binding.id) })
}
Button("Add keyword") {
    model.addKeywordBinding(AskKeywordBinding(id: UUID().uuidString, keyword: "",
        target: providerOptions.first?.target ?? AskTarget(kind: .agent, id: "claude")))
}
```
Add `providerOptions: [(label: String, target: AskTarget)]` (computed in the view) and a small `KeywordBindingRow` view (TextField + Picker(selection bound to the option whose `target == binding.target`) + Remove). Picker selection writes a new `AskKeywordBinding` with the chosen `target` back through `onChange`.

- [ ] **Step 4: Build + manual test**

Run: `swift build`, then `./script/build_and_run.sh`. Open Settings → AI: confirm **API configurations / OAuth configurations / Agent configurations** order, **no MCP** section, and a **keyword editor** in Voice Patterns. Add a keyword, bind it to an API provider, point a built-in keyword at the API provider instead of the agent, and confirm via voice that routing follows the binding.

- [ ] **Step 5: Commit**

```bash
git add Sources/OmniVoiceApp/SettingsView.swift Sources/OmniVoiceApp/AppModel.swift
git commit -m "feat(askai): AI tab reorg (API/OAuth/Agent) + keyword-binding editor"
```

---

## Self-review

- **Spec coverage:** AskTarget/binding (T1), resolver (T2), persisted bindings + defaults (T3), parser cleanup (T4), MCP removal (T5), unified dispatch incl. text-LLM-in-bubble (T6), AppDelegate wiring (T7), reorg + editor (T8). All spec sections covered.
- **Types consistent:** `AskTarget{kind,id}`, `AskKeywordBinding{id,keyword,target}`, `AskKeywordResolver.resolve`, `AskController.init(insertion:engineClient:)`/`updateConfiguration(_:)`, AppModel `add/update/removeKeywordBinding` used identically across tasks.
- **Note for executor:** copy the `AIHandoffRequest` initializer labels verbatim from `AppDelegate.handleAIHandoff` (Task 6) — they are the source of truth for that call.
