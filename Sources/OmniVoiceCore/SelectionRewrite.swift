import Foundation

public enum SelectionRewrite {
    public static func rewrite(selectedText: String, instruction: String) -> String? {
        let trimmedSelection = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedInstruction = instruction
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!?")))
            .lowercased()
        guard !trimmedSelection.isEmpty else {
            return nil
        }

        if normalizedInstruction.contains("bullet") {
            return bulletize(trimmedSelection)
        }

        if normalizedInstruction.contains("shorter") || normalizedInstruction.contains("concise") {
            return firstSentence(trimmedSelection)
        }

        if normalizedInstruction.contains("professional") {
            return professionalize(trimmedSelection)
        }

        if normalizedInstruction.contains("warmer") || normalizedInstruction.contains("friendly") {
            return warmer(trimmedSelection)
        }

        if normalizedInstruction.hasPrefix("reply ") || normalizedInstruction.hasPrefix("respond ") {
            return reply(from: normalizedInstruction)
        }

        return nil
    }

    private static func bulletize(_ text: String) -> String {
        let parts = sentenceParts(text)
        guard !parts.isEmpty else {
            return "- \(text)"
        }
        return parts.map { "- \($0)" }.joined(separator: "\n")
    }

    private static func firstSentence(_ text: String) -> String {
        sentenceParts(text).first ?? text
    }

    private static func professionalize(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "hey", with: "Hello", options: [.caseInsensitive])
            .replacingOccurrences(of: "thanks", with: "Thank you", options: [.caseInsensitive])
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return result }
        return result.prefix(1).uppercased() + String(result.dropFirst())
    }

    private static func warmer(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return result }
        if !result.localizedCaseInsensitiveContains("thank") {
            result += result.hasSuffix(".") ? " Thank you." : ". Thank you."
        }
        return result
    }

    private static func reply(from instruction: String) -> String? {
        let prefixes = ["reply politely that ", "reply that ", "respond politely that ", "respond that "]
        for prefix in prefixes where instruction.hasPrefix(prefix) {
            let content = String(instruction.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }
            return "Thanks for the note. \(content.prefix(1).uppercased() + String(content.dropFirst()))."
        }
        return nil
    }

    private static func sentenceParts(_ text: String) -> [String] {
        text.split(whereSeparator: { ".!?".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
