import Foundation

public struct ConversationTranscriptAccumulator: Equatable, Sendable {
    public enum Decision: Equatable, Sendable {
        case ignore
        case segment(text: String, isFinal: Bool)
    }

    private var lastPartialText = ""

    public init() {}

    public mutating func ingest(_ update: TranscriptUpdate) -> Decision {
        let text = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return .ignore
        }

        if !update.isFinal, Self.isTransientStreamingText(text) {
            return .ignore
        }

        if !update.isFinal, text == lastPartialText {
            return .ignore
        }

        if !update.isFinal {
            lastPartialText = text
        }

        if update.isFinal {
            lastPartialText = ""
        }

        return .segment(text: text, isFinal: update.isFinal)
    }

    public static func isTransientStreamingText(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("listening") == .orderedSame
    }
}
