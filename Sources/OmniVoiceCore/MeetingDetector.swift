import Foundation

public enum DetectedMeetingApp: String, CaseIterable, Codable, Hashable, Sendable {
    case teams
    case facetime
    case phoneCall
    case zoom
    case googleMeet
    case slackHuddle
    case webex
    case discord

    public var displayName: String {
        switch self {
        case .teams: "Microsoft Teams"
        case .facetime: "FaceTime"
        case .phoneCall: "Phone Call"
        case .zoom: "Zoom"
        case .googleMeet: "Google Meet"
        case .slackHuddle: "Slack Huddle"
        case .webex: "Webex"
        case .discord: "Discord"
        }
    }

    public var systemImage: String {
        switch self {
        case .teams: "video.badge.waveform"
        case .facetime: "video.fill"
        case .phoneCall: "phone.fill"
        case .zoom: "video.circle.fill"
        case .googleMeet: "person.2.wave.2.fill"
        case .slackHuddle: "headphones"
        case .webex: "video.bubble.left.fill"
        case .discord: "waveform.circle.fill"
        }
    }

    public func defaultSessionTitle(at date: Date = Date()) -> String {
        "\(displayName) — \(date.formatted(date: .omitted, time: .shortened))"
    }
}

public struct DetectedMeetingEvent: Equatable, Hashable, Sendable {
    public let app: DetectedMeetingApp
    public let bundleIdentifier: String
    public let windowTitle: String?

    public init(app: DetectedMeetingApp, bundleIdentifier: String, windowTitle: String? = nil) {
        self.app = app
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
    }
}

public struct RunningWindowSnapshot: Equatable, Sendable {
    public let bundleIdentifier: String
    public let localizedName: String
    public let windowTitle: String

    public init(bundleIdentifier: String, localizedName: String, windowTitle: String) {
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.windowTitle = windowTitle
    }
}

/// Pure heuristic matcher that identifies an active Teams, FaceTime, Phone, Zoom,
/// Google Meet, Slack Huddle, Webex, or Discord call from running apps, window titles,
/// and whether the system microphone is currently active.
public enum MeetingAppMatcher {
    private static let browserBundleIDs: Set<String> = [
        "com.apple.safari",
        "com.google.chrome",
        "com.brave.browser",
        "com.microsoft.edgemac",
        "company.thebrowser.browser", // Arc
        "org.mozilla.firefox",
    ]

