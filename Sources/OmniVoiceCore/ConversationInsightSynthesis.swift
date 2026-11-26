import Foundation

public enum ConversationInsightSynthesis {
    public static let systemPrompt = """
    You create concise live conversation insight cards for OmniSpeak.
    Only use evidence from the provided transcript. Do not invent facts, sources, or names.
    Prefer useful cards: detected questions, direct answers, time-zone conversions, follow-ups, action items, and warnings.
    """

    public static func userPrompt(for detail: ConversationDetail, maxCards: Int = 6) -> String {
        let transcript = transcriptLines(for: detail)
        return """
        Analyze this OmniSpeak conversation and create up to \(maxCards) useful insight rail cards.

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

    public static func liveQuestionAnswerPrompt(
        question: String,
        speakerName: String,
        recentTranscript: String,
        calendarContext: MeetingCalendarContext? = nil
    ) -> String {
        let contextBlock = calendarContext.map { "Calendar context:\n\($0.promptContextSummary)\n\n" } ?? ""
        return """
        A question was just asked during a live meeting.
        \(contextBlock)Speaker: \(speakerName)
        Question: "\(question)"

        Provide a concise, immediately usable answer the user can glance at and say out loud.
        Use facts from the recent transcript or calendar context if relevant; if it's a general technical or factual question, answer directly and briefly (1-3 sentences max).

        Return only JSON with this exact shape:
        {
          "cards": [
            {
              "kind": "answer",
              "title": "Short answer headline (max 6 words)",
              "body": "Direct, clear answer (1-3 sentences).",
              "source_references": ["\(speakerName)"],
              "confidence": 0.85
            }
          ]
        }

        Recent transcript:
        \(recentTranscript)
        """
    }

    public static func screenAwareAnswerPrompt(
        recentTranscript: String,
        calendarContext: MeetingCalendarContext? = nil
    ) -> String {
        let contextBlock = calendarContext.map { "Calendar context:\n\($0.promptContextSummary)\n\n" } ?? ""
        return """
        The user is in a live meeting and captured their current screen (attached image).
        \(contextBlock)Combine what is visible on screen with the recent meeting transcript to give a concise, high-signal insight or answer to whatever is being discussed or asked right now.

        Return only JSON with this exact shape:
        {
          "cards": [
            {
              "kind": "answer",
              "title": "Short headline about what's on screen",
              "body": "Clear, helpful takeaway or answer (1-4 sentences).",
              "source_references": ["Screen"],
              "confidence": 0.9
            }
          ]
        }

        Recent transcript:
        \(recentTranscript)
        """
    }

    public static func meetingWrapUpPrompt(
        title: String,
        transcript: String,
        calendarContext: MeetingCalendarContext? = nil
    ) -> String {
        let contextBlock = calendarContext.map { "Calendar context:\n\($0.promptContextSummary)\n\n" } ?? ""
        return """
        Create a crisp post-meeting wrap-up for "\(title)".
        \(contextBlock)Only use facts from the transcript. Return ONLY JSON with this exact shape:
        {
          "executive_summary": "2-3 sentence overview of what was covered.",
          "decisions": ["Concrete decision 1"],
          "action_items": ["Owner: concrete next step"],
          "follow_up_draft": "Short, ready-to-send Slack or email follow-up message."
        }

        Transcript:
        \(transcript)
        """
    }

    public static func jargonDecoderPrompt(terms: [String], recentTranscript: String) -> String {
        let joined = terms.joined(separator: ", ")
        return """
        Define these acronyms/terms mentioned in a live meeting as ultra-crisp 1-line glossary cards using the conversation context: \(joined).

        Return only JSON with this exact shape:
        {
          "cards": [
            {
              "kind": "answer",
              "title": "TERM — Short expansion",
              "body": "Plain-English 1-sentence explanation in this meeting's context.",
              "source_references": ["Glossary"],
              "confidence": 0.9
            }
          ]
        }

        Recent transcript:
        \(recentTranscript)
        """
    }

    public static func catchUpPrompt(
        recentTranscript: String,
        calendarContext: MeetingCalendarContext? = nil
    ) -> String {
        let contextBlock = calendarContext.map { "Calendar context:\n\($0.promptContextSummary)\n\n" } ?? ""
        return """
        The user briefly tuned out and clicked "What Did I Miss?" during a live meeting.
        \(contextBlock)Summarize the last ~2 minutes of transcript in at most 3 ultra-short bullet points so they can rejoin seamlessly.

        Return only JSON with this exact shape:
        {
          "cards": [
            {
              "kind": "follow_up",
              "title": "Catch-Up (Last 2 Min)",
              "body": "• Point 1\\n• Point 2\\n• Point 3",
              "source_references": ["Catch-Up"],
              "confidence": 0.95
            }
          ]
        }

        Recent transcript:
        \(recentTranscript)
        """
    }

    public static func preMeetingBriefPrompt(
        upcoming: MeetingCalendarContext,
        pastMeetingNotes: String
    ) -> String {
        """
        The user has a meeting starting in 2 minutes:
        \(upcoming.promptContextSummary)

        Create a crisp Pre-Meeting Brief (2-4 short bullets) summarizing what was decided last time and any open action items from past notes below.

        Return only JSON with this exact shape:
        {
          "cards": [
            {
              "kind": "follow_up",
              "title": "Pre-Meeting Brief: \(upcoming.title)",
              "body": "• Last time: ...\\n• Open items: ...",
              "source_references": ["Calendar"],
              "confidence": 0.9
            }
          ]
        }

        Past OmniSpeak meeting history:
        \(pastMeetingNotes)
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
