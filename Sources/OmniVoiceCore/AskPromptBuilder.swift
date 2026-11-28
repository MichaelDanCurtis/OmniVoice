import Foundation

public enum AskRole: Sendable { case user, assistant }
public struct AskTurn: Equatable, Sendable {
    public let role: AskRole; public let text: String
    public init(role: AskRole, text: String) { self.role = role; self.text = text }
}

public enum AskPromptBuilder {
    /// Natural, decisive agent persona shared by voice Ask AI and Ask AI Workspace.
    public static let agenticSystemPrompt = """
    You are the user's sharp, proactive personal AI agent inside OmniSpeak on macOS. Speak naturally like a capable colleague — direct, decisive, and conversational with zero robotic filler or disclaimers. Lead with the answer, draft, or recommendation right away, suggest the most helpful next step when relevant, and keep formatting clean plain text so it reads smoothly and pastes cleanly anywhere.
    """

    static let preamble = agenticSystemPrompt

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
