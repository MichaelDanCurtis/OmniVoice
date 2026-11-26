import Foundation

// MARK: - Command Mode (cua-driver Computer-Use MCP)

public enum CommandModeCorner: String, CaseIterable, Codable, Hashable, Sendable {
    case bottomLeft
    case topLeft
    case topRight
    case bottomRight

    public var displayName: String {
        switch self {
        case .bottomLeft: "Bottom Left"
        case .topLeft: "Top Left"
        case .topRight: "Top Right"
        case .bottomRight: "Bottom Right"
        }
    }

    public var next: CommandModeCorner {
        switch self {
        case .bottomLeft: .topLeft
        case .topLeft: .topRight
        case .topRight: .bottomRight
        case .bottomRight: .bottomLeft
        }
    }
}

public enum CommandModeDirective: Equatable, Sendable {
    case enter(initialCommand: String?)
    case exit
}

public enum CommandModeVoiceParser {
    private static let enterTriggers = [
        "go into command mode",
        "enter command mode",
        "start command mode",
        "enable command mode",
        "turn on command mode",
        "switch to command mode",
        "command mode",
    ]

    private static let exitTriggers = [
        "exit command mode",
        "leave command mode",
        "stop command mode",
        "disable command mode",
        "turn off command mode",
        "end command mode",
        "back to dictation",
        "normal mode",
        "dictation mode",
    ]

    public static func parse(_ text: String) -> CommandModeDirective? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed
            .lowercased()
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))

        if exitTriggers.contains(where: { normalized == $0 || normalized.hasPrefix($0 + " ") }) {
            return .exit
        }

        for trigger in enterTriggers {
            if normalized == trigger {
                return .enter(initialCommand: nil)
            }
            if normalized.hasPrefix(trigger) {
                let dropIdx = trimmed.lowercased().range(of: trigger)?.upperBound ?? trimmed.endIndex
                let remainder = String(trimmed[dropIdx...])
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,:;!?-")))
                return .enter(initialCommand: remainder.isEmpty ? nil : remainder)
            }
        }
        return nil
    }
}

/// Zero-latency fast-path parser for common desktop voice actions so simple
/// commands ("scroll down", "open Safari", "click Send", "press enter", "new tab")
/// execute immediately in-process without waiting on an LLM round-trip.
public struct NativeDesktopFastAction: Equatable, Sendable {
    public let tool: String
    public let stringArgs: [String: String]
    public let boolArgs: [String: Bool]
    public let intArgs: [String: Int]
    public let arrayArgs: [String: [String]]

    public init(
        tool: String,
        stringArgs: [String: String] = [:],
        boolArgs: [String: Bool] = [:],
        intArgs: [String: Int] = [:],
        arrayArgs: [String: [String]] = [:]
    ) {
        self.tool = tool
        self.stringArgs = stringArgs
        self.boolArgs = boolArgs
        self.intArgs = intArgs
        self.arrayArgs = arrayArgs
    }
}

