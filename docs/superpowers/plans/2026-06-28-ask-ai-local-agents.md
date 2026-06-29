# Ask AI via local agent CLIs — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Answer voice questions by calling a locally installed, already-authenticated agent CLI (Claude/Gemini first) and stream the answer into a liquid-glass bubble the user can insert at the cursor.

**Architecture:** Pure logic (descriptors, registry, command parsing, prompt building, config) lives in `OmniVoiceCore` and is fully unit-tested. The app layer (`OmniVoiceApp`) adds a thin process runner, a non-activating key-panel bubble, the dictation routing, and the settings UI. Conversation is OmniVoice-managed: each turn re-sends thread history as a one-shot prompt (no ACP). v1 uses plain-text output read incrementally from the pipe.

**Tech Stack:** Swift 6, SwiftPM, AppKit + SwiftUI, `Foundation.Process`, XCTest.

## Global Constraints

- Swift tools 6.0; platform macOS 14.
- The spoken prompt is passed as a discrete `argv` element or on stdin — **never** interpolated into a shell string; no `sh -c`.
- New pure logic goes in `OmniVoiceCore` with XCTest coverage in `Tests/OmniVoiceCoreTests`.
- Follow existing patterns: `OmniVoicePreferences` Codable style (explicit `CodingKeys`, `decodeIfPresent` for new optional fields), overlay windows modeled on `CaptionOverlayWindow` (borderless `.nonactivatingPanel`, `.floating`, clear background).
- Sentence-case UI text. Commit after every task.

---

### Task 1: `AgentDescriptor` + invocation rendering

**Files:**
- Create: `Sources/OmniVoiceCore/AgentDescriptor.swift`
- Test: `Tests/OmniVoiceCoreTests/AgentDescriptorTests.swift`

**Interfaces:**
- Produces: `AgentDescriptor` (struct), `AgentStreamFormat` (enum `.plainText`), `AgentInvocation` (`.args([String])` where the literal token `"{prompt}"` is replaced by the prompt as one argv element, or `.stdin([String])` where args are fixed and the prompt is written to stdin). `func render(prompt: String) -> (args: [String], stdin: String?)`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import OmniVoiceCore

final class AgentDescriptorTests: XCTestCase {
    func testArgsTemplateReplacesPromptAsSingleArgument() {
        let d = AgentDescriptor(
            id: "claude", displayName: "Claude", keywords: ["claude"],
            binaryName: "claude",
            invocation: .args(["-p", "{prompt}"]),
            streamFormat: .plainText
        )
        let r = d.render(prompt: "rhymes with bill; rm -rf /")
        XCTAssertEqual(r.args, ["-p", "rhymes with bill; rm -rf /"])
        XCTAssertNil(r.stdin)
    }

