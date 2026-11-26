import Foundation
import OmniVoiceCore

/// Meeting Co-Pilot Pro: calendar context, auto-detected calls, live insights,
/// screen-aware answers, moment bookmarks, catch-up, promises, jargon decoding,
/// pre-meeting briefs, and post-call wrap-ups.
extension AppModel {
    func refreshCalendarAuthorizationStatus() {
        calendarAccessGranted = calendarService.isAuthorized
    }

    func connectMeetingCalendar() async {
        let granted = await calendarService.requestAccess()
        calendarAccessGranted = granted
        statusText = granted
            ? "Calendar connected for meeting context"
            : "Calendar access denied — grant access in System Settings"
    }

    func startDetectedMeeting(_ event: DetectedMeetingEvent) async {
        if preferences.conversationCaptureMode != .microphoneAndSystemAudio {
            preferences.conversationCaptureMode = .microphoneAndSystemAudio
            _ = persistPreferences()
        }
        if preferences.conversationDiarizationProvider == "off",
           let ready = diarizationProviderStatuses.first(where: { $0.id != "off" && $0.available }) {
            preferences.conversationDiarizationProvider = ready.id
            _ = persistPreferences()
        }
        meetingStartedByAutoDetect = true
        let calendarContext = calendarService.currentMeetingContext()
        let title = calendarContext?.title ?? event.app.defaultSessionTitle()
        await startConversationRecording(title: title, calendarContext: calendarContext)
    }

    func handleDetectedCallEnded() async {
        guard meetingStartedByAutoDetect,
              preferences.meetingAutoStopOnCallEnd,
              isConversationRecording else {
            return
        }
        meetingStartedByAutoDetect = false
        await stopConversationRecording()
    }