    public static func detect(
        runningBundleIDs: Set<String>,
        windows: [RunningWindowSnapshot],
        microphoneActive: Bool
    ) -> DetectedMeetingEvent? {
        let lowerBundles = Set(runningBundleIDs.map { $0.lowercased() })

        // 1. FaceTime / Continuity iPhone Phone Call
        if lowerBundles.contains("com.apple.facetime") {
            let ftWindow = windows.first { $0.bundleIdentifier.lowercased() == "com.apple.facetime" }
            let title = ftWindow?.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if microphoneActive || (title != nil && !title!.isEmpty && title!.lowercased() != "facetime") {
                let isPhone = title?.lowercased().contains("phone") == true
                    || title?.lowercased().contains("call") == true
                return DetectedMeetingEvent(
                    app: isPhone ? .phoneCall : .facetime,
                    bundleIdentifier: "com.apple.FaceTime",
                    windowTitle: title
                )
            }
        }
        // Continuity / macOS Phone call via CallServices / Phone app when mic is active
        if microphoneActive && (lowerBundles.contains("com.apple.phone") || lowerBundles.contains("com.apple.callservicesd")) {
            return DetectedMeetingEvent(
                app: .phoneCall,
                bundleIdentifier: "com.apple.FaceTime",
                windowTitle: "Phone Call"
            )
        }

        // 2. Microsoft Teams (New Teams + Classic Teams)
        for teamsID in ["com.microsoft.teams2", "com.microsoft.teams"] where lowerBundles.contains(teamsID) {
            let meetingWindow = windows.first {
                $0.bundleIdentifier.lowercased() == teamsID
                    && isTeamsMeetingTitle($0.windowTitle)
            }
            if let meetingWindow {
                return DetectedMeetingEvent(
                    app: .teams,
                    bundleIdentifier: meetingWindow.bundleIdentifier,
                    windowTitle: meetingWindow.windowTitle
                )
            }
            if microphoneActive {
                let anyTitle = windows.first { $0.bundleIdentifier.lowercased() == teamsID }?.windowTitle
                return DetectedMeetingEvent(
                    app: .teams,
                    bundleIdentifier: teamsID,
                    windowTitle: anyTitle
                )
            }
        }

        // 3. Zoom
        if lowerBundles.contains("us.zoom.xos") {
            let zoomMeeting = windows.first {
                $0.bundleIdentifier.lowercased() == "us.zoom.xos"
                    && $0.windowTitle.lowercased().contains("zoom meeting")
            }
            if let zoomMeeting {
                return DetectedMeetingEvent(
                    app: .zoom,
                    bundleIdentifier: zoomMeeting.bundleIdentifier,
                    windowTitle: zoomMeeting.windowTitle
                )
            }
            if microphoneActive {
                return DetectedMeetingEvent(app: .zoom, bundleIdentifier: "us.zoom.xos", windowTitle: "Zoom Meeting")
            }
        }

        // 4. Webex
        for webexID in ["cisco-systems.spark", "com.webex.meetingmanager"] where lowerBundles.contains(webexID) {
            if microphoneActive {
                let title = windows.first { $0.bundleIdentifier.lowercased() == webexID }?.windowTitle
                return DetectedMeetingEvent(app: .webex, bundleIdentifier: webexID, windowTitle: title)
            }
        }

        // 5. Slack Huddle
        if lowerBundles.contains("com.tinyspeck.slackmacgap") {
            let huddleWindow = windows.first {
                $0.bundleIdentifier.lowercased() == "com.tinyspeck.slackmacgap"
                    && $0.windowTitle.lowercased().contains("huddle")
            }
            if let huddleWindow, microphoneActive {
                return DetectedMeetingEvent(
                    app: .slackHuddle,
                    bundleIdentifier: huddleWindow.bundleIdentifier,
                    windowTitle: huddleWindow.windowTitle
                )
            }
        }

        // 6. Browser-based Google Meet / Teams Web / Zoom Web (requires active mic to avoid false positives on idle tabs)
        if microphoneActive {
            for window in windows where browserBundleIDs.contains(window.bundleIdentifier.lowercased()) {
                let lowerTitle = window.windowTitle.lowercased()
                if lowerTitle.contains("meet -") || lowerTitle.contains("google meet") || lowerTitle.contains("meet.google.com") {
                    return DetectedMeetingEvent(
                        app: .googleMeet,
                        bundleIdentifier: window.bundleIdentifier,
                        windowTitle: window.windowTitle
                    )
                }
                if lowerTitle.contains("microsoft teams") && (lowerTitle.contains("meeting") || lowerTitle.contains("call")) {
                    return DetectedMeetingEvent(
                        app: .teams,
                        bundleIdentifier: window.bundleIdentifier,
                        windowTitle: window.windowTitle
                    )
                }
            }
        }

        // 7. Discord voice call
        if microphoneActive && lowerBundles.contains("com.hnc.discord") {
            let title = windows.first { $0.bundleIdentifier.lowercased() == "com.hnc.discord" }?.windowTitle
            return DetectedMeetingEvent(app: .discord, bundleIdentifier: "com.hnc.discord", windowTitle: title)
        }

        return nil
    }

    private static func isTeamsMeetingTitle(_ title: String) -> Bool {
        let lower = title.lowercased()
        return lower.contains("meeting") || lower.contains("call with") || lower.contains("huddle")
    }
}

public enum MeetingCopilotCorner: String, CaseIterable, Codable, Hashable, Sendable {
    case topRight
    case topLeft

    public var displayName: String {
        switch self {
        case .topRight: "Top Right"
        case .topLeft: "Top Left"
        }
    }
}

/// Fast, zero-latency heuristic detector for spoken questions in a live meeting transcript.
public enum MeetingQuestionDetector {
    private static let interrogativePrefixes = [
        "what ", "whats ", "what's ", "how ", "why ", "when ", "where ", "who ", "which ",
        "can you ", "could you ", "would you ", "do you ", "did you ", "are you ", "is there ",
        "are there ", "have you ", "should we ", "will you ", "does anyone ", "any idea ",
    ]

