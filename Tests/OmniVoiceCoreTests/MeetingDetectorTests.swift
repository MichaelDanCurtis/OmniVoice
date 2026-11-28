import XCTest
@testable import OmniVoiceCore

final class MeetingDetectorTests: XCTestCase {
    func testDetectsMicrosoftTeamsMeetingWithActiveMic() {
        let event = MeetingAppMatcher.detect(
            runningBundleIDs: ["com.microsoft.teams2"],
            windows: [
                RunningWindowSnapshot(
                    bundleIdentifier: "com.microsoft.teams2",
                    localizedName: "Microsoft Teams",
                    windowTitle: "Weekly Standup | Meeting | Microsoft Teams"
                ),
            ],
            microphoneActive: true
        )
        XCTAssertEqual(event?.app, .teams)
    }

    func testDetectsFaceTimeAndPhoneCalls() {
        let facetime = MeetingAppMatcher.detect(
            runningBundleIDs: ["com.apple.FaceTime"],
            windows: [
                RunningWindowSnapshot(
                    bundleIdentifier: "com.apple.FaceTime",
                    localizedName: "FaceTime",
                    windowTitle: "Alex Rivera"
                ),
            ],
            microphoneActive: true
        )
        XCTAssertEqual(facetime?.app, .facetime)

        let phone = MeetingAppMatcher.detect(
            runningBundleIDs: ["com.apple.FaceTime"],
            windows: [
                RunningWindowSnapshot(
                    bundleIdentifier: "com.apple.FaceTime",
                    localizedName: "FaceTime",
                    windowTitle: "Phone Call with Sam"
                ),
            ],
            microphoneActive: true
        )
        XCTAssertEqual(phone?.app, .phoneCall)
    }

    func testDetectsGoogleMeetInBrowserOnlyWhenMicIsActive() {
        let window = RunningWindowSnapshot(
            bundleIdentifier: "com.google.Chrome",
            localizedName: "Google Chrome",
            windowTitle: "Meet - abc-defg-hij"
        )
        XCTAssertNil(
            MeetingAppMatcher.detect(
                runningBundleIDs: ["com.google.Chrome"],
                windows: [window],
                microphoneActive: false
            )
        )
        let detected = MeetingAppMatcher.detect(
            runningBundleIDs: ["com.google.Chrome"],
            windows: [window],
            microphoneActive: true
        )
        XCTAssertEqual(detected?.app, .googleMeet)
    }

    func testDetectsTeamsPreJoinLobbyBeforeMicActivates() {
        let lobby = MeetingAppMatcher.detect(
            runningBundleIDs: ["com.microsoft.teams2"],
            windows: [
                RunningWindowSnapshot(
                    bundleIdentifier: "com.microsoft.teams2",
                    localizedName: "Microsoft Teams",
                    windowTitle: "Chat | Microsoft Teams"
                ),
                RunningWindowSnapshot(
                    bundleIdentifier: "com.microsoft.teams2",
                    localizedName: "Microsoft Teams",
                    windowTitle: "Choose your audio and video settings | Microsoft Teams"
                ),
            ],
            microphoneActive: false
        )
        XCTAssertEqual(lobby?.app, .teams)
        XCTAssertEqual(lobby?.isPreJoin, true)

        // Popped-out second Teams window with a custom meeting title (no "meeting" keyword)
        let popped = MeetingAppMatcher.detect(
            runningBundleIDs: ["com.microsoft.teams2"],
            windows: [
                RunningWindowSnapshot(
                    bundleIdentifier: "com.microsoft.teams2",
                    localizedName: "Microsoft Teams",
                    windowTitle: "Calendar | Microsoft Teams"
                ),
                RunningWindowSnapshot(
                    bundleIdentifier: "com.microsoft.teams2",
                    localizedName: "Microsoft Teams",
                    windowTitle: "Q4 Architecture Review"
                ),
            ],
            microphoneActive: false
        )
        XCTAssertEqual(popped?.app, .teams)
        XCTAssertEqual(popped?.isPreJoin, true)
        XCTAssertEqual(popped?.windowTitle, "Q4 Architecture Review")
    }

    func testDetectsTeamsWebPreJoinAndActiveTabInBrowser() {
        let preJoin = MeetingAppMatcher.detect(
            runningBundleIDs: ["com.microsoft.edgemac"],
            windows: [
                RunningWindowSnapshot(
                    bundleIdentifier: "com.microsoft.edgemac",
                    localizedName: "Microsoft Edge",
                    windowTitle: "Join conversation | Microsoft Teams"
                ),
            ],
            microphoneActive: false
        )
        XCTAssertEqual(preJoin?.app, .teams)
        XCTAssertEqual(preJoin?.isPreJoin, true)

        let active = MeetingAppMatcher.detect(
            runningBundleIDs: ["com.google.Chrome"],
            windows: [
                RunningWindowSnapshot(
                    bundleIdentifier: "com.google.Chrome",
                    localizedName: "Google Chrome",
                    windowTitle: "Weekly Design Sync | Microsoft Teams"
                ),
            ],
            microphoneActive: true
        )
        XCTAssertEqual(active?.app, .teams)
    }

