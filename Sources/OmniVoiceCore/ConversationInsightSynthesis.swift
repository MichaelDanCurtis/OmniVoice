import Foundation

public enum ConversationInsightSynthesis {
    public static let systemPrompt = """
    You create concise live conversation insight cards for OmniVoice.
    Only use evidence from the provided transcript. Do not invent facts, sources, or names.
    Prefer useful cards: detected questions, direct answers, time-zone conversions, follow-ups, action items, and warnings.
    """

    public static func userPrompt(for detail: ConversationDetail, maxCards: Int = 6) -> String {
        let transcript = transcriptLines(for: detail)
        return """
        Analyze this OmniVoice conversation and create up to \(maxCards) useful insight rail cards.

        Return only JSON with this exact shape:
        {
          "cards": [
            {
              "kind": "question",
              "title": "Short card title",
              "body": "Useful concise detail the user can copy or act on.",
              "source_references": ["Speaker [00:18]"],
              "confidence": 0.8
            }
          ]
        }

        Valid kind values: question, answer, time_zone, follow_up, action_item, warning.
        Use source_references from transcript line labels only.
        If there are no useful cards, return {"cards":[]}.

        Transcript:
        \(transcript)
        """
    }

    public static func cardRequests(from response: String) -> [ConversationAssistCardCreateRequest] {
        guard let jsonData = jsonData(from: response),
              let object = try? JSONSerialization.jsonObject(with: jsonData) else {
            return []
        }

        let rawCards: [[String: Any]]
        if let dictionary = object as? [String: Any],
           let cards = dictionary["cards"] as? [[String: Any]] {
            rawCards = cards
        } else if let cards = object as? [[String: Any]] {
            rawCards = cards
        } else {
            rawCards = []
        }

        return rawCards.compactMap(cardRequest(from:))
    }

    private static func transcriptLines(for detail: ConversationDetail) -> String {
        let lines = detail.segments
            .filter { $0.state != .live }
            .flatMap { segment in
                segment.diarizedTranscriptLines.map { line in
                    "\(line.speakerDisplayName) [\(line.timestampLabel)]: \(line.text)"
                }
            }

        return lines.isEmpty ? "_No settled transcript segments yet._" : lines.joined(separator: "\n")
    }

    private static func cardRequest(from dictionary: [String: Any]) -> ConversationAssistCardCreateRequest? {
        guard let kindValue = dictionary["kind"] as? String,
              let kind = ConversationAssistCardKind(rawValue: kindValue),
              let title = nonBlankString(dictionary["title"]),
              let body = nonBlankString(dictionary["body"]) else {
            return nil
        }

        let references = (dictionary["source_references"] as? [String] ?? dictionary["sourceReferences"] as? [String] ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let confidence = confidenceValue(dictionary["confidence"])

        return ConversationAssistCardCreateRequest(
            kind: kind,
            title: title,
            body: body,
            sourceReferences: references,
            confidence: confidence
        )
    }

    private static func nonBlankString(_ value: Any?) -> String? {
        guard let string = value as? String else {
            return nil
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func confidenceValue(_ value: Any?) -> Double? {
        let confidence: Double?
        if let number = value as? NSNumber {
            confidence = number.doubleValue
        } else if let string = value as? String {
            confidence = Double(string)
        } else {
            confidence = nil
        }

        guard let confidence else {
            return nil
        }
        return min(1.0, max(0.0, confidence))
    }

    private static func jsonData(from response: String) -> Data? {
        for block in fencedBlocks(in: response) {
            if let data = block.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) != nil {
                return data
            }
        }

        if let range = firstJSONObjectRange(in: response) {
            return String(response[range]).data(using: .utf8)
        }

        return response.data(using: .utf8)
    }

    private static func fencedBlocks(in response: String) -> [String] {
        var blocks: [String] = []
        var current: [String] = []
        var inFence = false

        for line in response.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inFence {
                    blocks.append(current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
                    current.removeAll()
                }
                inFence.toggle()
                continue
            }

            if inFence {
                current.append(line)
            }
        }

        return blocks
    }

    private static func firstJSONObjectRange(in response: String) -> Range<String.Index>? {
        guard let start = response.firstIndex(where: { $0 == "{" || $0 == "[" }) else {
            return nil
        }

        let opening = response[start]
        let closing: Character = opening == "{" ? "}" : "]"
        var depth = 0
        var isEscaped = false
        var isInString = false
        var index = start

        while index < response.endIndex {
            let character = response[index]

            if isInString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInString = false
                }
            } else if character == "\"" {
                isInString = true
            } else if character == opening {
                depth += 1
            } else if character == closing {
                depth -= 1
                if depth == 0 {
                    return start..<response.index(after: index)
                }
            }

            index = response.index(after: index)
        }

        return nil
    }
}