public enum NativeDesktopFastPath {
    public static func match(_ spokenCommand: String) -> NativeDesktopFastAction? {
        let trimmed = spokenCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
        let lower = cleaned.lowercased()
        guard !lower.isEmpty else { return nil }

        // Scroll
        if lower == "scroll down" || lower == "page down" {
            return NativeDesktopFastAction(tool: "scroll", stringArgs: ["direction": "down"], intArgs: ["amount": 8])
        }
        if lower == "scroll up" || lower == "page up" {
            return NativeDesktopFastAction(tool: "scroll", stringArgs: ["direction": "up"], intArgs: ["amount": 8])
        }
        if lower == "scroll left" {
            return NativeDesktopFastAction(tool: "scroll", stringArgs: ["direction": "left"], intArgs: ["amount": 8])
        }
        if lower == "scroll right" {
            return NativeDesktopFastAction(tool: "scroll", stringArgs: ["direction": "right"], intArgs: ["amount": 8])
        }

        // Common keys & shortcuts
        switch lower {
        case "press enter", "hit enter", "enter", "return":
            return NativeDesktopFastAction(tool: "press_key", stringArgs: ["key": "enter"])
        case "press escape", "escape", "cancel":
            return NativeDesktopFastAction(tool: "press_key", stringArgs: ["key": "escape"])
        case "new tab", "open new tab":
            return NativeDesktopFastAction(tool: "press_key", stringArgs: ["key": "t"], arrayArgs: ["modifiers": ["cmd"]])
        case "close tab":
            return NativeDesktopFastAction(tool: "press_key", stringArgs: ["key": "w"], arrayArgs: ["modifiers": ["cmd"]])
        case "copy", "copy that":
            return NativeDesktopFastAction(tool: "press_key", stringArgs: ["key": "c"], arrayArgs: ["modifiers": ["cmd"]])
        case "paste", "paste that":
            return NativeDesktopFastAction(tool: "press_key", stringArgs: ["key": "v"], arrayArgs: ["modifiers": ["cmd"]])
        case "undo", "undo that":
            return NativeDesktopFastAction(tool: "press_key", stringArgs: ["key": "z"], arrayArgs: ["modifiers": ["cmd"]])
        case "save", "save file":
            return NativeDesktopFastAction(tool: "press_key", stringArgs: ["key": "s"], arrayArgs: ["modifiers": ["cmd"]])
        default:
            break
        }

        // Open / switch to single app (only when it's a simple single-step request without "and")
        if !lower.contains(" and ") {
            for prefix in ["open ", "switch to ", "launch ", "focus "] where lower.hasPrefix(prefix) {
                let target = String(cleaned.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !target.isEmpty else { continue }
                if target.contains(".") && !target.contains(" ") {
                    return NativeDesktopFastAction(tool: "open_url", stringArgs: ["url": target])
                }
                return NativeDesktopFastAction(tool: "open_app", stringArgs: ["name": target])
            }
            for prefix in ["go to ", "navigate to "] where lower.hasPrefix(prefix) {
                let target = String(cleaned.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if target.contains(".") && !target.contains(" ") {
                    return NativeDesktopFastAction(tool: "open_url", stringArgs: ["url": target])
                }
            }
            for prefix in ["click ", "click on ", "press ", "tap "] where lower.hasPrefix(prefix) {
                let label = String(cleaned.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !label.isEmpty, label.split(separator: " ").count <= 4 {
                    return NativeDesktopFastAction(tool: "click_element", stringArgs: ["label": label])
                }
            }
            for prefix in ["type ", "write "] where lower.hasPrefix(prefix) {
                let text = String(cleaned.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return NativeDesktopFastAction(tool: "type_text", stringArgs: ["text": text])
                }
            }
        }

        return nil
    }
}

// MARK: - Inline Voice Translation ("in Spanish, ..." / "translate to Japanese, ...")

public struct InlineTranslationRequest: Equatable, Sendable {
    public let targetLanguageCode: String
    public let targetLanguageName: String
    public let text: String

    public init(targetLanguageCode: String, targetLanguageName: String, text: String) {
        self.targetLanguageCode = targetLanguageCode
        self.targetLanguageName = targetLanguageName
        self.text = text
    }
}

public enum InlineTranslationParser {
    public static let supportedLanguages: [(name: String, code: String, flag: String)] = [
        ("Spanish", "es", "🇪🇸"),
        ("French", "fr", "🇫🇷"),
        ("German", "de", "🇩🇪"),
        ("Japanese", "ja", "🇯🇵"),
        ("Chinese", "zh", "🇨🇳"),
        ("Mandarin", "zh", "🇨🇳"),
        ("Korean", "ko", "🇰🇷"),
        ("Italian", "it", "🇮🇹"),
        ("Portuguese", "pt", "🇧🇷"),
        ("Dutch", "nl", "🇳🇱"),
        ("Russian", "ru", "🇷🇺"),
        ("Arabic", "ar", "🇸🇦"),
        ("Hindi", "hi", "🇮🇳"),
        ("Polish", "pl", "🇵🇱"),
        ("Swedish", "sv", "🇸🇪"),
        ("Turkish", "tr", "🇹🇷"),
        ("Vietnamese", "vi", "🇻🇳"),
        ("English", "en", "🇺🇸"),
    ]

    public static func languageInfo(forCode code: String) -> (name: String, code: String, flag: String)? {
        let lower = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return supportedLanguages.first { $0.code == lower }
    }

    public static func parse(_ rawText: String) -> InlineTranslationRequest? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()

        let prefixes = ["translate to ", "translate into ", "say in ", "in "]
        for prefix in prefixes where lower.hasPrefix(prefix) {
            let afterPrefix = String(trimmed.dropFirst(prefix.count))
            let lowerAfter = afterPrefix.lowercased()
            for lang in supportedLanguages {
                let langLower = lang.name.lowercased()
                if lowerAfter.hasPrefix(langLower) {
                    let boundaryIdx = afterPrefix.index(afterPrefix.startIndex, offsetBy: langLower.count)
                    if boundaryIdx < afterPrefix.endIndex {
                        let nextChar = afterPrefix[boundaryIdx]
                        guard nextChar.isWhitespace || ",:;-.".contains(nextChar) else { continue }
                    }
                    let payload = String(afterPrefix[boundaryIdx...])
                        .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",:;-")))
                    guard !payload.isEmpty else { return nil }
                    return InlineTranslationRequest(
                        targetLanguageCode: lang.code,
                        targetLanguageName: lang.name,
                        text: payload
                    )
                }
            }
        }
        return nil
    }
}