    public static func looksLikeQuestion(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { return false }
        if trimmed.contains("?") {
            return true
        }
        let lower = trimmed.lowercased()
        return interrogativePrefixes.contains { lower.hasPrefix($0) || lower.contains(". \($0)") || lower.contains(", \($0)") }
    }
}

public struct MeetingCalendarContext: Equatable, Sendable {
    public let title: String
    public let attendees: [String]
    public let notes: String?
    public let startDate: Date?
    public let endDate: Date?

    public init(
        title: String,
        attendees: [String] = [],
        notes: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) {
        self.title = title
        self.attendees = attendees
        self.notes = notes
        self.startDate = startDate
        self.endDate = endDate
    }

    public var promptContextSummary: String {
        var parts: [String] = ["Meeting: \(title)"]
        if !attendees.isEmpty {
            parts.append("Attendees: \(attendees.prefix(12).joined(separator: ", "))")
        }
        if let notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            let clipped = notes.count > 400 ? String(notes.prefix(400)) + "…" : notes
            parts.append("Agenda/Notes: \(clipped)")
        }
        return parts.joined(separator: "\n")
    }
}

public struct MeetingTalkTimeStats: Equatable, Sendable {
    public let meMs: Int
    public let themMs: Int

    public init(meMs: Int = 0, themMs: Int = 0) {
        self.meMs = max(0, meMs)
        self.themMs = max(0, themMs)
    }

    public var totalMs: Int { meMs + themMs }

    public var meRatio: Double {
        guard totalMs > 0 else { return 0.5 }
        return Double(meMs) / Double(totalMs)
    }

    public var mePercent: Int {
        guard totalMs > 0 else { return 0 }
        return Int((meRatio * 100).rounded())
    }

    public var themPercent: Int {
        guard totalMs > 0 else { return 0 }
        return max(0, 100 - mePercent)
    }

    public static func compute(from segments: [ConversationSegment]) -> MeetingTalkTimeStats {
        var me = 0
        var them = 0
        for segment in segments where segment.state != .live {
            let duration = max(500, (segment.endMs ?? segment.startMs) - segment.startMs)
            let speakerID = segment.speakerID.lowercased()
            let label = segment.speakerDisplayName.lowercased()
            if speakerID == TwoTrackSpeaker.me.speakerID.lowercased() || label == "me" {
                me += duration
            } else {
                them += duration
            }
        }
        return MeetingTalkTimeStats(meMs: me, themMs: them)
    }
}

