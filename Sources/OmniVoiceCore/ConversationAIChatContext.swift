import Foundation

public enum ConversationAIChatContext {
    public static let systemPrompt = """
    You are OmniSpeak's conversation assistant.
    Only answer from the supplied transcript unless the user explicitly asks for outside knowledge.
    When possible, cite the relevant speaker and timestamp.
    If the transcript does not contain enough information, say what is missing instead of guessing.
    Keep answers concise and directly useful.
    """

    public static func transcriptAttachment(for detail: ConversationDetail) -> AIChatAttachment {
        AIChatAttachment(AskAIContextAttachment(conversation: detail))
    }

    public static func messages(history: [AskAIMessage], question: String) -> [AIChatMessage] {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let historyMessages = history.map { AIChatMessage(role: $0.role, content: $0.text) }
        return [AIChatMessage(role: .system, content: systemPrompt)]
            + historyMessages
            + [AIChatMessage(role: .user, content: trimmedQuestion)]
    }
}