// MARK: - Highlight & Transform ("Voice Edit Mode")

public enum VoiceEditDetector {
    private static let editPrefixes = [
        "make this ", "make it ", "rewrite this", "rewrite it", "rephrase",
        "shorten this", "shorten it", "summarize this", "summarize it",
        "expand this", "expand it", "polish this", "polish it",
        "fix grammar", "fix the grammar", "fix spelling", "fix tone", "fix the tone",
        "turn this into ", "convert this to ", "convert to ",
        "translate this to ", "translate to ", "translate into ",
        "explain this", "simplify this", "clean this up", "format this",
        "bullet points", "make bullet points",
    ]

    public static func isEditInstruction(_ spokenText: String, hasSelectedText: Bool) -> Bool {
        guard hasSelectedText else { return false }
        let lower = spokenText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard lower.count >= 6, lower.count <= 160 else { return false }
        return editPrefixes.contains { lower.hasPrefix($0) }
    }
}

// MARK: - Voice Snippets & Dynamic Macros

public struct VoiceSnippet: Codable, Equatable, Identifiable, Hashable, Sendable {
    public var id: String
    public var trigger: String
    public var expansion: String

    public init(id: String = UUID().uuidString, trigger: String, expansion: String) {
        self.id = id
        self.trigger = trigger
        self.expansion = expansion
    }

    public static let defaultSnippets: [VoiceSnippet] = [
        VoiceSnippet(id: "snippet-date", trigger: "today's date", expansion: "{{date}}"),
        VoiceSnippet(id: "snippet-standup", trigger: "standup template", expansion: "**Yesterday:**\n- \n\n**Today:**\n- \n\n**Blockers:**\n- None"),
    ]
}

public enum VoiceSnippetExpander {
    public static func expand(
        _ spokenText: String,
        snippets: [VoiceSnippet],
        now: Date = Date(),
        clipboardText: String = ""
    ) -> String? {
        let normalized = spokenText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
        guard !normalized.isEmpty else { return nil }

        guard let match = snippets.first(where: { snippet in
            let trig = snippet.trigger
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
            return !trig.isEmpty && (normalized == trig || normalized == "insert \(trig)" || normalized == "paste \(trig)")
        }) else {
            return nil
        }

        let dateFmt = DateFormatter()
        dateFmt.dateStyle = .medium
        dateFmt.timeStyle = .none
        let timeFmt = DateFormatter()
        timeFmt.dateStyle = .none
        timeFmt.timeStyle = .short

        return match.expansion
            .replacingOccurrences(of: "{{date}}", with: dateFmt.string(from: now))
            .replacingOccurrences(of: "{{time}}", with: timeFmt.string(from: now))
            .replacingOccurrences(of: "{{clipboard}}", with: clipboardText)
    }
}

// MARK: - Per-App Auto-Tone & Code-Aware Formatting

public enum AppToneContext: Equatable, Sendable {
    case coding(appName: String)
    case chat(appName: String)
    case email(appName: String)
    case writing(appName: String)
    case general(appName: String)