    func testDetectsGenericTwoWayCallWhenMicAndSystemAudioBothActive() {
        let detected = MeetingAppMatcher.detect(
            runningBundleIDs: ["com.example.CustomDialer"],
            windows: [
                RunningWindowSnapshot(
                    bundleIdentifier: "com.example.CustomDialer",
                    localizedName: "Custom Dialer",
                    windowTitle: "Call with Jamie"
                ),
            ],
            microphoneActive: true,
            systemAudioActive: true,
            frontmostBundleID: "com.example.CustomDialer"
        )
        XCTAssertEqual(detected?.app, .twoWayCall)
        XCTAssertEqual(detected?.windowTitle, "Call with Jamie")

        // Must NOT fire for OmniSpeak itself
        let selfIgnored = MeetingAppMatcher.detect(
            runningBundleIDs: ["com.omnispeak.OmniVoiceApp"],
            windows: [
                RunningWindowSnapshot(
                    bundleIdentifier: "com.omnispeak.OmniVoiceApp",
                    localizedName: "OmniSpeak",
                    windowTitle: "Control Panel"
                ),
            ],
            microphoneActive: true,
            systemAudioActive: true,
            frontmostBundleID: "com.omnispeak.OmniVoiceApp"
        )
        XCTAssertNil(selfIgnored)
    }

    func testQuestionDetectorIdentifiesSpokenQuestions() {
        XCTAssertTrue(MeetingQuestionDetector.looksLikeQuestion("What is our target launch date?"))
        XCTAssertTrue(MeetingQuestionDetector.looksLikeQuestion("Can you remind me how we handle token refresh"))
        XCTAssertFalse(MeetingQuestionDetector.looksLikeQuestion("Sounds good to me."))
        XCTAssertFalse(MeetingQuestionDetector.looksLikeQuestion("Okay"))
    }

    func testTalkTimeStatsComputeMeVersusThemBalance() {
        let segments = [
            ConversationSegment(
                id: "1",
                sessionID: "s1",
                speakerID: TwoTrackSpeaker.me.speakerID,
                speakerDisplayName: "Me",
                startMs: 0,
                endMs: 4_000,
                text: "Hello everyone",
                state: .settled
            ),
            ConversationSegment(
                id: "2",
                sessionID: "s1",
                speakerID: TwoTrackSpeaker.them.speakerID,
                speakerDisplayName: "Them",
                startMs: 4_000,
                endMs: 10_000,
                text: "Thanks for joining",
                state: .settled
            ),
        ]
        let stats = MeetingTalkTimeStats.compute(from: segments)
        XCTAssertEqual(stats.mePercent, 40)
        XCTAssertEqual(stats.themPercent, 60)
    }

    func testMeetingWrapUpSummaryParsesStructuredJSON() {
        let json = """
        ```json
        {
          "executive_summary": "Aligned on the Q4 ship date.",
          "decisions": ["Ship on Dec 3"],
          "action_items": ["Alex: finalize release notes"],
          "follow_up_draft": "Thanks all — we're set for Dec 3."
        }
        ```
        """
        let summary = MeetingWrapUpSummary.parse(from: json, fallbackTitle: "Q4 Launch")
        XCTAssertEqual(summary?.title, "Q4 Launch")
        XCTAssertEqual(summary?.executiveSummary, "Aligned on the Q4 ship date.")
        XCTAssertEqual(summary?.decisions, ["Ship on Dec 3"])
        XCTAssertEqual(summary?.actionItems, ["Alex: finalize release notes"])
        XCTAssertEqual(summary?.followUpDraft, "Thanks all — we're set for Dec 3.")
    }

    func testJargonDetectorExtractsUnfamiliarAcronymsAndSkipsStopwords() {
        let terms = MeetingJargonDetector.extractAcronyms(
            from: "We need SOC2 compliance and better NRR before the API launch with EBITDA targets.",
            excluding: ["EBITDA"]
        )
        XCTAssertEqual(terms, ["SOC2", "NRR"])
    }

    func testCommitmentDetectorTracksFirstPersonPromisesFromMeOnly() {
        XCTAssertEqual(
            MeetingCommitmentDetector.extractCommitment(
                from: "I'll send the updated architecture deck by Friday.",
                speakerID: TwoTrackSpeaker.me.speakerID,
                speakerDisplayName: "Me"
            ),
            "I'll send the updated architecture deck by Friday."
        )
        XCTAssertNil(
            MeetingCommitmentDetector.extractCommitment(
                from: "I'll send the updated architecture deck by Friday.",
                speakerID: TwoTrackSpeaker.them.speakerID,
                speakerDisplayName: "Them"
            )
        )
        XCTAssertNil(
            MeetingCommitmentDetector.extractCommitment(
                from: "Sounds like a solid plan.",
                speakerID: TwoTrackSpeaker.me.speakerID,
                speakerDisplayName: "Me"
            )
        )
    }
}