    func testStdinModeSendsPromptOnStdinNotArgs() {
        let d = AgentDescriptor(
            id: "x", displayName: "X", keywords: ["x"], binaryName: "x",
            invocation: .stdin(["chat"]), streamFormat: .plainText
        )
        let r = d.render(prompt: "hello")
        XCTAssertEqual(r.args, ["chat"])
        XCTAssertEqual(r.stdin, "hello")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AgentDescriptorTests`
Expected: FAIL — `AgentDescriptor` is not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public enum AgentStreamFormat: String, Codable, Equatable, Sendable {
    case plainText
}

public enum AgentInvocation: Equatable, Sendable {
    case args([String])    // "{prompt}" token replaced by the prompt argument
    case stdin([String])   // fixed args; prompt written to stdin
}

public struct AgentDescriptor: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let keywords: [String]
    public let binaryName: String          // resolved on PATH unless binaryPath set
    public let binaryPath: String?
    public let invocation: AgentInvocation
    public let streamFormat: AgentStreamFormat

    public init(id: String, displayName: String, keywords: [String],
                binaryName: String, binaryPath: String? = nil,
                invocation: AgentInvocation, streamFormat: AgentStreamFormat) {
        self.id = id; self.displayName = displayName; self.keywords = keywords
        self.binaryName = binaryName; self.binaryPath = binaryPath
        self.invocation = invocation; self.streamFormat = streamFormat
    }

    public func render(prompt: String) -> (args: [String], stdin: String?) {
        switch invocation {
        case .args(let template):
            return (template.map { $0 == "{prompt}" ? prompt : $0 }, nil)
        case .stdin(let args):
            return (args, prompt)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AgentDescriptorTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/OmniVoiceCore/AgentDescriptor.swift Tests/OmniVoiceCoreTests/AgentDescriptorTests.swift
git commit -m "feat(askai): AgentDescriptor with injection-safe invocation rendering"
```

---

### Task 2: `AgentConfiguration` (persisted custom agent)

**Files:**
- Modify: `Sources/OmniVoiceCore/AgentDescriptor.swift` (append)
- Test: `Tests/OmniVoiceCoreTests/AgentConfigurationTests.swift`

**Interfaces:**
- Consumes: `AgentDescriptor`, `AgentInvocation`, `AgentStreamFormat`.
- Produces: `AgentConfiguration` (Codable value persisted in preferences) with `func descriptor() -> AgentDescriptor`. Fields: `id`, `displayName`, `keyword`, `binaryPath`, `argsTemplate: [String]` (advanced; default `["{prompt}"]`), `usesStdin: Bool`, `streamFormat`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import OmniVoiceCore

final class AgentConfigurationTests: XCTestCase {
    func testConfigurationMapsToDescriptor() {
        let c = AgentConfiguration(
            id: "glm", displayName: "GLM", keyword: "glm",
            binaryPath: "/Users/me/.glm/bin/glm",
            argsTemplate: ["chat", "{prompt}"], usesStdin: false,
            streamFormat: .plainText
        )
        let d = c.descriptor()
        XCTAssertEqual(d.keywords, ["glm"])
        XCTAssertEqual(d.binaryPath, "/Users/me/.glm/bin/glm")
        XCTAssertEqual(d.render(prompt: "hi").args, ["chat", "hi"])
    }

    func testConfigurationRoundTripsThroughCodable() throws {
        let c = AgentConfiguration(id: "glm", displayName: "GLM", keyword: "glm",
            binaryPath: "/x", argsTemplate: ["{prompt}"], usesStdin: true,
            streamFormat: .plainText)
        let data = try JSONEncoder().encode(c)
        XCTAssertEqual(try JSONDecoder().decode(AgentConfiguration.self, from: data), c)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AgentConfigurationTests`
Expected: FAIL — `AgentConfiguration` undefined.

- [ ] **Step 3: Write minimal implementation** (append to `AgentDescriptor.swift`)

```swift
public struct AgentConfiguration: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var keyword: String
    public var binaryPath: String
    public var argsTemplate: [String]   // contains "{prompt}" unless usesStdin
    public var usesStdin: Bool
    public var streamFormat: AgentStreamFormat

    public init(id: String, displayName: String, keyword: String, binaryPath: String,
                argsTemplate: [String] = ["{prompt}"], usesStdin: Bool = false,
                streamFormat: AgentStreamFormat = .plainText) {
        self.id = id; self.displayName = displayName; self.keyword = keyword
        self.binaryPath = binaryPath; self.argsTemplate = argsTemplate
        self.usesStdin = usesStdin; self.streamFormat = streamFormat
    }

    public func descriptor() -> AgentDescriptor {
        AgentDescriptor(
            id: id, displayName: displayName, keywords: [keyword.lowercased()],
            binaryName: (binaryPath as NSString).lastPathComponent, binaryPath: binaryPath,
            invocation: usesStdin ? .stdin(argsTemplate) : .args(argsTemplate),
            streamFormat: streamFormat
        )
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AgentConfigurationTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/OmniVoiceCore/AgentDescriptor.swift Tests/OmniVoiceCoreTests/AgentConfigurationTests.swift
git commit -m "feat(askai): AgentConfiguration persisted custom-agent model"
```

---

### Task 3: Persist `customAgents` in `OmniVoicePreferences`

**Files:**
- Modify: `Sources/OmniVoiceCore/PreferencesStore.swift` (stored property, `defaults`, memberwise `init`, `CodingKeys`, decode with `decodeIfPresent`)
- Test: `Tests/OmniVoiceCoreTests/PreferencesStoreTests.swift` (append)

**Interfaces:**
- Produces: `OmniVoicePreferences.customAgents: [AgentConfiguration]` (default `[]`).

- [ ] **Step 1: Write the failing test** (append to `PreferencesStoreTests`)

```swift
func testDefaultsHaveNoCustomAgents() {
    XCTAssertEqual(OmniVoicePreferences.defaults.customAgents, [])
}

func testCustomAgentsRoundTripThroughStore() throws {
    let suiteName = "OmniVoicePreferencesStoreTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = PreferencesStore(userDefaults: defaults)
    var prefs = OmniVoicePreferences.defaults
    prefs.customAgents = [AgentConfiguration(id: "glm", displayName: "GLM",
        keyword: "glm", binaryPath: "/x")]
    try store.save(prefs)
    XCTAssertEqual(try store.load().customAgents, prefs.customAgents)
}

func testOldPreferencesWithoutCustomAgentsDecodeToEmpty() throws {
    let json = """
    { "asr_provider": "parakeet-tdt-mlx", "style": "neutral", "dictionary_terms": [],
      "microphone_id": null, "dictation_hotkey": { "key_code": 49, "modifiers": 2304 },
      "style_hotkey": { "key_code": 1, "modifiers": 2304 } }
    """.data(using: .utf8)!
    let prefs = try EngineCoding.decoder.decode(OmniVoicePreferences.self, from: json)
    XCTAssertEqual(prefs.customAgents, [])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PreferencesStoreTests`
Expected: FAIL — no member `customAgents`.

- [ ] **Step 3: Write minimal implementation**

In `OmniVoicePreferences`: add stored property near the other arrays:
```swift
    public var customAgents: [AgentConfiguration]
```
Add to `defaults` initializer call: `customAgents: [],`
Add to the memberwise `init` signature: `customAgents: [AgentConfiguration] = [],`
and body: `self.customAgents = customAgents`
Add to `CodingKeys`: `case customAgents = "custom_agents"`
In `init(from:)` (back-compatible): `self.customAgents = try container.decodeIfPresent([AgentConfiguration].self, forKey: .customAgents) ?? []`
In `encode(to:)`: `try container.encode(customAgents, forKey: .customAgents)`

(Match the exact placement/style of the neighboring `mcpServers` field.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PreferencesStoreTests`
Expected: PASS (existing + 3 new).

- [ ] **Step 5: Commit**

```bash
git add Sources/OmniVoiceCore/PreferencesStore.swift Tests/OmniVoiceCoreTests/PreferencesStoreTests.swift
git commit -m "feat(askai): persist customAgents in preferences (back-compatible)"
```

---

### Task 4: `AgentRegistry` (built-ins + custom, keyword resolution)

**Files:**
- Create: `Sources/OmniVoiceCore/AgentRegistry.swift`
- Test: `Tests/OmniVoiceCoreTests/AgentRegistryTests.swift`

**Interfaces:**
- Consumes: `AgentDescriptor`, `AgentConfiguration`.
- Produces: `AgentRegistry(builtIns:custom:)`, `static let defaultBuiltIns: [AgentDescriptor]` (v1: Claude, Gemini), `func resolve(keyword: String) -> AgentDescriptor?` (case-insensitive), `var all: [AgentDescriptor]`, `let defaultAgentID: String`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import OmniVoiceCore

final class AgentRegistryTests: XCTestCase {
    func testResolvesBuiltInKeywordCaseInsensitively() {
        let r = AgentRegistry(custom: [])
        XCTAssertEqual(r.resolve(keyword: "Claude")?.id, "claude")
        XCTAssertEqual(r.resolve(keyword: "gemini")?.id, "gemini")
        XCTAssertNil(r.resolve(keyword: "nope"))
    }

    func testCustomAgentKeywordResolves() {
        let r = AgentRegistry(custom: [AgentConfiguration(id: "glm",
            displayName: "GLM", keyword: "glm", binaryPath: "/x")])
        XCTAssertEqual(r.resolve(keyword: "glm")?.binaryPath, "/x")
    }

    func testBuiltInsUsePlainTextForV1() {
        for d in AgentRegistry.defaultBuiltIns { XCTAssertEqual(d.streamFormat, .plainText) }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AgentRegistryTests`
Expected: FAIL — `AgentRegistry` undefined.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public struct AgentRegistry {
    public static let defaultBuiltIns: [AgentDescriptor] = [
        AgentDescriptor(id: "claude", displayName: "Claude", keywords: ["claude"],
            binaryName: "claude", invocation: .args(["-p", "{prompt}"]), streamFormat: .plainText),
        AgentDescriptor(id: "gemini", displayName: "Gemini", keywords: ["gemini"],
            binaryName: "gemini", invocation: .args(["{prompt}"]), streamFormat: .plainText),
    ]
    public static let defaultAgentID = "claude"

    private let descriptors: [AgentDescriptor]
    public init(builtIns: [AgentDescriptor] = AgentRegistry.defaultBuiltIns,
                custom: [AgentConfiguration]) {
        self.descriptors = builtIns + custom.map { $0.descriptor() }
    }

    public var all: [AgentDescriptor] { descriptors }

    public func resolve(keyword: String) -> AgentDescriptor? {
        let k = keyword.lowercased()
        return descriptors.first { $0.keywords.contains(k) }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AgentRegistryTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/OmniVoiceCore/AgentRegistry.swift Tests/OmniVoiceCoreTests/AgentRegistryTests.swift
git commit -m "feat(askai): AgentRegistry with built-in + custom keyword resolution"
```

---

### Task 5: `AskAICommandParser` (voice grammar)

**Files:**
- Create: `Sources/OmniVoiceCore/AskAICommandParser.swift`
- Test: `Tests/OmniVoiceCoreTests/AskAICommandParserTests.swift`

**Interfaces:**
- Produces: `enum AskAIIntent { case ask(keyword: String, question: String); case followUp(String); case action(AskAIAction); case none }`, `enum AskAIAction { case insert, copy, dismiss }`, and `AskAICommandParser.parse(_ transcript: String, knownKeywords: [String], bubbleOpen: Bool) -> AskAIIntent`.

Rules: leading "ask &lt;keyword&gt; &lt;rest&gt;" with a known keyword → `.ask`. When `bubbleOpen`: "copy that"/"insert that"/"copy"/"insert" → `.action(.insert)` (insert is the default copy verb); "copy to clipboard" → `.action(.copy)`; "dismiss"/"never mind"/"close that" → `.action(.dismiss)`; any other transcript → `.followUp(transcript)`. When not open and no "ask" prefix → `.none`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import OmniVoiceCore

final class AskAICommandParserTests: XCTestCase {
    let kws = ["claude", "gemini"]

    func testAskPrefixExtractsAgentAndQuestion() {
        let i = AskAICommandParser.parse("ask Claude how many names rhyme with Bill",
            knownKeywords: kws, bubbleOpen: false)
        guard case let .ask(k, q) = i else { return XCTFail() }
        XCTAssertEqual(k, "claude")
        XCTAssertEqual(q, "how many names rhyme with Bill")
    }

    func testUnknownAgentIsNotAnAskWhenClosed() {
        XCTAssertEqual(AskAICommandParser.parse("ask Frank a question",
            knownKeywords: kws, bubbleOpen: false), .none)
    }

    func testActionsRecognizedWhileBubbleOpen() {
        XCTAssertEqual(AskAICommandParser.parse("copy that", knownKeywords: kws, bubbleOpen: true),
            .action(.insert))
        XCTAssertEqual(AskAICommandParser.parse("copy to clipboard", knownKeywords: kws, bubbleOpen: true),
            .action(.copy))
        XCTAssertEqual(AskAICommandParser.parse("never mind", knownKeywords: kws, bubbleOpen: true),
            .action(.dismiss))
    }

    func testPlainTranscriptWhileOpenIsFollowUp() {
        XCTAssertEqual(AskAICommandParser.parse("how many have the first name Jack",
            knownKeywords: kws, bubbleOpen: true), .followUp("how many have the first name Jack"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AskAICommandParserTests`
Expected: FAIL — types undefined.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public enum AskAIAction: Equatable, Sendable { case insert, copy, dismiss }

public enum AskAIIntent: Equatable, Sendable {
    case ask(keyword: String, question: String)
    case followUp(String)
    case action(AskAIAction)
    case none
}

public enum AskAICommandParser {
    public static func parse(_ transcript: String, knownKeywords: [String],
                             bubbleOpen: Bool) -> AskAIIntent {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if lower.hasPrefix("ask ") {
            let rest = trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces)
            if let space = rest.firstIndex(of: " ") {
                let keyword = String(rest[..<space]).lowercased()
                let question = String(rest[rest.index(after: space)...])
                    .trimmingCharacters(in: .whitespaces)
                if knownKeywords.contains(keyword), !question.isEmpty {
                    return .ask(keyword: keyword, question: question)
                }
            }
        }

        guard bubbleOpen else { return .none }

        switch lower {
        case "copy to clipboard", "copy this to clipboard":
            return .action(.copy)
        case "copy that", "copy this", "insert that", "insert this", "copy", "insert":
            return .action(.insert)
        case "dismiss", "never mind", "nevermind", "close that", "close this":
            return .action(.dismiss)
        default:
            return .followUp(trimmed)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AskAICommandParserTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/OmniVoiceCore/AskAICommandParser.swift Tests/OmniVoiceCoreTests/AskAICommandParserTests.swift
git commit -m "feat(askai): voice command parser for ask/follow-up/actions"
```

---

### Task 6: `AskPromptBuilder` (thread → one-shot prompt)

**Files:**
- Create: `Sources/OmniVoiceCore/AskPromptBuilder.swift`
- Test: `Tests/OmniVoiceCoreTests/AskPromptBuilderTests.swift`

**Interfaces:**
- Produces: `struct AskTurn { let role: Role; let text: String }` (`enum Role { case user, assistant }`), `AskPromptBuilder.build(history: [AskTurn], question: String, maxTurns: Int = 12) -> String`. Output = a fixed system preamble, then the last `maxTurns` turns rendered as `User:`/`Assistant:` lines, then the new `User:` question. The preamble instructs: answer concisely in plain text, do not use tools or read files.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import OmniVoiceCore

final class AskPromptBuilderTests: XCTestCase {
    func testBuildsPreambleHistoryAndQuestion() {
        let p = AskPromptBuilder.build(
            history: [AskTurn(role: .user, text: "names like Bill"),
                      AskTurn(role: .assistant, text: "Bill, Will, Jill")],
            question: "how about Jack")
        XCTAssertTrue(p.contains("plain text"))
        XCTAssertTrue(p.contains("do not use tools"))
        XCTAssertTrue(p.contains("User: names like Bill"))
        XCTAssertTrue(p.contains("Assistant: Bill, Will, Jill"))
        XCTAssertTrue(p.hasSuffix("User: how about Jack"))
    }

    func testTrimsToLastMaxTurns() {
        let history = (0..<40).map { AskTurn(role: .user, text: "q\($0)") }
        let p = AskPromptBuilder.build(history: history, question: "now", maxTurns: 4)
        XCTAssertFalse(p.contains("q0"))
        XCTAssertTrue(p.contains("q39"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AskPromptBuilderTests`
Expected: FAIL — types undefined.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public enum AskRole: Sendable { case user, assistant }
public struct AskTurn: Equatable, Sendable {
    public let role: AskRole; public let text: String
    public init(role: AskRole, text: String) { self.role = role; self.text = text }
}

public enum AskPromptBuilder {
    static let preamble = """
    You are a quick-answer assistant inside a dictation app. Answer concisely in \
    plain text. Do not use tools, run commands, or read files — just answer.
    """

    public static func build(history: [AskTurn], question: String, maxTurns: Int = 12) -> String {
        let recent = history.suffix(maxTurns)
        var lines = [preamble, ""]
        for t in recent {
            lines.append("\(t.role == .user ? "User" : "Assistant"): \(t.text)")
        }
        lines.append("User: \(question)")
        return lines.joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AskPromptBuilderTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/OmniVoiceCore/AskPromptBuilder.swift Tests/OmniVoiceCoreTests/AskPromptBuilderTests.swift
git commit -m "feat(askai): prompt builder for stateless multi-turn context"
```

---

### Task 7: `ExecutableResolver` (find CLI binaries off the GUI PATH)

**Files:**
- Create: `Sources/OmniVoiceApp/ExecutableResolver.swift`
- Test: `Tests/OmniVoiceAppTests/ExecutableResolverTests.swift` (create target dir if needed)

**Interfaces:**
- Produces: `enum ExecutableResolver { static func resolve(_ descriptor: AgentDescriptor) -> String? }` — returns `binaryPath` if set and executable; else runs `"$SHELL" -lc "command -v <binaryName>"` and returns the trimmed path if it exists; caches results in a static dictionary.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import OmniVoiceApp
import OmniVoiceCore

final class ExecutableResolverTests: XCTestCase {
    func testReturnsExplicitBinaryPathWhenExecutable() {
        let d = AgentDescriptor(id: "x", displayName: "X", keywords: ["x"],
            binaryName: "x", binaryPath: "/bin/echo",
            invocation: .args(["{prompt}"]), streamFormat: .plainText)
        XCTAssertEqual(ExecutableResolver.resolve(d), "/bin/echo")
    }

    func testResolvesKnownBinaryViaLoginShell() {
        let d = AgentDescriptor(id: "ls", displayName: "ls", keywords: ["ls"],
            binaryName: "ls", invocation: .args(["{prompt}"]), streamFormat: .plainText)
        XCTAssertNotNil(ExecutableResolver.resolve(d))   // ls is on the login PATH
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ExecutableResolverTests`
Expected: FAIL — `ExecutableResolver` undefined (and target may need creating — add `.testTarget(name: "OmniVoiceAppTests", dependencies: ["OmniVoiceApp"])` to `Package.swift` if not present, plus the `OmniVoiceApp` target must be importable; if the executable target can't be imported, move `ExecutableResolver` into a thin testable file and keep the test minimal).

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation
import OmniVoiceCore

enum ExecutableResolver {
    private static var cache: [String: String] = [:]

    static func resolve(_ descriptor: AgentDescriptor) -> String? {
        if let p = descriptor.binaryPath, FileManager.default.isExecutableFile(atPath: p) { return p }
        if let hit = cache[descriptor.binaryName] { return hit }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = ["-lc", "command -v \(descriptor.binaryName)"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !out.isEmpty, FileManager.default.isExecutableFile(atPath: out) else { return nil }
        cache[descriptor.binaryName] = out
        return out
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ExecutableResolverTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/OmniVoiceApp/ExecutableResolver.swift Tests/OmniVoiceAppTests/ExecutableResolverTests.swift
git commit -m "feat(askai): resolve agent CLIs off the login-shell PATH"
```

---

### Task 8: `AgentRunner` (spawn + stream stdout)

**Files:**
- Create: `Sources/OmniVoiceApp/AgentRunner.swift`
- Test: `Tests/OmniVoiceAppTests/AgentRunnerTests.swift`

**Interfaces:**
- Produces: `protocol AgentRunning { func run(_ descriptor: AgentDescriptor, prompt: String, onChunk: @escaping @Sendable (String) -> Void) async throws -> String }` and `struct AgentRunner: AgentRunning`. Errors: `enum AgentRunError: Error { case notFound, failed(String) }`. Streams stdout chunks to `onChunk` as they arrive (plain text), returns full output; non-zero exit → `.failed(stderr)`; unresolved binary → `.notFound`.

- [ ] **Step 1: Write the failing test** (uses `/bin/cat`-style behavior via a fake descriptor pointing at `printf`)

```swift
import XCTest
@testable import OmniVoiceApp
import OmniVoiceCore

final class AgentRunnerTests: XCTestCase {
    func testStreamsStdoutAndReturnsFullOutput() async throws {
        // echo writes the prompt to stdout; binaryPath set so resolver returns it.
        let d = AgentDescriptor(id: "echo", displayName: "echo", keywords: ["echo"],
            binaryName: "echo", binaryPath: "/bin/echo",
            invocation: .args(["{prompt}"]), streamFormat: .plainText)
        var chunks = ""
        let out = try await AgentRunner().run(d, prompt: "hello world") { chunks += $0 }
        XCTAssertEqual(out.trimmingCharacters(in: .whitespacesAndNewlines), "hello world")
        XCTAssertTrue(chunks.contains("hello world"))
    }

    func testUnresolvedBinaryThrowsNotFound() async {
        let d = AgentDescriptor(id: "nope", displayName: "nope", keywords: ["nope"],
            binaryName: "definitely-not-a-real-binary-xyz",
            invocation: .args(["{prompt}"]), streamFormat: .plainText)
        do { _ = try await AgentRunner().run(d, prompt: "x") { _ in }; XCTFail() }
        catch AgentRunError.notFound {} catch { XCTFail("wrong error: \(error)") }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AgentRunnerTests`
Expected: FAIL — types undefined.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation
import OmniVoiceCore

enum AgentRunError: Error, Equatable { case notFound, failed(String) }

protocol AgentRunning: Sendable {
    func run(_ descriptor: AgentDescriptor, prompt: String,
             onChunk: @escaping @Sendable (String) -> Void) async throws -> String
}

struct AgentRunner: AgentRunning {
    func run(_ descriptor: AgentDescriptor, prompt: String,
             onChunk: @escaping @Sendable (String) -> Void) async throws -> String {
        guard let path = ExecutableResolver.resolve(descriptor) else { throw AgentRunError.notFound }
        let rendered = descriptor.render(prompt: prompt)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = rendered.args
        let outPipe = Pipe(); let errPipe = Pipe()
        process.standardOutput = outPipe; process.standardError = errPipe
        if let stdin = rendered.stdin {
            let inPipe = Pipe(); process.standardInput = inPipe
            inPipe.fileHandleForWriting.write(Data(stdin.utf8))
            inPipe.fileHandleForWriting.closeFile()
        }

        let collected = OutputBox()
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let s = String(data: data, encoding: .utf8) else { return }
            collected.append(s); onChunk(s)
        }

        try process.run()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in c.resume() }
        }
        outPipe.fileHandleForReading.readabilityHandler = nil

        if process.terminationStatus != 0 {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                             encoding: .utf8) ?? "exit \(process.terminationStatus)"
            throw AgentRunError.failed(err.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return collected.value
    }
}

private final class OutputBox: @unchecked Sendable {
    private let lock = NSLock(); private var s = ""
    func append(_ x: String) { lock.lock(); s += x; lock.unlock() }
    var value: String { lock.lock(); defer { lock.unlock() }; return s }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AgentRunnerTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/OmniVoiceApp/AgentRunner.swift Tests/OmniVoiceAppTests/AgentRunnerTests.swift
git commit -m "feat(askai): AgentRunner spawns CLI and streams stdout"
```

---

### Task 9: Ask bubble (non-activating key panel + view)

**Files:**
- Create: `Sources/OmniVoiceApp/AskBubbleWindow.swift`
- Manual test (no unit test — AppKit window): build + visual check

**Interfaces:**
- Produces: `@MainActor final class AskBubbleWindow` with `func show(question:)`, `func appendAnswer(_:)`, `func setStreaming(_:)`, `func showError(_:)`, `func hide()`, and callbacks `onInsert`, `onCopy`, `onDismiss`, `onFollowUpKey`. Internally an `NSPanel` subclass that overrides `canBecomeKey = true` and is created with `[.borderless, .nonactivatingPanel]`, `.floating`, clear background — mirror `CaptionOverlayWindow`. A local key monitor (or `keyDown`) maps `i`→onInsert, `c`→onCopy, `d`/Esc→onDismiss, Return→onInsert.

- [ ] **Step 1: Implement the panel** (model on `CaptionOverlayWindow.swift`; reuse its glass styling helpers)

```swift
import AppKit
import SwiftUI
import OmniVoiceCore

@MainActor
final class AskBubbleWindow {
    var onInsert: (() -> Void)?
    var onCopy: (() -> Void)?
    var onDismiss: (() -> Void)?

    private var panel: KeyablePanel?
    private let model = AskBubbleViewModel()

    func show(question: String, agentName: String) {
        model.question = question; model.agentName = agentName
        model.answer = ""; model.streaming = true; model.error = nil
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        positionCenteredNearTop(panel)
    }
    func appendAnswer(_ s: String) { model.answer += s }
    func setStreaming(_ on: Bool) { model.streaming = on }
    func showError(_ msg: String) { model.streaming = false; model.error = msg }
    func hide() { panel?.orderOut(nil) }

    private func makePanel() -> KeyablePanel {
        let p = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .floating; p.isOpaque = false; p.backgroundColor = .clear
        p.hasShadow = true
        p.onKey = { [weak self] key in
            switch key {
            case .insert: self?.onInsert?()
            case .copy: self?.onCopy?()
            case .dismiss: self?.onDismiss?()
            }
        }
        p.contentView = NSHostingView(rootView: AskBubbleView(model: model))
        return p
    }

    private func positionCenteredNearTop(_ p: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        p.setFrameOrigin(NSPoint(x: f.midX - p.frame.width / 2, y: f.maxY - p.frame.height - 80))
    }
}

final class KeyablePanel: NSPanel {
    enum Key { case insert, copy, dismiss }
    var onKey: ((Key) -> Void)?
    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onKey?(.dismiss)                 // esc
        case 36, 76: onKey?(.insert)              // return / enter
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "i": onKey?(.insert)
            case "c": onKey?(.copy)
            case "d": onKey?(.dismiss)
            default: super.keyDown(with: event)
            }
        }
    }
}

@MainActor final class AskBubbleViewModel: ObservableObject {
    @Published var agentName = ""; @Published var question = ""
    @Published var answer = ""; @Published var streaming = false
    @Published var error: String?
}

struct AskBubbleView: View {
    @ObservedObject var model: AskBubbleViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.agentName).font(.caption).opacity(0.6)
            Text(model.question).font(.callout).opacity(0.8)
            if let e = model.error { Text(e).foregroundStyle(.red).font(.callout) }
            else { Text(model.answer.isEmpty && model.streaming ? "…" : model.answer).font(.body) }
            HStack(spacing: 14) {
                Label("Insert", systemImage: "return").labelStyle(.titleOnly)
                Text("I").keycap(); Text("C").keycap(); Text("D").keycap()
                Spacer()
            }.font(.caption).opacity(0.7)
        }
        .padding(16)
        .frame(width: 420, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private extension View { func keycap() -> some View {
    self.padding(.horizontal, 6).padding(.vertical, 2)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4)) } }
```

(Refine glass styling to match `CaptionOverlayView`/Lucidity theming during implementation.)

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 3: Commit**

```bash
git add Sources/OmniVoiceApp/AskBubbleWindow.swift
git commit -m "feat(askai): liquid-glass Ask bubble (non-activating key panel, I/C/D)"
```

---

### Task 10: Wire Ask AI into the dictation flow

**Files:**
- Modify: `Sources/OmniVoiceApp/AppDelegate.swift` (add an `AskController` and route final transcripts)
- Create: `Sources/OmniVoiceApp/AskController.swift`

**Interfaces:**
- Consumes: `AgentRegistry`, `AskAICommandParser`, `AskPromptBuilder`, `AgentRunner`, `AskBubbleWindow`, `TextInsertionService`.
- Produces: `@MainActor final class AskController` with `func handle(transcript: String, captureTarget: TextInsertionService.Target?) -> Bool` (returns true if it consumed the transcript as an Ask command/follow-up/action, so dictation should NOT insert it).

- [ ] **Step 1: Implement `AskController`**

```swift
import AppKit
import OmniVoiceCore

@MainActor
final class AskController {
    private let bubble = AskBubbleWindow()
    private let runner: AgentRunning = AgentRunner()
    private let insertion: TextInsertionService
    private var registry: AgentRegistry
    private var history: [AskTurn] = []
    private var activeAgent: AgentDescriptor?
    private var capturedTarget: TextInsertionService.Target?
    private var lastAnswer = ""
    private(set) var bubbleOpen = false

    init(insertion: TextInsertionService, customAgents: [AgentConfiguration]) {
        self.insertion = insertion
        self.registry = AgentRegistry(custom: customAgents)
        bubble.onInsert = { [weak self] in self?.insertAnswer() }
        bubble.onCopy = { [weak self] in self?.copyAnswer() }
        bubble.onDismiss = { [weak self] in self?.dismiss() }
    }

    func updateAgents(_ custom: [AgentConfiguration]) { registry = AgentRegistry(custom: custom) }

    /// Returns true if consumed (so the caller must not type the transcript).
    func handle(transcript: String, captureTarget: TextInsertionService.Target?) -> Bool {
        let kws = registry.all.flatMap(\.keywords)
        switch AskAICommandParser.parse(transcript, knownKeywords: kws, bubbleOpen: bubbleOpen) {
        case .ask(let keyword, let question):
            guard let agent = registry.resolve(keyword: keyword) else { return false }
            history = []; activeAgent = agent
            capturedTarget = captureTarget
            ask(agent: agent, question: question); return true
        case .followUp(let q):
            guard let agent = activeAgent else { return false }
            ask(agent: agent, question: q); return true
        case .action(.insert): insertAnswer(); return true
        case .action(.copy): copyAnswer(); return true
        case .action(.dismiss): dismiss(); return true
        case .none:
            return false
        }
    }

    private func ask(agent: AgentDescriptor, question: String) {
        bubbleOpen = true; lastAnswer = ""
        bubble.show(question: question, agentName: agent.displayName)
        history.append(AskTurn(role: .user, text: question))
        let prompt = AskPromptBuilder.build(history: Array(history.dropLast()), question: question)
        Task { @MainActor in
            do {
                let out = try await runner.run(agent, prompt: prompt) { [weak self] chunk in
                    Task { @MainActor in self?.bubble.appendAnswer(chunk) }
                }
                bubble.setStreaming(false)
                lastAnswer = out.trimmingCharacters(in: .whitespacesAndNewlines)
                history.append(AskTurn(role: .assistant, text: lastAnswer))
            } catch AgentRunError.notFound {
                bubble.showError("\(agent.displayName) CLI not found. Set its path in Settings.")
            } catch AgentRunError.failed(let msg) {
                bubble.showError(msg.isEmpty ? "The agent returned an error." :
                    "Error: run `\(agent.binaryName)` once in a terminal to sign in.\n\(msg)")
            } catch { bubble.showError("\(error)") }
        }
    }

    private func insertAnswer() {
        guard !lastAnswer.isEmpty else { return }
        copyAnswer()
        Task { @MainActor in try? await insertion.insert(lastAnswer, target: capturedTarget) }
    }
    private func copyAnswer() {
        guard !lastAnswer.isEmpty else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(lastAnswer, forType: .string)
    }
    private func dismiss() { bubbleOpen = false; bubble.hide() }
}
```

- [ ] **Step 2: Route transcripts in `AppDelegate`**

In `AppDelegate`, add `private lazy var askController = AskController(insertion: insertionService, customAgents: model?.preferences.customAgents ?? [])`. In the dictation-finalize path (`finishDictation`), **before** the existing cleanup/insert, capture the target and try Ask:
```swift
let target = insertionService.captureTarget()
if askController.handle(transcript: rawTranscript, captureTarget: target) { 
    cancelLiveDraftIfNeeded(); hideOverlay(); return
}
```
(Place this right after `rawTranscript` is computed and the empty-guard passes, so "ask …" never gets typed. When the bubble is open, route subsequent finals through `askController.handle` first as well.) Call `askController.updateAgents(_:)` when preferences change.

- [ ] **Step 3: Build**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 4: Manual smoke test**

Run the app (`./script/build_and_run.sh`), hold push-to-talk, say "ask Claude what rhymes with bill", confirm the bubble streams an answer, press `I`, confirm it inserts at the cursor.

- [ ] **Step 5: Commit**

```bash
git add Sources/OmniVoiceApp/AskController.swift Sources/OmniVoiceApp/AppDelegate.swift
git commit -m "feat(askai): route ask/follow-up/actions from dictation to the bubble"
```

---

### Task 11: Custom-agent settings UI

**Files:**
- Modify: `Sources/OmniVoiceApp/SettingsView.swift` (add an "Ask AI agents" section)

**Interfaces:**
- Consumes: `model.preferences.customAgents`, an AppModel method `addCustomAgent(_:)` / `removeCustomAgent(id:)` that persists and calls `askController.updateAgents`.

- [ ] **Step 1: Add AppModel mutators** (in `AppModel.swift`, following the `mcpServers` pattern)

```swift
func addCustomAgent(_ agent: AgentConfiguration) {
    preferences.customAgents.append(agent); persistPreferences()
    onCustomAgentsChanged?(preferences.customAgents)
}
func removeCustomAgent(id: String) {
    preferences.customAgents.removeAll { $0.id == id }; persistPreferences()
    onCustomAgentsChanged?(preferences.customAgents)
}
```
Add `@ObservationIgnored var onCustomAgentsChanged: (([AgentConfiguration]) -> Void)?` and wire it in `OmniVoiceApp`/`AppDelegate` to `askController.updateAgents`.

- [ ] **Step 2: Add the settings section**

```swift
private var askAIAgentsSection: some View {
    Section("Ask AI agents") {
        Text("Built in: Claude, Gemini").foregroundStyle(.secondary).font(.caption)
        ForEach(model.preferences.customAgents) { a in
            HStack { Text("\(a.displayName) — say “ask \(a.keyword)”"); Spacer()
                Button("Remove") { model.removeCustomAgent(id: a.id) } }
        }
        DisclosureGroup("Add a custom agent") { AddAgentForm { model.addCustomAgent($0) } }
    }
}
```
Add a small `AddAgentForm` view: fields for **name/keyword**, **CLI path** (with an `NSOpenPanel` "Browse…" button), and an **Advanced** `DisclosureGroup` with a TextField for the args template (default `{prompt}`), a "send prompt on stdin" toggle, and a stream-format picker (only `.plainText` for v1). On submit it builds an `AgentConfiguration` (id = UUID string) and calls the closure.

- [ ] **Step 3: Build**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 4: Manual test**

Open Settings → Ask AI agents → add an agent pointing at `/bin/echo` with keyword "echo"; say "ask echo hello"; confirm the bubble shows "hello".

- [ ] **Step 5: Commit**

```bash
git add Sources/OmniVoiceApp/SettingsView.swift Sources/OmniVoiceApp/AppModel.swift Sources/OmniVoiceApp/OmniVoiceApp.swift
git commit -m "feat(askai): settings UI to add custom agents (keyword, path, advanced command)"
```

---

## Follow-up (separate plan, not v1)

- Token-level streaming via `streamJSON`/`streamingJSON` parsers (capture real `claude -p --output-format stream-json` and `grok ... streaming-json` samples first), plus built-in descriptors for Codex, Grok, Kimi, Copilot, opencode.
- Per-agent "no tools" hardening once each CLI's flags are confirmed.
- Bubble polish: idle-timeout auto-dismiss, theming pass to fully match Lucidity glass.

## Self-review notes

- Spec coverage: trigger/grammar (T5,T10), stateless context (T6), one-shot run + stream (T8), bubble + I/C/D (T9), insert-at-cursor (T10), custom agents incl. advanced command (T2,T3,T11), security/argv (T1,T8), PATH discovery (T7), error handling (T8,T10). Stream-JSON + extra agents deferred (documented above) per spec's "Claude+Gemini first."
- Types are consistent across tasks (`AgentDescriptor`, `AgentConfiguration`, `AskTurn`, `AskAIIntent`, `AgentRunning`, `AskBubbleWindow` callbacks).
