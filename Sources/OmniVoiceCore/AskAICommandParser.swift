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
