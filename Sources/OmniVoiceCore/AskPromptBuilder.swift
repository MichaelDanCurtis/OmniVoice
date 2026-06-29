import Foundation

public enum AskRole: Sendable { case user, assistant }
public struct AskTurn: Equatable, Sendable {
    public let role: AskRole; public let text: String
    public init(role: AskRole, text: String) { self.role = role; self.text = text }
}

public enum AskPromptBuilder {
    static let preamble = """
    You are a quick-answer assistant inside a dictation app. Answer concisely in plain text. do not use tools, run commands, or read files — just answer.
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
