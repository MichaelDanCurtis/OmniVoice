import Foundation

public enum DictationCommandAction: Equatable, Sendable {
    case openApplication(name: String)
    case showCommandPalette
    case undoLastDictation
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
}