    public var formattingHint: String {
        switch self {
        case .coding(let app):
            return "Active app is \(app) (coding/terminal). Preserve exact camelCase/snake_case identifiers, wrap filenames, symbols, and CLI flags in markdown backticks."
        case .chat(let app):
            return "Active app is \(app) (messaging). Keep the reply natural, punchy, and conversational with clean punctuation."
        case .email(let app):
            return "Active app is \(app) (email). Use polished, clear sentences and natural paragraph breaks."
        case .writing(let app):
            return "Active app is \(app) (document editor). Use clean grammar, well-structured sentences, and crisp markdown where helpful."
        case .general(let app):
            return app.isEmpty ? "" : "Active app is \(app)."
        }
    }

    public static func detect(bundleIdentifier: String?, appName: String?) -> AppToneContext {
        let bundle = (bundleIdentifier ?? "").lowercased()
        let name = appName ?? ""
        let lowerName = name.lowercased()

        if bundle.contains("xcode") || bundle.contains("vscode") || bundle.contains("cursor")
            || bundle.contains("windsurf") || bundle.contains("zed") || bundle.contains("terminal")
            || bundle.contains("iterm") || bundle.contains("ghostty") || bundle.contains("warp")
            || bundle.contains("antigravity") || lowerName.contains("antigravity") {
            return .coding(appName: name.isEmpty ? "IDE" : name)
        }
        if bundle.contains("slack") || bundle.contains("mobilesms") || bundle.contains("messages")
            || bundle.contains("discord") || bundle.contains("whatsapp") || bundle.contains("telegram")
            || bundle.contains("teams") {
            return .chat(appName: name.isEmpty ? "Chat" : name)
        }
        if bundle.contains("mail") || bundle.contains("outlook") || bundle.contains("superhuman")
            || bundle.contains("spark") || bundle.contains("mimestream") {
            return .email(appName: name.isEmpty ? "Mail" : name)
        }
        if bundle.contains("notion") || bundle.contains("obsidian") || bundle.contains("notes")
            || bundle.contains("pages") || bundle.contains("word") || bundle.contains("linear") {
            return .writing(appName: name.isEmpty ? "Docs" : name)
        }
        return .general(appName: name)
    }
}

// MARK: - Voice Productivity & WPM Stats

public struct DictationStatsSnapshot: Codable, Equatable, Sendable {
    public var totalWords: Int
    public var todayWords: Int
    public var todayDateKey: String
    public var totalSessions: Int
    public var totalSpeakingSeconds: Double
    public var wordsByApp: [String: Int]

    public init(
        totalWords: Int = 0,
        todayWords: Int = 0,
        todayDateKey: String = DictationStatsSnapshot.dateKey(for: Date()),
        totalSessions: Int = 0,
        totalSpeakingSeconds: Double = 0,
        wordsByApp: [String: Int] = [:]
    ) {
        self.totalWords = totalWords
        self.todayWords = todayWords
        self.todayDateKey = todayDateKey
        self.totalSessions = totalSessions
        self.totalSpeakingSeconds = totalSpeakingSeconds
        self.wordsByApp = wordsByApp
    }

    public mutating func record(text: String, speakingSeconds: Double, appName: String?, at date: Date = Date()) {
        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        guard words > 0 else { return }
        let key = Self.dateKey(for: date)
        if todayDateKey != key {
            todayDateKey = key
            todayWords = 0
        }
        totalWords += words
        todayWords += words
        totalSessions += 1
        totalSpeakingSeconds += max(0.5, speakingSeconds)
        if let app = appName?.trimmingCharacters(in: .whitespacesAndNewlines), !app.isEmpty {
            wordsByApp[app, default: 0] += words
        }
    }

    public var averageWPM: Int {
        guard totalSpeakingSeconds >= 2 else { return 0 }
        return Int((Double(totalWords) / (totalSpeakingSeconds / 60.0)).rounded())
    }

    /// Estimated minutes saved compared to typing at 42 WPM.
    public var estimatedMinutesSaved: Int {
        let typingMinutes = Double(totalWords) / 42.0
        let speakingMinutes = totalSpeakingSeconds / 60.0
        return max(0, Int((typingMinutes - speakingMinutes).rounded()))
    }

    public var topApps: [(name: String, words: Int)] {
        wordsByApp
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { (name: $0.key, words: $0.value) }
    }

    public static func dateKey(for date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }
}
