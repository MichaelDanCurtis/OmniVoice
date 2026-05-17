import XCTest
@testable import OmniVoiceCore

final class ConversationModelsTests: XCTestCase {
    func testConversationAudioSourceStoresDesignSourceFields() {
        let source = ConversationAudioSource(
            id: "source-1",
            sessionID: "session-1",
            kind: .systemAudio,
            displayName: "System Audio",
            isSeparatedTrack: true
        )

        XCTAssertEqual(source.sessionId, "session-1")
        XCTAssertEqual(source.kind, .systemAudio)
        XCTAssertEqual(source.displayName, "System Audio")
        XCTAssertTrue(source.isSeparatedTrack)
    }

    func testConversationAudioSourceDecodesSnakeCaseEnginePayload() throws {
        let data = #"{"id":"source-1","session_id":"session-1","kind":"system_audio","display_name":"System Audio","is_separated_track":true}"#
            .data(using: .utf8)!

        let source = try EngineCoding.decoder.decode(ConversationAudioSource.self, from: data)

        XCTAssertEqual(source.sessionID, "session-1")
        XCTAssertEqual(source.kind, .systemAudio)
        XCTAssertEqual(source.displayName, "System Audio")
        XCTAssertTrue(source.isSeparatedTrack)
    }

    func testSpeakerIdentityDefaultsToGenericName() {
        let speaker = ConversationSpeakerIdentity(
            id: "speaker-1",
            displayName: "Speaker 1",
            origin: .generic,
            colorHex: "#FDE047"
        )

        XCTAssertEqual(speaker.displayName, "Speaker 1")
        XCTAssertEqual(speaker.origin, .generic)
    }

    func testSpeakerIdentityDecodesSnakeCaseEnginePayload() throws {
        let data = ##"{"id":"speaker-1","display_name":"Speaker 1","origin":"user_confirmed","color_hex":"#FDE047"}"##
            .data(using: .utf8)!

        let speaker = try EngineCoding.decoder.decode(ConversationSpeakerIdentity.self, from: data)

        XCTAssertEqual(speaker.displayName, "Speaker 1")
        XCTAssertEqual(speaker.origin, .userConfirmed)
        XCTAssertEqual(speaker.colorHex, "#FDE047")
    }

    func testSegmentUsesSpeakerDisplayName() {
        let segment = ConversationSegment(
            id: "seg-1",
            sessionID: "session-1",
            speakerID: "speaker-1",
            speakerDisplayName: "Bob",
            startMs: 18_130,
            endMs: 21_900,
            text: "How many users did we have last year?",
            state: .settled,
            confidence: 0.91
        )

        XCTAssertEqual(segment.timestampLabel, "00:18")
        XCTAssertEqual(segment.sessionId, "session-1")
        XCTAssertEqual(segment.sessionID, "session-1")
        XCTAssertEqual(segment.speakerId, "speaker-1")
        XCTAssertEqual(segment.speakerID, "speaker-1")
        XCTAssertEqual(segment.speakerDisplayName, "Bob")
        XCTAssertEqual(segment.state, .settled)
    }

    func testSegmentDecodesSnakeCaseEnginePayload() throws {
        let data = #"{"id":"seg-1","session_id":"session-1","speaker_id":"speaker-1","speaker_display_name":"Bob","start_ms":18130,"end_ms":21900,"text":"How many users did we have last year?","state":"settled","confidence":0.91}"#
            .data(using: .utf8)!

        let segment = try EngineCoding.decoder.decode(ConversationSegment.self, from: data)

        XCTAssertEqual(segment.sessionId, "session-1")
        XCTAssertEqual(segment.speakerId, "speaker-1")
        XCTAssertEqual(segment.speakerDisplayName, "Bob")
        XCTAssertEqual(segment.startMs, 18_130)
        XCTAssertEqual(segment.endMs, 21_900)
    }

    func testAssistCardCopyTextUsesBodyOnly() {
        let card = ConversationAssistCard(
            id: "card-1",
            sessionID: "session-1",
            kind: .answer,
            title: "Answer Found",
            body: "Last year we had 18,420 active users.",
            sourceReferences: ["Obsidian/adoption-2025.md"],
            confidence: 0.78,
            status: .active,
            createdAt: "2026-05-17T08:00:00Z"
        )

        XCTAssertEqual(card.copyText, "Last year we had 18,420 active users.")
        XCTAssertEqual(card.sessionId, "session-1")
        XCTAssertEqual(card.sourceReferences, ["Obsidian/adoption-2025.md"])
    }

    func testAssistCardDecodesSnakeCaseEnginePayload() throws {
        let data = #"{"id":"card-1","session_id":"session-1","kind":"answer","title":"Answer Found","body":"Last year we had 18,420 active users.","source_references":["Obsidian/adoption-2025.md"],"confidence":0.78,"status":"active","created_at":"2026-05-17T08:00:00Z"}"#
            .data(using: .utf8)!

        let card = try EngineCoding.decoder.decode(ConversationAssistCard.self, from: data)

        XCTAssertEqual(card.sessionId, "session-1")
        XCTAssertEqual(card.sessionID, "session-1")
        XCTAssertEqual(card.sourceReferences, ["Obsidian/adoption-2025.md"])
        XCTAssertEqual(card.createdAt, "2026-05-17T08:00:00Z")
    }

