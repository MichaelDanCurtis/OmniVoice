import Foundation

public enum ConversationArchive {
    public static func defaultRootURL(
        documentsURL: URL? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    ) -> URL {
        let base = documentsURL ?? URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)
            .appending(path: "Documents", directoryHint: .isDirectory)
        return base.appending(path: "OmniVoice", directoryHint: .isDirectory)
    }

    public static func markdown(for detail: ConversationDetail) -> String {
        var lines: [String] = [
            "# \(detail.session.title)",
            "",
            "- Started: \(detail.session.startedAt)",
            "- Ended: \(detail.session.endedAt ?? "Active")",
            "- Capture: \(detail.session.captureMode.displayName)",
            "- ASR: \(detail.session.asrProvider)",
            "- Diarization: \(detail.session.diarizationProvider)",
            "",
            "## Transcript",
            "",
        ]

        if detail.segments.isEmpty {
            lines.append("_No transcript segments were recorded._")
        } else {
            lines.append(contentsOf: detail.segments.flatMap { segment in
                segment.diarizedTranscriptLines.map { line in
                    "\(line.speakerDisplayName) [\(line.timestampLabel)]: \(line.text)"
                }
            })
        }

        if !detail.assistCards.isEmpty {
            lines.append(contentsOf: ["", "## Assist Cards", ""])
            for card in detail.assistCards {
                lines.append("### \(card.title)")
                lines.append(card.body)
                if !card.sourceReferences.isEmpty {
                    lines.append("")
                    lines.append("Sources:")
                    lines.append(contentsOf: card.sourceReferences.map { "- \($0)" })
                }
                lines.append("")
            }
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    @discardableResult
    public static func write(
        _ detail: ConversationDetail,
        rootURL: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let conversationsURL = rootURL.appending(path: "Conversations", directoryHint: .isDirectory)
        let folderURL = conversationsURL.appending(path: folderName(for: detail.session), directoryHint: .isDirectory)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        try markdown(for: detail).write(to: folderURL.appending(path: "transcript.md"), atomically: true, encoding: .utf8)
        try EngineCoding.encoder.encode(detail).write(to: folderURL.appending(path: "transcript.json"), options: .atomic)
        try EngineCoding.encoder.encode(detail.assistCards).write(to: folderURL.appending(path: "assist-cards.json"), options: .atomic)
        try EngineCoding.encoder.encode(detail.session).write(to: folderURL.appending(path: "metadata.json"), options: .atomic)

        return folderURL
    }

    public static func folderName(for session: ConversationSession) -> String {
        let timestamp = session.startedAt
            .replacingOccurrences(of: "T", with: " ")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "Z", with: "")
            .prefix(19)
        let title = sanitizedFolderComponent(session.title)
        return "\(timestamp) \(title)".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sanitizedFolderComponent(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = value
            .components(separatedBy: invalid)
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Conversation" : cleaned
    }
}
