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
    case whatsapp
    case signal
    case telegram
    case ringCentral
    case dialpad
    case chime
    case upcomingMeeting
    case twoWayCall

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
        case .whatsapp: "WhatsApp"
        case .signal: "Signal"
        case .telegram: "Telegram"
        case .ringCentral: "RingCentral"
        case .dialpad: "Dialpad"
        case .chime: "Amazon Chime"
        case .upcomingMeeting: "Upcoming Meeting"
        case .twoWayCall: "Two-Way Call"
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
        case .whatsapp: "phone.bubble.left.fill"
        case .signal: "lock.shield.fill"
        case .telegram: "paperplane.fill"
        case .ringCentral: "phone.connection.fill"
        case .dialpad: "phone.arrow.up.right.fill"
        case .chime: "video.fill"
        case .upcomingMeeting: "calendar.badge.clock"
        case .twoWayCall: "phone.and.waveform.fill"
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
    public let isPreJoin: Bool

    public init(
        app: DetectedMeetingApp,
        bundleIdentifier: String,
        windowTitle: String? = nil,
        isPreJoin: Bool = false
    ) {
        self.app = app
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.isPreJoin = isPreJoin
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

/// Pure heuristic matcher that identifies an active or about-to-join Teams, FaceTime, Phone,
/// Zoom, Google Meet, Slack Huddle, Webex, Discord, WhatsApp, Signal, Telegram, RingCentral,
/// Dialpad, Chime, or generic two-way call from running apps, window titles, and CoreAudio state.
public enum MeetingAppMatcher {
    private static let browserBundleIDs: Set<String> = [
        "com.apple.safari",
        "com.google.chrome",
        "com.google.chrome.canary",
        "com.brave.browser",
        "com.microsoft.edgemac",
        "company.thebrowser.browser", // Arc
        "org.mozilla.firefox",
        "com.vivaldi.vivaldi",
        "com.operasoftware.opera",
    ]

    private static let nonCallAudioBundleIDs: Set<String> = [
        "com.omnispeak.omnivoiceapp",
        "com.apple.logic10",
        "com.apple.garageband10",
        "com.apple.quicktimeplayerx",
        "com.apple.voicememos",
        "com.obsproject.obs-studio",
        "com.loom.desktop",
    ]

    public static func detect(
        runningBundleIDs: Set<String>,
        windows: [RunningWindowSnapshot],
        microphoneActive: Bool,
        systemAudioActive: Bool = false,
        frontmostBundleID: String? = nil
    ) -> DetectedMeetingEvent? {
        let lowerBundles = Set(runningBundleIDs.map { $0.lowercased() })

        // 1. FaceTime / Continuity iPhone Phone Call
        if lowerBundles.contains("com.apple.facetime") {
            let ftWindow = windows.first { $0.bundleIdentifier.lowercased() == "com.apple.facetime" }
            let title = ftWindow?.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowerTitle = title?.lowercased() ?? ""
            let looksLikeCallWindow = !lowerTitle.isEmpty && lowerTitle != "facetime"
            if microphoneActive || looksLikeCallWindow {
                let isPhone = lowerTitle.contains("phone") || lowerTitle.contains("call")
                let isPreJoin = !microphoneActive && (lowerTitle.contains("incoming") || lowerTitle.contains("ringing") || lowerTitle.contains("join"))
                return DetectedMeetingEvent(
                    app: isPhone ? .phoneCall : .facetime,
                    bundleIdentifier: "com.apple.FaceTime",
                    windowTitle: title,
                    isPreJoin: isPreJoin
                )
            }
        }
        // Continuity / macOS Phone call via CallServices / Phone app when mic is active
        if microphoneActive && (
            lowerBundles.contains("com.apple.phone")
                || lowerBundles.contains("com.apple.mobilephone")
                || lowerBundles.contains("com.apple.callservicesd")
        ) {
            return DetectedMeetingEvent(
                app: .phoneCall,
                bundleIdentifier: "com.apple.FaceTime",
                windowTitle: "Phone Call"
            )
        }

        // 2. Microsoft Teams (New Teams, Classic Teams, and Teams Chrome/Edge PWAs)
        let teamsWindows = windows.filter { isTeamsWindow($0) }
        let hasTeamsApp = lowerBundles.contains("com.microsoft.teams2")
            || lowerBundles.contains("com.microsoft.teams")
            || !teamsWindows.isEmpty

        if hasTeamsApp {
            // 2a. Explicit Teams pre-join lobby or meeting/call window title (works even before mic turns on!)
            if let meetingWindow = teamsWindows.first(where: { isTeamsMeetingOrPreJoinTitle($0.windowTitle) }) {
                return DetectedMeetingEvent(
                    app: .teams,
                    bundleIdentifier: meetingWindow.bundleIdentifier,
                    windowTitle: meetingWindow.windowTitle,
                    isPreJoin: !microphoneActive && isPreJoinTitle(meetingWindow.windowTitle)
                )
            }

            // 2b. Popped-out native Teams meeting/pre-join window heuristic:
            // New Teams opens a second window for pre-join lobbies and active calls even when the
            // meeting title doesn't literally contain the word "meeting" or "call".
            let nativeTeamsWindows = windows.filter {
                let id = $0.bundleIdentifier.lowercased()
                return id == "com.microsoft.teams2" || id == "com.microsoft.teams"
            }
            let titledNativeTeams = nativeTeamsWindows.filter {
                !$0.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if titledNativeTeams.count >= 2,
               let poppedWindow = titledNativeTeams.first(where: { !isGenericTeamsNavigationTitle($0.windowTitle) }) {
                return DetectedMeetingEvent(
                    app: .teams,
                    bundleIdentifier: poppedWindow.bundleIdentifier,
                    windowTitle: poppedWindow.windowTitle,
                    isPreJoin: !microphoneActive
                )
            }

            // 2c. Active mic while Teams native/PWA is running
            if microphoneActive {
                let primaryTeamsBundle = lowerBundles.contains("com.microsoft.teams2")
                    ? "com.microsoft.teams2"
                    : (lowerBundles.contains("com.microsoft.teams")
                        ? "com.microsoft.teams"
                        : (teamsWindows.first?.bundleIdentifier ?? "com.microsoft.teams2"))
                let anyTitle = teamsWindows.first?.windowTitle
                return DetectedMeetingEvent(
                    app: .teams,
                    bundleIdentifier: primaryTeamsBundle,
                    windowTitle: anyTitle
                )
            }
        }

        // 3. Zoom (active or pre-join waiting room)
        if lowerBundles.contains("us.zoom.xos") {
            let zoomMeeting = windows.first {
                let lowerTitle = $0.windowTitle.lowercased()
                return $0.bundleIdentifier.lowercased() == "us.zoom.xos"
                    && (lowerTitle.contains("zoom meeting")
                        || lowerTitle.contains("waiting room")
                        || lowerTitle.contains("join a meeting")
                        || lowerTitle.contains("zoom webinar"))
            }
            if let zoomMeeting {
                return DetectedMeetingEvent(
                    app: .zoom,
                    bundleIdentifier: zoomMeeting.bundleIdentifier,
                    windowTitle: zoomMeeting.windowTitle,
                    isPreJoin: !microphoneActive && isPreJoinTitle(zoomMeeting.windowTitle)
                )
            }
            if microphoneActive {
                return DetectedMeetingEvent(app: .zoom, bundleIdentifier: "us.zoom.xos", windowTitle: "Zoom Meeting")
            }
        }

        // 4. Webex
        for webexID in ["cisco-systems.spark", "com.webex.meetingmanager"] where lowerBundles.contains(webexID) {
            let preJoinWindow = windows.first {
                $0.bundleIdentifier.lowercased() == webexID && isPreJoinTitle($0.windowTitle)
            }
            if let preJoinWindow {
                return DetectedMeetingEvent(
                    app: .webex,
                    bundleIdentifier: preJoinWindow.bundleIdentifier,
                    windowTitle: preJoinWindow.windowTitle,
                    isPreJoin: !microphoneActive
                )
            }
            if microphoneActive {
                let title = windows.first { $0.bundleIdentifier.lowercased() == webexID }?.windowTitle
                return DetectedMeetingEvent(app: .webex, bundleIdentifier: webexID, windowTitle: title)
            }
        }

        // 5. Slack Huddle (active mic OR open Huddle window)
        if lowerBundles.contains("com.tinyspeck.slackmacgap") {
            let huddleWindow = windows.first {
                $0.bundleIdentifier.lowercased() == "com.tinyspeck.slackmacgap"
                    && $0.windowTitle.lowercased().contains("huddle")
            }
            if let huddleWindow, microphoneActive || isPreJoinTitle(huddleWindow.windowTitle) {
                return DetectedMeetingEvent(
                    app: .slackHuddle,
                    bundleIdentifier: huddleWindow.bundleIdentifier,
                    windowTitle: huddleWindow.windowTitle,
                    isPreJoin: !microphoneActive
                )
            }
        }

        // 6. Browser-based Teams Web / Google Meet / Zoom Web / browser calling apps
        for window in windows where isBrowserOrWebApp(window.bundleIdentifier) {
            let lowerTitle = window.windowTitle.lowercased()

            // Teams Web: detect pre-join lobby EVEN BEFORE mic activates, and any Teams tab when mic is active
            let isTeamsTab = lowerTitle.contains("microsoft teams")
                || lowerTitle.contains("teams.microsoft.com")
                || lowerTitle.contains("teams.live.com")
            if isTeamsTab {
                if isTeamsMeetingOrPreJoinTitle(window.windowTitle) {
                    return DetectedMeetingEvent(
                        app: .teams,
                        bundleIdentifier: window.bundleIdentifier,
                        windowTitle: window.windowTitle,
                        isPreJoin: !microphoneActive
                    )
                }
                if microphoneActive {
                    return DetectedMeetingEvent(
                        app: .teams,
                        bundleIdentifier: window.bundleIdentifier,
                        windowTitle: window.windowTitle
                    )
                }
            }

            // Google Meet: detect pre-join lobby ("ready to join" / "getting ready") or active mic tab
            let isMeetTab = lowerTitle.contains("meet -")
                || lowerTitle.contains("google meet")
                || lowerTitle.contains("meet.google.com")
            if isMeetTab {
                if !microphoneActive && (lowerTitle.contains("ready to join") || lowerTitle.contains("getting ready")) {
                    return DetectedMeetingEvent(
                        app: .googleMeet,
                        bundleIdentifier: window.bundleIdentifier,
                        windowTitle: window.windowTitle,
                        isPreJoin: true
                    )
                }
                if microphoneActive {
                    return DetectedMeetingEvent(
                        app: .googleMeet,
                        bundleIdentifier: window.bundleIdentifier,
                        windowTitle: window.windowTitle
                    )
                }
            }

            // Zoom Web / Whereby / Jitsi / Dialpad / RingCentral / Google Voice in browser when mic is active
            if microphoneActive {
                if lowerTitle.contains("zoom") && (lowerTitle.contains("meeting") || lowerTitle.contains("join")) {
                    return DetectedMeetingEvent(app: .zoom, bundleIdentifier: window.bundleIdentifier, windowTitle: window.windowTitle)
                }
                if lowerTitle.contains("ringcentral") {
                    return DetectedMeetingEvent(app: .ringCentral, bundleIdentifier: window.bundleIdentifier, windowTitle: window.windowTitle)
                }
                if lowerTitle.contains("dialpad") {
                    return DetectedMeetingEvent(app: .dialpad, bundleIdentifier: window.bundleIdentifier, windowTitle: window.windowTitle)
                }
                if lowerTitle.contains("google voice") || lowerTitle.contains("openphone") || lowerTitle.contains("aircall") {
                    return DetectedMeetingEvent(app: .phoneCall, bundleIdentifier: window.bundleIdentifier, windowTitle: window.windowTitle)
                }
            }
        }

        // 7. Native VoIP / Messaging / Conferencing apps (Discord, WhatsApp, Signal, Telegram, RingCentral, Dialpad, Chime)
        let commsApps: [(bundleIDs: [String], app: DetectedMeetingApp)] = [
            (["com.hnc.discord"], .discord),
            (["net.whatsapp.whatsapp", "desktop.whatsapp"], .whatsapp),
            (["org.whispersystems.signal-desktop"], .signal),
            (["ru.keepcoder.telegram", "org.telegram.desktop"], .telegram),
            (["com.ringcentral.glip", "com.ringcentral.ringcentral"], .ringCentral),
            (["com.dialpad.dialpad", "com.electron.dialpad"], .dialpad),
            (["com.amazon.amazonchime"], .chime),
        ]
        for entry in commsApps {
            if let matchedID = entry.bundleIDs.first(where: { lowerBundles.contains($0) }) {
                let callWindow = windows.first {
                    $0.bundleIdentifier.lowercased() == matchedID && isGenericCallTitle($0.windowTitle)
                }
                if let callWindow {
                    return DetectedMeetingEvent(
                        app: entry.app,
                        bundleIdentifier: callWindow.bundleIdentifier,
                        windowTitle: callWindow.windowTitle,
                        isPreJoin: !microphoneActive
                    )
                }
                if microphoneActive {
                    let title = windows.first { $0.bundleIdentifier.lowercased() == matchedID }?.windowTitle
                    return DetectedMeetingEvent(app: entry.app, bundleIdentifier: matchedID, windowTitle: title)
                }
            }
        }

        // 8. Generic Two-Way Call Fallback (ANY app with BOTH microphone + system audio output active!)
        if microphoneActive && systemAudioActive {
            let candidateBundle = frontmostBundleID?.lowercased()
            let chosenWindow: RunningWindowSnapshot? = {
                if let candidateBundle, !nonCallAudioBundleIDs.contains(candidateBundle),
                   let frontWin = windows.first(where: { $0.bundleIdentifier.lowercased() == candidateBundle }) {
                    return frontWin
                }
                return windows.first(where: { !nonCallAudioBundleIDs.contains($0.bundleIdentifier.lowercased()) })
            }()
            let bundle = chosenWindow?.bundleIdentifier ?? frontmostBundleID ?? "system.two-way-call"
            guard !nonCallAudioBundleIDs.contains(bundle.lowercased()) else { return nil }
            let appLabel = chosenWindow?.localizedName.trimmingCharacters(in: .whitespacesAndNewlines)
            let title: String?
            if let winTitle = chosenWindow?.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines), !winTitle.isEmpty {
                title = winTitle
            } else if let appLabel, !appLabel.isEmpty {
                title = "Active call in \(appLabel)"
            } else {
                title = "Two-Way Audio Active"
            }
            return DetectedMeetingEvent(
                app: .twoWayCall,
                bundleIdentifier: bundle,
                windowTitle: title
            )
        }

        return nil
    }

    private static func isBrowserOrWebApp(_ bundleID: String) -> Bool {
        let lower = bundleID.lowercased()
        if browserBundleIDs.contains(lower) { return true }
        // Chrome / Edge / Brave PWAs installed as standalone macOS app shims
        return lower.hasPrefix("com.google.chrome.app.")
            || lower.hasPrefix("com.microsoft.edgemac.app.")
            || lower.hasPrefix("com.brave.browser.app.")
    }

    private static func isTeamsWindow(_ window: RunningWindowSnapshot) -> Bool {
        let id = window.bundleIdentifier.lowercased()
        if id == "com.microsoft.teams2" || id == "com.microsoft.teams" || id.hasPrefix("com.microsoft.teams.") {
            return true
        }
        if isBrowserOrWebApp(id) {
            let name = window.localizedName.lowercased()
            let title = window.windowTitle.lowercased()
            if name.contains("microsoft teams") || (name.contains("teams") && id.contains(".app.")) {
                return true
            }
            if title.contains("microsoft teams") || title.contains("teams.microsoft.com") {
                return true
            }
        }
        return false
    }

    private static func isTeamsMeetingOrPreJoinTitle(_ title: String) -> Bool {
        let lower = title.lowercased()
        let cues = [
            "meeting", "call with", "huddle", "join", "lobby", "waiting",
            "choose your audio", "pre-join", "prejoin", "calling",
            "incoming call", "standup", "stand-up", "town hall", "webinar",
        ]
        return cues.contains { lower.contains($0) }
    }

    private static func isGenericTeamsNavigationTitle(_ title: String) -> Bool {
        let lower = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.isEmpty || lower == "microsoft teams" || lower == "teams" {
            return true
        }
        let navPrefixes = ["chat |", "activity |", "calendar |", "teams |", "calls |", "files |", "apps |", "planner |"]
        return navPrefixes.contains { lower.hasPrefix($0) }
    }

    private static func isPreJoinTitle(_ title: String) -> Bool {
        let lower = title.lowercased()
        let cues = ["join", "lobby", "waiting", "choose your audio", "pre-join", "prejoin", "ready to join", "incoming", "ringing"]
        return cues.contains { lower.contains($0) }
    }

    private static func isGenericCallTitle(_ title: String) -> Bool {
        let lower = title.lowercased()
        return lower.contains("voice call")
            || lower.contains("video call")
            || lower.contains("incoming call")
            || lower.contains("calling")
            || lower.contains("in a call")
            || lower.contains("huddle")
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
