import Foundation

public enum AIHandoffTarget: String, Codable, CaseIterable, Equatable, Sendable {
    case claude
    case codex
    case openRouter = "openrouter"
    case openAI = "openai"
    case custom

    public var displayName: String {
        switch self {
        case .claude:
            "Claude"
        case .codex:
            "Codex"
        case .openRouter:
            "OpenRouter"
        case .openAI:
            "OpenAI"
        case .custom:
            "AI"
        }
    }
}

public enum DictationCommandAction: Equatable, Sendable {
    case openApplication(name: String)
    case showCommandPalette
    case undoLastDictation
    case aiHandoff(target: AIHandoffTarget, prompt: String)
}

public struct DictationCommand: Equatable, Sendable {
    public let action: DictationCommandAction
    public let displayText: String

    public init(action: DictationCommandAction, displayText: String) {
        self.action = action
        self.displayText = displayText
    }
}

public enum DictationCommandParser {
    public static func parse(_ text: String) -> DictationCommand? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let aiCommand = parseAIHandoff(trimmed) {
            return aiCommand
        }

        guard trimmed.localizedCaseInsensitiveCompare("command") != .orderedSame else {
            return nil
        }
        guard trimmed.lowercased().hasPrefix("command") else {
            return nil
        }

        let afterCommand = String(trimmed.dropFirst("command".count))
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,:;!?")))
        guard !afterCommand.isEmpty else {
            return nil
        }

        var body = afterCommand
        for prefix in ["please ", "let's ", "lets "] {
            if body.lowercased().hasPrefix(prefix) {
                body = String(body.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        let normalizedBody = body.lowercased()

        if ["show commands", "show command palette", "help", "what can i say"].contains(normalizedBody) {
            return DictationCommand(action: .showCommandPalette, displayText: "Showing commands")
        }

        if ["undo last dictation", "undo last insertion", "undo that"].contains(normalizedBody) {
            return DictationCommand(action: .undoLastDictation, displayText: "Undoing last dictation")
        }

        for verb in ["open ", "launch ", "start "] {
            if body.lowercased().hasPrefix(verb) {
                let name = String(body.dropFirst(verb.count))
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,:;!?")))
                guard !name.isEmpty else {
                    return nil
                }
                return DictationCommand(
                    action: .openApplication(name: name),
                    displayText: "Opening \(name)"
                )
            }
        }

        return nil
    }

    private static func parseAIHandoff(_ text: String) -> DictationCommand? {
        guard !text.isEmpty else {
            return nil
        }

        for target in AIHandoffTarget.allCases {
            guard target != .custom else {
                continue
            }

            for prefix in aiPrefixes(for: target) {
                if let prompt = prompt(after: prefix, in: text) {
                    return DictationCommand(
                        action: .aiHandoff(target: target, prompt: prompt),
                        displayText: "Asking \(target.displayName)"
                    )
                }
            }
        }

        for prefix in ["ask ai", "hey ai", "have ai take a look", "have the ai take a look"] {
            if let prompt = prompt(after: prefix, in: text) {
                return DictationCommand(
                    action: .aiHandoff(target: .custom, prompt: prompt),
                    displayText: "Asking AI"
                )
            }
        }

        return nil
    }

    private static func aiPrefixes(for target: AIHandoffTarget) -> [String] {
        switch target {
        case .claude:
            ["ask claude", "hey claude", "have claude take a look"]
        case .codex:
            ["ask codex", "hey codex", "have codex take a look"]
        case .openRouter:
            ["ask openrouter", "ask open router", "hey openrouter", "hey open router", "have openrouter take a look", "have open router take a look"]
        case .openAI:
            ["ask openai", "ask open ai", "hey openai", "hey open ai", "have openai take a look", "have open ai take a look"]
        case .custom:
            []
        }
    }

    private static func prompt(after prefix: String, in text: String) -> String? {
        let lowercased = text.lowercased()
        guard lowercased.hasPrefix(prefix) else {
            return nil
        }

        let boundaryIndex = lowercased.index(lowercased.startIndex, offsetBy: prefix.count)
        if boundaryIndex < lowercased.endIndex {
            let next = lowercased[boundaryIndex]
            guard next.isWhitespace || ".,:;!?".contains(next) else {
                return nil
            }
        }

        let rawPrompt = String(text.dropFirst(prefix.count))
        let prompt = rawPrompt.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,:;!?"))
        )
        guard !prompt.isEmpty else {
            return nil
        }
        return prompt
    }
}