    func startMeetingCopilotLoop(title: String) {
        meetingCopilotLoopTask?.cancel()
        let subtitle: String?
        if let attendees = activeMeetingCalendarContext?.attendees, !attendees.isEmpty {
            subtitle = "With \(attendees.prefix(3).joined(separator: ", "))"
        } else {
            subtitle = nil
        }
        onMeetingCopilotSessionChanged?(title, subtitle, true)
        meetingCopilotLoopTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled, let self, self.isConversationRecording else { break }
                guard self.preferences.meetingLiveCopilotEnabled else { continue }
                await self.runLiveMeetingInsightPass(force: false)
            }
        }
    }

    func stopMeetingCopilotLoop(keepPinnedModals: Bool) {
        meetingCopilotLoopTask?.cancel()
        meetingCopilotLoopTask = nil
        onMeetingCopilotAnalyzingChanged?(false)
        onMeetingCopilotSessionChanged?(nil, nil, keepPinnedModals)
    }

    func captureScreenAndAnswerInMeeting() async {
        guard isConversationRecording, let session = activeConversation else { return }
        onMeetingCopilotAnalyzingChanged?(true)
        defer { onMeetingCopilotAnalyzingChanged?(false) }

        guard let attachment = await MeetingScreenCaptureHelper.captureMainDisplayAttachment() else {
            onMeetingCopilotModal?(
                MeetingCopilotModalItem(
                    id: "screen-err-\(UUID().uuidString)",
                    kind: .warning,
                    title: "Screen capture unavailable",
                    body: "Grant Screen Recording permission in System Settings to enable screen-aware meeting answers.",
                    questionText: nil,
                    speakerLabel: "Screen",
                    createdAt: Date()
                )
            )
            return
        }

        let recentLines = conversationSegments
            .filter { $0.state != .live }
            .suffix(10)
            .map { "\($0.speakerDisplayName): \($0.text)" }
            .joined(separator: "\n")

        let responseText = await synthesizeMeetingAIResponse(
            systemPrompt: ConversationInsightSynthesis.systemPrompt,
            userPrompt: ConversationInsightSynthesis.screenAwareAnswerPrompt(
                recentTranscript: recentLines.isEmpty ? "_No speech yet._" : recentLines,
                calendarContext: activeMeetingCalendarContext
            ),
            attachments: [attachment]
        )
        guard let responseText else { return }

        let requests = ConversationInsightSynthesis.cardRequests(from: responseText)
        let cardRequest = requests.first ?? ConversationAssistCardCreateRequest(
            kind: .answer,
            title: "Screen Insight",
            body: responseText.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceReferences: ["Screen"],
            confidence: 0.85
        )
        if let card = try? await engineClient.addConversationAssistCard(sessionID: session.id, request: cardRequest) {
            conversationAssistCards.append(card)
            onMeetingCopilotModal?(
                MeetingCopilotModalItem(
                    id: card.id,
                    kind: .answer,
                    title: card.title,
                    body: card.body,
                    questionText: nil,
                    speakerLabel: "Screen",
                    createdAt: Date()
                )
            )
        }
    }

    func bookmarkCurrentMeetingMoment() async {
        guard isConversationRecording, let session = activeConversation else { return }
        let latest = conversationSegments.last(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        let excerpt = latest?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Flagged key moment during meeting."
        let speaker = latest?.speakerDisplayName ?? "Bookmark"
        let request = ConversationAssistCardCreateRequest(
            kind: .followUp,
            title: "Bookmarked Moment",
            body: excerpt,
            sourceReferences: [speaker],
            confidence: 1.0
        )
        if let card = try? await engineClient.addConversationAssistCard(sessionID: session.id, request: request) {
            conversationAssistCards.append(card)
            var modal = MeetingCopilotModalItem(
                id: card.id,
                kind: .followUp,
                title: "Bookmarked Moment",
                body: excerpt,
                questionText: nil,
                speakerLabel: speaker,
                createdAt: Date()
            )
            modal.isPinned = true
            onMeetingCopilotModal?(modal)
        }
    }

    func generateMeetingWrapUp(
        title: String,
        segments: [ConversationSegment],
        promises: [String],
        calendarContext: MeetingCalendarContext?
    ) async {
        let transcript = segments
            .map { "\($0.speakerDisplayName): \($0.text)" }
            .joined(separator: "\n")
        guard !transcript.isEmpty else { return }

        let responseText = await synthesizeMeetingAIResponse(
            systemPrompt: ConversationInsightSynthesis.systemPrompt,
            userPrompt: ConversationInsightSynthesis.meetingWrapUpPrompt(
                title: title,
                transcript: transcript,
                calendarContext: calendarContext
            )
        )
        guard let responseText,
              let parsed = MeetingWrapUpSummary.parse(from: responseText, fallbackTitle: title) else {
            return
        }
        onMeetingWrapUpReady?(parsed.withPromises(promises))
    }

    func catchUpLastTwoMinutesInMeeting() async {
        guard isConversationRecording else { return }
        let settled = conversationSegments.filter {
            $0.state != .live && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !settled.isEmpty else {
            onMeetingCopilotModal?(
                MeetingCopilotModalItem(
                    id: "catchup-empty-\(UUID().uuidString)",
                    kind: .followUp,
                    title: "Catch-Up (Last 2 Min)",
                    body: "No settled speech yet in this meeting.",
                    questionText: nil,
                    speakerLabel: "Catch-Up",
                    createdAt: Date()
                )
            )
            return
        }

        let maxMs = settled.compactMap(\.endMs).max() ?? (settled.last?.startMs ?? 0)
        let cutoffMs = max(0, maxMs - 120_000)
        let recent = settled.filter { ($0.endMs ?? $0.startMs) >= cutoffMs }
        let windowSegments = recent.isEmpty ? Array(settled.suffix(12)) : Array(recent.suffix(20))
        let transcript = windowSegments
            .map { "\($0.speakerDisplayName): \($0.text)" }
            .joined(separator: "\n")

        onMeetingCopilotAnalyzingChanged?(true)
        defer { onMeetingCopilotAnalyzingChanged?(false) }

        let responseText = await synthesizeMeetingAIResponse(
            systemPrompt: ConversationInsightSynthesis.systemPrompt,
            userPrompt: ConversationInsightSynthesis.catchUpPrompt(
                recentTranscript: transcript,
                calendarContext: activeMeetingCalendarContext
            )
        )
        guard let responseText else { return }

        let requests = ConversationInsightSynthesis.cardRequests(from: responseText)
        let body = requests.first?.body ?? responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        var modal = MeetingCopilotModalItem(
            id: "catchup-\(UUID().uuidString)",
            kind: .followUp,
            title: requests.first?.title ?? "Catch-Up (Last 2 Min)",
            body: body,
            questionText: nil,
            speakerLabel: "Catch-Up",
            createdAt: Date()
        )
        modal.isPinned = false
        onMeetingCopilotModal?(modal)
    }

    func recordMeetingPromise(_ promise: String) async {
        guard isConversationRecording, let session = activeConversation else { return }
        guard !activeMeetingPromises.contains(where: { $0.caseInsensitiveCompare(promise) == .orderedSame }) else {
            return
        }
        activeMeetingPromises.append(promise)

        let request = ConversationAssistCardCreateRequest(
            kind: .actionItem,
            title: "My Promise",
            body: promise,
            sourceReferences: ["Me"],
            confidence: 0.95
        )
        if let card = try? await engineClient.addConversationAssistCard(sessionID: session.id, request: request) {
            conversationAssistCards.append(card)
            var modal = MeetingCopilotModalItem(
                id: card.id,
                kind: .actionItem,
                title: "Promise Tracked",
                body: promise,
                questionText: nil,
                speakerLabel: "Me",
                createdAt: Date()
            )
            modal.isPinned = true
            onMeetingCopilotModal?(modal)
        }
    }

    func decodeLiveMeetingJargon(terms: [String]) async {
        guard isConversationRecording, !terms.isEmpty else { return }
        let recentLines = conversationSegments
            .filter { $0.state != .live }
            .suffix(8)
            .map { "\($0.speakerDisplayName): \($0.text)" }
            .joined(separator: "\n")

        let responseText = await synthesizeMeetingAIResponse(
            systemPrompt: ConversationInsightSynthesis.systemPrompt,
            userPrompt: ConversationInsightSynthesis.jargonDecoderPrompt(
                terms: terms,
                recentTranscript: recentLines
            )
        )
        guard let responseText else { return }
        let requests = ConversationInsightSynthesis.cardRequests(from: responseText)
        for request in requests.prefix(2) {
            onMeetingCopilotModal?(
                MeetingCopilotModalItem(
                    id: "jargon-\(UUID().uuidString)",
                    kind: .answer,
                    title: request.title,
                    body: request.body,
                    questionText: nil,
                    speakerLabel: "Glossary",
                    createdAt: Date()
                )
            )
        }
    }

    func startPreMeetingBriefMonitor() {
        preMeetingBriefMonitorTask?.cancel()
        preMeetingBriefMonitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self else { break }
                guard self.preferences.meetingLiveCopilotEnabled,
                      !self.isConversationRecording else { continue }
                await self.checkUpcomingPreMeetingBrief()
            }
        }
    }

    func stopPreMeetingBriefMonitor() {
        preMeetingBriefMonitorTask?.cancel()
        preMeetingBriefMonitorTask = nil
    }

    private func checkUpcomingPreMeetingBrief() async {
        guard let upcoming = calendarService.upcomingMeetingSoon(withinMinutes: 3.0) else {
            return
        }
        let startStamp = Int((upcoming.startDate ?? Date()).timeIntervalSince1970 / 60)
        let eventKey = "\(upcoming.title.lowercased())|\(startStamp)"
        guard preBriefedEventKeys.insert(eventKey).inserted else { return }

        if conversationSessions.isEmpty {
            await loadConversations()
        }

        let tokens = Set(
            upcoming.title
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 4 }
        )
        let matchingSessions = conversationSessions.filter { session in
            let lowerTitle = session.title.lowercased()
            return tokens.contains { lowerTitle.contains($0) }
        }.prefix(2)

        var pastNotes: [String] = []
        for session in matchingSessions {
            if let detail = try? await engineClient.conversationDetail(sessionID: session.id) {
                let cards = detail.assistCards.prefix(4).map { "• \($0.title): \($0.body)" }
                let tail = detail.segments.suffix(6).map { "\($0.speakerDisplayName): \($0.text)" }
                pastNotes.append("Past meeting '\(session.title)':\n" + (cards + tail).joined(separator: "\n"))
            }
        }

        let briefBody: String
        if !pastNotes.isEmpty,
           let response = await synthesizeMeetingAIResponse(
               systemPrompt: ConversationInsightSynthesis.systemPrompt,
               userPrompt: ConversationInsightSynthesis.preMeetingBriefPrompt(
                   upcoming: upcoming,
                   pastMeetingNotes: pastNotes.joined(separator: "\n\n")
               )
           ),
           let first = ConversationInsightSynthesis.cardRequests(from: response).first {
            briefBody = first.body
        } else {
            var lines: [String] = ["Starts in ~2 min."]
            if !upcoming.attendees.isEmpty {
                lines.append("Attendees: \(upcoming.attendees.prefix(5).joined(separator: ", "))")
            }
            if let notes = upcoming.notes, !notes.isEmpty {
                lines.append("Agenda: \(notes.prefix(180))")
            }
            briefBody = lines.joined(separator: "\n")
        }

        var modal = MeetingCopilotModalItem(
            id: "prebrief-\(eventKey)",
            kind: .followUp,
            title: "Pre-Meeting Brief: \(upcoming.title)",
            body: briefBody,
            questionText: nil,
            speakerLabel: "Starting Soon",
            createdAt: Date()
        )
        modal.isPinned = true
        onMeetingCopilotModal?(modal)
    }

    func runLiveMeetingInsightPass(force: Bool = false) async {
        guard isConversationRecording, !isGeneratingConversationInsights else { return }
        let settled = conversationSegments.filter {
            $0.state != .live && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !settled.isEmpty else { return }
        guard force || settled.count > lastCopilotAnalyzedSegmentCount else { return }
        guard let session = activeConversation else { return }

        let detail = ConversationDetail(
            session: session,
            segments: settled,
            assistCards: conversationAssistCards
        )
        isGeneratingConversationInsights = true
        onMeetingCopilotAnalyzingChanged?(true)
        defer {
            isGeneratingConversationInsights = false
            onMeetingCopilotAnalyzingChanged?(false)
        }

        let responseText = await synthesizeMeetingAIResponse(
            systemPrompt: ConversationInsightSynthesis.systemPrompt,
            userPrompt: ConversationInsightSynthesis.userPrompt(for: detail, maxCards: 3)
        )
        lastCopilotAnalyzedSegmentCount = settled.count
        guard let responseText else { return }

        let requests = nonDuplicateInsightRequests(
            ConversationInsightSynthesis.cardRequests(from: responseText),
            existingCards: conversationAssistCards
        )
        guard !requests.isEmpty else { return }

        for request in requests {
            if let card = try? await engineClient.addConversationAssistCard(sessionID: session.id, request: request) {
                conversationAssistCards.append(card)
                onMeetingCopilotModal?(
                    MeetingCopilotModalItem(
                        id: card.id,
                        kind: card.kind,
                        title: card.title,
                        body: card.body,
                        questionText: nil,
                        speakerLabel: card.sourceReferences.first,
                        createdAt: Date()
                    )
                )
            }
        }
    }

    func answerLiveMeetingQuestion(segment: ConversationSegment) async {
        guard isConversationRecording, let session = activeConversation else { return }
        let recentLines = conversationSegments
            .filter { $0.state != .live }
            .suffix(12)
            .map { "\($0.speakerDisplayName): \($0.text)" }
            .joined(separator: "\n")

        onMeetingCopilotAnalyzingChanged?(true)
        defer { onMeetingCopilotAnalyzingChanged?(false) }

        let responseText = await synthesizeMeetingAIResponse(
            systemPrompt: ConversationInsightSynthesis.systemPrompt,
            userPrompt: ConversationInsightSynthesis.liveQuestionAnswerPrompt(
                question: segment.text,
                speakerName: segment.speakerDisplayName,
                recentTranscript: recentLines,
                calendarContext: activeMeetingCalendarContext
            )
        )
        guard let responseText else { return }

        let requests = ConversationInsightSynthesis.cardRequests(from: responseText)
        guard let first = requests.first else { return }

        if let card = try? await engineClient.addConversationAssistCard(sessionID: session.id, request: first) {
            conversationAssistCards.append(card)
            onMeetingCopilotModal?(
                MeetingCopilotModalItem(
                    id: card.id,
                    kind: .answer,
                    title: card.title,
                    body: card.body,
                    questionText: segment.text,
                    speakerLabel: segment.speakerDisplayName,
                    createdAt: Date()
                )
            )
        }
    }

    /// Runs a meeting Co-Pilot prompt through Service Mode (if active) or the configured
    /// cloud/OAuth Text LLM, falling back cleanly to a discovered local AI agent CLI.
    func synthesizeMeetingAIResponse(
        systemPrompt: String,
        userPrompt: String,
        attachments: [AIChatAttachment] = []
    ) async -> String? {
        if preferences.serviceMode.enabled,
           let routed = await runServiceModeLLM(
               systemPrompt: systemPrompt,
               userPrompt: userPrompt,
               attachments: attachments
           ) {
            return routed
        }

        if let configuration = configuredConversationTextLLMConfiguration() {
            do {
                let result = try await engineClient.aiChat(
                    AIChatRequest(
                        provider: configuration.provider.rawValue,
                        baseURL: configuration.resolvedBaseURL,
                        model: configuration.trimmedModel,
                        apiKey: configuration.trimmedAPIKey,
                        transport: configuration.transport,
                        oauthAccessToken: configuration.trimmedOAuthAccessToken,
                        headers: configuration.resolvedHeaders,
                        messages: [
                            AIChatMessage(role: .system, content: systemPrompt),
                            AIChatMessage(role: .user, content: userPrompt),
                        ],
                        attachments: attachments,
                        webSearchEnabled: conversationAIWebSearchEnabled
                    )
                )
                return result.text
            } catch {
                // Fall through to local agent fallback if available.
            }
        }

        if attachments.isEmpty, let localAgent = discoveredAgents.first?.descriptor {
            let combinedPrompt = "\(systemPrompt)\n\n\(userPrompt)"
            return try? await meetingAgentRunner.run(localAgent, prompt: combinedPrompt, onChunk: { _ in })
        }

        return nil
    }
}