public struct MeetingWrapUpSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let executiveSummary: String
    public let decisions: [String]
    public let actionItems: [String]
    public let myPromises: [String]
    public let followUpDraft: String
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        title: String,
        executiveSummary: String,
        decisions: [String],
        actionItems: [String],
        myPromises: [String] = [],
        followUpDraft: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.executiveSummary = executiveSummary
        self.decisions = decisions
        self.actionItems = actionItems
        self.myPromises = myPromises
        self.followUpDraft = followUpDraft
        self.createdAt = createdAt
    }

    public func withPromises(_ promises: [String]) -> MeetingWrapUpSummary {
        var seen = Set<String>()
        let merged = (myPromises + promises).filter { item in
            let key = item.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !key.isEmpty && seen.insert(key).inserted
        }
        return MeetingWrapUpSummary(
            id: id,
            title: title,
            executiveSummary: executiveSummary,
            decisions: decisions,
            actionItems: actionItems,
            myPromises: merged,
            followUpDraft: followUpDraft,
            createdAt: createdAt
        )
    }

    public var markdownRecap: String {
        var lines: [String] = ["# \(title)", "", executiveSummary]
        if !decisions.isEmpty {
            lines.append("")
            lines.append("## Decisions")
            lines.append(contentsOf: decisions.map { "- \($0)" })
        }
        if !myPromises.isEmpty {
            lines.append("")
            lines.append("## My Promises")
            lines.append(contentsOf: myPromises.map { "- [ ] \($0)" })
        }
        if !actionItems.isEmpty {
            lines.append("")
            lines.append("## Action Items")
            lines.append(contentsOf: actionItems.map { "- [ ] \($0)" })
        }
        return lines.joined(separator: "\n")
    }

    public static func parse(from response: String, fallbackTitle: String) -> MeetingWrapUpSummary? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Try fenced or raw JSON extraction
        let candidateJSON: String
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start < end {
            candidateJSON = String(trimmed[start...end])
        } else {
            candidateJSON = trimmed
        }

        if let data = candidateJSON.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let summary = (dict["executive_summary"] as? String ?? dict["summary"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let decisions = (dict["decisions"] as? [String] ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let actionItems = (dict["action_items"] as? [String] ?? dict["actionItems"] as? [String] ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let followUp = (dict["follow_up_draft"] as? String ?? dict["followUpDraft"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !summary.isEmpty || !decisions.isEmpty || !actionItems.isEmpty {
                return MeetingWrapUpSummary(
                    title: fallbackTitle,
                    executiveSummary: summary.isEmpty ? "Meeting completed." : summary,
                    decisions: decisions,
                    actionItems: actionItems,
                    followUpDraft: followUp.isEmpty
                        ? "Hi everyone,\n\nThanks for the conversation today. Here are the key takeaways:\n\n\(summary)"
                        : followUp
                )
            }
        }

        return MeetingWrapUpSummary(
            title: fallbackTitle,
            executiveSummary: trimmed,
            decisions: [],
            actionItems: [],
            followUpDraft: "Hi everyone,\n\nThanks for meeting today. Quick recap:\n\n\(trimmed)"
        )
    }
}

/// Detects unfamiliar acronyms and technical jargon in finalized meeting speech
/// so Co-Pilot can pop a 1-line live glossary card.
public enum MeetingJargonDetector {
    private static let commonStopwords: Set<String> = [
        "THE", "AND", "FOR", "ARE", "BUT", "NOT", "YOU", "ALL", "CAN", "HER", "WAS", "ONE", "OUR",
        "OUT", "DAY", "GET", "HAS", "HIM", "HIS", "HOW", "MAN", "NEW", "NOW", "OLD", "SEE", "TWO",
        "WAY", "WHO", "YES", "YET", "USA", "USD", "EUR", "GBP", "EST", "PST", "CST", "MST", "UTC",
        "GMT", "PDF", "URL", "FAQ", "ASAP", "FYI", "CEO", "CTO", "CFO", "COO", "API", "APP", "MAC",
        "IOS", "CPU", "GPU", "RAM", "USB", "VPN", "DNS", "HTTP", "HTML", "JSON", "WIFI", "TEAM",
        "CALL", "ZOOM", "MEET", "OKAY", "YEAH", "COOL", "GOOD", "TIME", "WEEK", "YEAR", "DATE",
    ]

    public static func extractAcronyms(from text: String, excluding alreadySeen: Set<String> = []) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\b[A-Z][A-Z0-9]{2,5}\b"#) else {
            return []
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: nsRange)
        var seenInText = Set<String>()
        var results: [String] = []
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            let token = String(text[range])
            // Skip pure numbers or common everyday words
            guard token.contains(where: \.isLetter) else { continue }
            guard !commonStopwords.contains(token), !alreadySeen.contains(token) else { continue }
            if seenInText.insert(token).inserted {
                results.append(token)
            }
        }
        return results
    }
}

/// Detects spoken commitments & promises made by the user ("Me") during a live meeting.
public enum MeetingCommitmentDetector {
    private static let commitmentCues = [
        "i'll send", "i will send", "i'll share", "i will share",
        "i'll follow up", "i will follow up", "let me follow up",
        "i'll check", "i will check", "let me check",
        "i'll get that", "i will get that", "i'll get back",
        "i'll put together", "i will put together", "i'll write up",
        "i'll schedule", "i will schedule", "i'll set up",
        "i'll update", "i will update", "i'll review", "i will review",
        "i'll take care of", "i can send", "i can share", "let me send",
        "let me share", "i promise", "count on me to",
    ]

    public static func extractCommitment(
        from text: String,
        speakerID: String,
        speakerDisplayName: String
    ) -> String? {
        let isMe = speakerID.lowercased() == TwoTrackSpeaker.me.speakerID.lowercased()
            || speakerDisplayName.lowercased() == "me"
        guard isMe else { return nil }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12 else { return nil }
        let lower = trimmed.lowercased()
        guard commitmentCues.contains(where: { lower.contains($0) }) else {
            return nil
        }
        return trimmed
    }
}