    func testConversationSessionDetectsActiveState() {
        let active = ConversationSession(
            id: "session-1",
            title: "Conversation",
            startedAt: "2026-05-17T08:00:00Z",
            endedAt: nil,
            captureMode: .microphoneOnly,
            asrProvider: "parakeet-tdt",
            diarizationProvider: "mock",
            externalProcessingEnabled: false
        )

        XCTAssertTrue(active.isActive)
    }

    func testConversationSessionStoresSourceIDsAndDefaultsToEmpty() {
        let defaultSources = ConversationSession(
            id: "session-1",
            title: "Conversation",
            startedAt: "2026-05-17T08:00:00Z",
            captureMode: .microphoneOnly,
            asrProvider: "parakeet-tdt",
            diarizationProvider: "mock",
            externalProcessingEnabled: false
        )
        let session = ConversationSession(
            id: "session-2",
            title: "Conversation",
            startedAt: "2026-05-17T08:00:00Z",
            captureMode: .microphoneAndSystemAudio,
            asrProvider: "parakeet-tdt",
            diarizationProvider: "mock",
            externalProcessingEnabled: false,
            sourceIDs: ["source-mic", "source-system"]
        )

        XCTAssertEqual(defaultSources.sourceIDs, [])
        XCTAssertEqual(session.sourceIDs, ["source-mic", "source-system"])
    }

    func testConversationSessionDecodesSnakeCaseSourceIDs() throws {
        let data = #"{"id":"session-1","title":"Conversation","started_at":"2026-05-17T08:00:00Z","ended_at":null,"capture_mode":"microphone_and_system_audio","asr_provider":"parakeet-tdt","diarization_provider":"mock","external_processing_enabled":false,"source_ids":["source-mic","source-system"]}"#
            .data(using: .utf8)!

        let session = try EngineCoding.decoder.decode(ConversationSession.self, from: data)

        XCTAssertEqual(session.sourceIDs, ["source-mic", "source-system"])
    }

    func testConversationSessionDecodesMissingSourceIDsAsEmpty() throws {
        let data = #"{"id":"session-1","title":"Conversation","started_at":"2026-05-17T08:00:00Z","ended_at":null,"capture_mode":"microphone_only","asr_provider":"parakeet-tdt","diarization_provider":"mock","external_processing_enabled":false}"#
            .data(using: .utf8)!

        let session = try EngineCoding.decoder.decode(ConversationSession.self, from: data)

        XCTAssertEqual(session.sourceIDs, [])
    }

    func testConversationSessionEncodesSourceIDsAsSnakeCase() throws {
        let session = ConversationSession(
            id: "session-1",
            title: "Conversation",
            startedAt: "2026-05-17T08:00:00Z",
            captureMode: .microphoneAndSystemAudio,
            asrProvider: "parakeet-tdt",
            diarizationProvider: "mock",
            externalProcessingEnabled: false,
            sourceIDs: ["source-mic", "source-system"]
        )

        let data = try EngineCoding.encoder.encode(session)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["source_ids"] as? [String], ["source-mic", "source-system"])
        XCTAssertNil(object["source_i_ds"])
    }

    func testSpeakerTurnStoresTimingAndProviderMetadata() {
        let turn = SpeakerTurn(
            id: "turn-1",
            sessionID: "session-1",
            speakerID: "speaker-1",
            startMs: 18_130,
            endMs: 21_900,
            confidence: 0.86,
            overlap: true,
            sourceProvider: "mock"
        )

        XCTAssertEqual(turn.sessionId, "session-1")
        XCTAssertEqual(turn.sessionID, "session-1")
        XCTAssertEqual(turn.speakerId, "speaker-1")
        XCTAssertEqual(turn.speakerID, "speaker-1")
        XCTAssertEqual(turn.startMs, 18_130)
        XCTAssertEqual(turn.endMs, 21_900)
        XCTAssertEqual(turn.confidence, 0.86)
        XCTAssertTrue(turn.overlap)
        XCTAssertEqual(turn.sourceProvider, "mock")
    }

    func testSpeakerTurnDecodesSnakeCaseEnginePayload() throws {
        let data = #"{"id":"turn-1","session_id":"session-1","speaker_id":"speaker-1","start_ms":18130,"end_ms":21900,"confidence":0.86,"overlap":true,"source_provider":"mock"}"#
            .data(using: .utf8)!

        let turn = try EngineCoding.decoder.decode(SpeakerTurn.self, from: data)

        XCTAssertEqual(turn.sessionID, "session-1")
        XCTAssertEqual(turn.speakerID, "speaker-1")
        XCTAssertEqual(turn.startMs, 18_130)
        XCTAssertEqual(turn.endMs, 21_900)
        XCTAssertEqual(turn.sourceProvider, "mock")
    }
}
