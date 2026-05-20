import XCTest
@testable import OmniVoiceCore

final class ConversationModelsTests: XCTestCase {
    func testFallbackFinalSegmentTurnsLastLivePreviewIntoSettledSegment() throws {
        let audio = Data("pcm-window".utf8)
        let liveRequest = ConversationSegmentCreateRequest(
            speakerID: "speaker-2",
            speakerDisplayName: "Speaker 2",
            startMs: 4_500,
            endMs: 6_000,
            text: "  Speaker one and speaker two are both visible.  ",
            state: .live,
            confidence: 0.42
        )

        let finalRequest = try XCTUnwrap(
            ConversationSegmentFinalization.fallbackSettledRequest(
                from: liveRequest,
                recordingEndMs: 12_000,
                audioPCMFloat32: audio,
                audioSampleRate: 48_000
            )
        )

        XCTAssertNil(finalRequest.speakerID)
        XCTAssertNil(finalRequest.speakerDisplayName)
        XCTAssertEqual(finalRequest.audioStartMs, 0)
        XCTAssertEqual(finalRequest.startMs, 0)
        XCTAssertEqual(finalRequest.endMs, 12_000)
        XCTAssertEqual(finalRequest.text, "Speaker one and speaker two are both visible.")
        XCTAssertEqual(finalRequest.state, .settled)
        XCTAssertEqual(finalRequest.confidence, 0.42)
        XCTAssertEqual(finalRequest.audioPCMFloat32Base64, audio.base64EncodedString())
        XCTAssertEqual(finalRequest.audioSampleRate, 48_000)
    }

    func testFallbackFinalSegmentIgnoresMissingLiveText() {
        let liveRequest = ConversationSegmentCreateRequest(
            startMs: 4_500,
            endMs: 6_000,
            text: "   ",
            state: .live
        )

        XCTAssertNil(
            ConversationSegmentFinalization.fallbackSettledRequest(
                from: liveRequest,
                recordingEndMs: 12_000,
                audioPCMFloat32: nil,
                audioSampleRate: 48_000
            )
        )
    }

    func testConversationAIChatContextBuildsTranscriptAttachmentAndMessages() {
        let detail = ConversationDetail(
            session: ConversationSession(
                id: "session-1",
                title: "Roadmap call",
                startedAt: "2026-05-20T07:00:00Z",
                endedAt: "2026-05-20T07:15:00Z",
                captureMode: .microphoneOnly,
                asrProvider: "parakeet-tdt-mlx",
                diarizationProvider: "mlx-sortformer-streaming-fp32",
                externalProcessingEnabled: false
            ),
            segments: [
                ConversationSegment(
                    id: "segment-1",
                    sessionID: "session-1",
                    speakerID: "speaker-1",
                    speakerDisplayName: "Speaker 1",
                    startMs: 2_000,
                    endMs: 4_000,
                    text: "We need to call Jane tomorrow.",
                    state: .settled
                )
            ]
        )

        let attachment = ConversationAIChatContext.transcriptAttachment(for: detail)
        let messages = ConversationAIChatContext.messages(
            history: [AskAIMessage(role: .assistant, text: "Previous answer.")],
            question: "What follow-up did we discuss?"
        )

        XCTAssertEqual(attachment.kind, .conversation)
        XCTAssertEqual(attachment.title, "Roadmap call")
        XCTAssertTrue(attachment.text.contains("Speaker 1"))
        XCTAssertTrue(attachment.text.contains("We need to call Jane tomorrow."))
        XCTAssertEqual(messages.first?.role, .system)
        XCTAssertTrue(messages.first?.content.contains("Only answer from the supplied transcript") ?? false)
        XCTAssertEqual(messages.last, AIChatMessage(role: .user, content: "What follow-up did we discuss?"))
    }

    func testConversationArchiveFormatsReadableMarkdownTranscript() {
        let detail = ConversationDetail(
            session: ConversationSession(
                id: "session-1",
                title: "Roadmap call",
                startedAt: "2026-05-17T08:00:00Z",
                endedAt: "2026-05-17T08:12:00Z",
                captureMode: .microphoneOnly,
                asrProvider: "parakeet-tdt",
                diarizationProvider: "mlx-sortformer-streaming-fp16",
                externalProcessingEnabled: false
            ),
            segments: [
                ConversationSegment(
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
            ],
            assistCards: [
                ConversationAssistCard(
                    id: "card-1",
                    sessionID: "session-1",
                    kind: .answer,
                    title: "Answer Found",
                    body: "Last year we had 18,420 active users.",
                    sourceReferences: ["Obsidian/adoption-2025.md"],
                    confidence: 0.78,
                    createdAt: "2026-05-17T08:00:30Z"
                )
            ]
        )

        let markdown = ConversationArchive.markdown(for: detail)

        XCTAssertTrue(markdown.contains("# Roadmap call"))
        XCTAssertTrue(markdown.contains("Started: 2026-05-17T08:00:00Z"))
        XCTAssertTrue(markdown.contains("Bob [00:18]: How many users did we have last year?"))
        XCTAssertTrue(markdown.contains("## Assist Cards"))
        XCTAssertTrue(markdown.contains("Answer Found"))
        XCTAssertTrue(markdown.contains("Obsidian/adoption-2025.md"))
    }

    func testConversationArchiveUsesDiarizedTranscriptLinesWhenAvailable() {
        let detail = ConversationDetail(
            session: ConversationSession(
                id: "session-1",
                title: "Speaker test",
                startedAt: "2026-05-17T08:00:00Z",
                endedAt: "2026-05-17T08:12:00Z",
                captureMode: .microphoneOnly,
                asrProvider: "parakeet-tdt-mlx",
                diarizationProvider: "mlx-sortformer-streaming-fp32",
                externalProcessingEnabled: false
            ),
            segments: [
                ConversationSegment(
                    id: "seg-1",
                    sessionID: "session-1",
                    speakerID: "speaker-1",
                    speakerDisplayName: "Bob",
                    startMs: 0,
                    endMs: 3_500,
                    text: "Bob asked one question. Sarah answered clearly. Bob followed up.",
                    state: .settled,
                    speakerTurns: [
                        SpeakerTurn(
                            id: "turn-1",
                            sessionID: "session-1",
                            speakerID: "speaker-1",
                            startMs: 0,
                            endMs: 1_000,
                            overlap: false,
                            sourceProvider: "mlx-sortformer-streaming-fp32"
                        ),
                        SpeakerTurn(
                            id: "turn-2",
                            sessionID: "session-1",
                            speakerID: "speaker-2",
                            startMs: 1_000,
                            endMs: 2_500,
                            overlap: false,
                            sourceProvider: "mlx-sortformer-streaming-fp32"
                        ),
                        SpeakerTurn(
                            id: "turn-3",
                            sessionID: "session-1",
                            speakerID: "speaker-1",
                            startMs: 2_500,
                            endMs: 3_500,
                            overlap: false,
                            sourceProvider: "mlx-sortformer-streaming-fp32"
                        ),
                    ]
                )
            ],
            assistCards: []
        )

        let markdown = ConversationArchive.markdown(for: detail)

        XCTAssertTrue(markdown.contains("Bob [00:00]: Bob asked one question."))
        XCTAssertTrue(markdown.contains("Speaker 2 [00:01]: Sarah answered clearly."))
        XCTAssertTrue(markdown.contains("Bob [00:02]: Bob followed up."))
    }

    func testConversationArchiveWritesDocumentBundle() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let detail = ConversationDetail(
            session: ConversationSession(
                id: "session-1",
                title: "Roadmap / Call?",
                startedAt: "2026-05-17T08:00:00Z",
                endedAt: "2026-05-17T08:12:00Z",
                captureMode: .microphoneOnly,
                asrProvider: "parakeet-tdt",
                diarizationProvider: "none",
                externalProcessingEnabled: false
            ),
            segments: [
                ConversationSegment(
                    id: "seg-1",
                    sessionID: "session-1",
                    speakerID: "speaker-1",
                    speakerDisplayName: "Speaker 1",
                    startMs: 1_000,
                    text: "First saved line.",
                    state: .settled
                )
            ],
            assistCards: []
        )

        let folder = try ConversationArchive.write(detail, rootURL: root)

        XCTAssertEqual(folder.deletingLastPathComponent().lastPathComponent, "Conversations")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appending(path: "transcript.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appending(path: "transcript.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appending(path: "assist-cards.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appending(path: "metadata.json").path))

        let transcript = try String(contentsOf: folder.appending(path: "transcript.md"), encoding: .utf8)
        XCTAssertTrue(transcript.contains("Speaker 1 [00:01]: First saved line."))
    }

    func testConversationArchiveDefaultRootUsesDocumentsOmniVoice() {
        let documents = URL(filePath: "/Users/tester/Documents", directoryHint: .isDirectory)

        let root = ConversationArchive.defaultRootURL(documentsURL: documents)

        XCTAssertEqual(root.path, "/Users/tester/Documents/OmniVoice")
    }

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

    func testSegmentDecodesDiarizationSpeakerTurns() throws {
        let data = #"{"id":"seg-1","session_id":"session-1","speaker_id":"speaker-2","speaker_display_name":"Speaker 2","start_ms":1000,"end_ms":3200,"text":"Bob asked and Sarah answered.","state":"settled","confidence":0.74,"speaker_turns":[{"id":"turn-1","session_id":"session-1","speaker_id":"speaker-1","start_ms":250,"end_ms":1200,"confidence":0.81,"overlap":false,"source_provider":"mlx-sortformer-streaming-fp32"},{"id":"turn-2","session_id":"session-1","speaker_id":"speaker-2","start_ms":1200,"end_ms":3200,"confidence":0.74,"overlap":false,"source_provider":"mlx-sortformer-streaming-fp32"}]}"#
            .data(using: .utf8)!

        let segment = try EngineCoding.decoder.decode(ConversationSegment.self, from: data)

        XCTAssertEqual(segment.speakerTurns.map(\.speakerID), ["speaker-1", "speaker-2"])
        XCTAssertEqual(segment.speakerTurns[0].startMs, 250)
        XCTAssertEqual(segment.speakerTurns[1].sourceProvider, "mlx-sortformer-streaming-fp32")
    }

    func testSegmentDecodesBackendSpeakerLines() throws {
        let data = #"{"id":"seg-1","session_id":"session-1","speaker_id":"speaker-2","speaker_display_name":"Speaker 2","start_ms":1000,"end_ms":3200,"text":"Bob asked and Sarah answered.","state":"settled","confidence":0.74,"speaker_lines":[{"id":"line-1","session_id":"session-1","speaker_id":"speaker-1","start_ms":250,"end_ms":1200,"text":"Bob asked.","confidence":0.81,"source_provider":"mlx-sortformer-streaming-fp32"},{"id":"line-2","session_id":"session-1","speaker_id":"speaker-2","start_ms":1200,"end_ms":3200,"text":"Sarah answered.","confidence":0.74,"source_provider":"mlx-sortformer-streaming-fp32"}]}"#
            .data(using: .utf8)!

        let segment = try EngineCoding.decoder.decode(ConversationSegment.self, from: data)

        XCTAssertEqual(segment.speakerLines.map(\.speakerID), ["speaker-1", "speaker-2"])
        XCTAssertEqual(segment.speakerLines.map(\.text), ["Bob asked.", "Sarah answered."])
        XCTAssertEqual(segment.speakerLines[0].sourceProvider, "mlx-sortformer-streaming-fp32")
    }

    func testSegmentDiarizedTranscriptLinesPreferBackendSpeakerLines() {
        let segment = ConversationSegment(
            id: "seg-1",
            sessionID: "session-1",
            speakerID: "speaker-2",
            speakerDisplayName: "Speaker 2",
            startMs: 0,
            endMs: 3_000,
            text: "This should not be proportionally split.",
            state: .settled,
            speakerTurns: [
                SpeakerTurn(
                    id: "turn-1",
                    sessionID: "session-1",
                    speakerID: "speaker-1",
                    startMs: 0,
                    endMs: 3_000,
                    overlap: false,
                    sourceProvider: "mlx-sortformer-streaming-fp32"
                )
            ],
            speakerLines: [
                ConversationSpeakerLine(
                    id: "line-1",
                    sessionID: "session-1",
                    speakerID: "speaker-1",
                    startMs: 0,
                    endMs: 1_000,
                    text: "Bob asked.",
                    sourceProvider: "mlx-sortformer-streaming-fp32"
                ),
                ConversationSpeakerLine(
                    id: "line-2",
                    sessionID: "session-1",
                    speakerID: "speaker-2",
                    startMs: 1_000,
                    endMs: 3_000,
                    text: "Sarah answered.",
                    sourceProvider: "mlx-sortformer-streaming-fp32"
                ),
            ]
        )

        let lines = segment.diarizedTranscriptLines

        XCTAssertEqual(lines.map(\.speakerID), ["speaker-1", "speaker-2"])
        XCTAssertEqual(lines.map(\.text), ["Bob asked.", "Sarah answered."])
    }

    func testSegmentDiarizedTranscriptLinesFallsBackToTurnsWhenBackendLinesMissSpeakers() {
        let segment = ConversationSegment(
            id: "seg-1",
            sessionID: "session-1",
            speakerID: "speaker-1",
            speakerDisplayName: "Speaker 1",
            startMs: 0,
            endMs: 3_000,
            text: "Bob asked one question. Sarah answered clearly.",
            state: .settled,
            speakerTurns: [
                SpeakerTurn(
                    id: "turn-1",
                    sessionID: "session-1",
                    speakerID: "speaker-1",
                    startMs: 0,
                    endMs: 1_400,
                    overlap: false,
                    sourceProvider: "mlx-sortformer-streaming-fp32"
                ),
                SpeakerTurn(
                    id: "turn-2",
                    sessionID: "session-1",
                    speakerID: "speaker-2",
                    startMs: 1_400,
                    endMs: 3_000,
                    overlap: false,
                    sourceProvider: "mlx-sortformer-streaming-fp32"
                ),
            ],
            speakerLines: [
                ConversationSpeakerLine(
                    id: "line-1",
                    sessionID: "session-1",
                    speakerID: "speaker-1",
                    startMs: 0,
                    endMs: 1_400,
                    text: "Bob asked one question.",
                    sourceProvider: "mlx-sortformer-streaming-fp32"
                ),
            ]
        )

        let lines = segment.diarizedTranscriptLines

        XCTAssertEqual(lines.map(\.speakerID), ["speaker-1", "speaker-2"])
        XCTAssertEqual(lines.map(\.text), ["Bob asked one question.", "Sarah answered clearly."])
    }

    func testSegmentBuildsSpeakerTranscriptLinesFromDiarizationTurns() {
        let segment = ConversationSegment(
            id: "seg-1",
            sessionID: "session-1",
            speakerID: "speaker-1",
            speakerDisplayName: "Bob",
            startMs: 0,
            endMs: 3_500,
            text: "Bob asked one question. Sarah answered clearly. Bob followed up.",
            state: .settled,
            speakerTurns: [
                SpeakerTurn(
                    id: "turn-1",
                    sessionID: "session-1",
                    speakerID: "speaker-1",
                    startMs: 0,
                    endMs: 1_000,
                    overlap: false,
                    sourceProvider: "mlx-sortformer-streaming-fp32"
                ),
                SpeakerTurn(
                    id: "turn-2",
                    sessionID: "session-1",
                    speakerID: "speaker-2",
                    startMs: 1_000,
                    endMs: 2_500,
                    overlap: false,
                    sourceProvider: "mlx-sortformer-streaming-fp32"
                ),
                SpeakerTurn(
                    id: "turn-3",
                    sessionID: "session-1",
                    speakerID: "speaker-1",
                    startMs: 2_500,
                    endMs: 3_500,
                    overlap: false,
                    sourceProvider: "mlx-sortformer-streaming-fp32"
                ),
            ]
        )

        let lines = segment.diarizedTranscriptLines

        XCTAssertEqual(lines.map(\.speakerID), ["speaker-1", "speaker-2", "speaker-1"])
        XCTAssertEqual(lines.map(\.speakerDisplayName), ["Bob", "Speaker 2", "Bob"])
        XCTAssertEqual(
            lines.map(\.text),
            ["Bob asked one question.", "Sarah answered clearly.", "Bob followed up."]
        )
    }

    func testSpeakerTurnMergePreservesPastTurnsAndReplacesCurrentPreviewWindow() {
        let existing = [
            SpeakerTurn(
                id: "old-1",
                sessionID: "session-1",
                speakerID: "speaker-1",
                startMs: 0,
                endMs: 2_400,
                overlap: false,
                sourceProvider: "mlx-sortformer-streaming-fp32"
            ),
            SpeakerTurn(
                id: "old-window",
                sessionID: "session-1",
                speakerID: "speaker-1",
                startMs: 3_000,
                endMs: 5_000,
                overlap: false,
                sourceProvider: "mlx-sortformer-streaming-fp32"
            ),
        ]
        let preview = [
            SpeakerTurn(
                id: "new-1",
                sessionID: "session-1",
                speakerID: "speaker-2",
                startMs: 3_300,
                endMs: 5_200,
                overlap: false,
                sourceProvider: "mlx-sortformer-streaming-fp32"
            ),
            SpeakerTurn(
                id: "new-2",
                sessionID: "session-1",
                speakerID: "speaker-1",
                startMs: 5_200,
                endMs: 6_400,
                overlap: false,
                sourceProvider: "mlx-sortformer-streaming-fp32"
            ),
        ]

        let merged = ConversationSpeakerTurnMerge.merge(
            existing: existing,
            preview: preview,
            replacingStartMs: 3_000,
            replacingEndMs: 6_500
        )

        XCTAssertEqual(merged.map(\.id), ["old-1", "new-1", "new-2"])
        XCTAssertEqual(merged.map(\.speakerID), ["speaker-1", "speaker-2", "speaker-1"])
    }

    func testSpeakerLineMergePreservesPastLinesAndReplacesCurrentPreviewWindow() {
        let existing = [
            ConversationSpeakerLine(
                id: "old-1",
                sessionID: "session-1",
                speakerID: "speaker-1",
                startMs: 0,
                endMs: 1_200,
                text: "Bob asked.",
                sourceProvider: "mlx-sortformer-streaming-fp32"
            ),
            ConversationSpeakerLine(
                id: "old-window",
                sessionID: "session-1",
                speakerID: "speaker-1",
                startMs: 3_000,
                endMs: 4_000,
                text: "Old live words.",
                sourceProvider: "mlx-sortformer-streaming-fp32"
            ),
        ]
        let preview = [
            ConversationSpeakerLine(
                id: "new-1",
                sessionID: "session-1",
                speakerID: "speaker-2",
                startMs: 3_100,
                endMs: 4_300,
                text: "Sarah answered.",
                sourceProvider: "mlx-sortformer-streaming-fp32"
            ),
            ConversationSpeakerLine(
                id: "new-2",
                sessionID: "session-1",
                speakerID: "speaker-1",
                startMs: 4_300,
                endMs: 5_000,
                text: "Bob followed up.",
                sourceProvider: "mlx-sortformer-streaming-fp32"
            ),
        ]

        let merged = ConversationSpeakerLineMerge.merge(
            existing: existing,
            preview: preview,
            replacingStartMs: 3_000,
            replacingEndMs: 5_100
        )

        XCTAssertEqual(merged.map(\.id), ["old-1", "new-1", "new-2"])
        XCTAssertEqual(merged.map(\.speakerID), ["speaker-1", "speaker-2", "speaker-1"])
        XCTAssertEqual(merged.map(\.text), ["Bob asked.", "Sarah answered.", "Bob followed up."])
    }

    func testLiveSegmentWindowKeepsFullSessionRangeForMergedSpeakerTurns() {
        let window = ConversationLiveSegmentWindow.merge(
            existingStartMs: 2_500,
            existingEndMs: 6_000,
            incomingStartMs: 9_000,
            incomingEndMs: nil,
            speakerTurns: [
                SpeakerTurn(
                    id: "turn-1",
                    sessionID: "session-1",
                    speakerID: "speaker-1",
                    startMs: 1_000,
                    endMs: 2_000,
                    overlap: false,
                    sourceProvider: "mlx-sortformer-streaming-fp32"
                ),
                SpeakerTurn(
                    id: "turn-2",
                    sessionID: "session-1",
                    speakerID: "speaker-2",
                    startMs: 9_200,
                    endMs: 10_000,
                    overlap: false,
                    sourceProvider: "mlx-sortformer-streaming-fp32"
                ),
            ]
        )

        XCTAssertEqual(window.startMs, 1_000)
        XCTAssertEqual(window.endMs, 10_000)
    }

    func testSegmentDiarizedTranscriptLinesIgnoreTinyOverlappingNoiseTurns() {
        let segment = ConversationSegment(
            id: "seg-1",
            sessionID: "session-1",
            speakerID: "speaker-2",
            speakerDisplayName: "Speaker 2",
            startMs: 0,
            endMs: 2_000,
            text: "Sarah handled the full answer.",
            state: .settled,
            speakerTurns: [
                SpeakerTurn(
                    id: "noise",
                    sessionID: "session-1",
                    speakerID: "speaker-1",
                    startMs: 0,
                    endMs: 120,
                    overlap: false,
                    sourceProvider: "mlx-sortformer-streaming-fp32"
                ),
                SpeakerTurn(
                    id: "turn-1",
                    sessionID: "session-1",
                    speakerID: "speaker-2",
                    startMs: 0,
                    endMs: 2_000,
                    overlap: false,
                    sourceProvider: "mlx-sortformer-streaming-fp32"
                ),
            ]
        )

        let lines = segment.diarizedTranscriptLines

        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].speakerID, "speaker-2")
        XCTAssertEqual(lines[0].text, "Sarah handled the full answer.")
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

    func testConversationInsightSynthesisParsesFencedJSONCards() {
        let response = """
        Here are the cards:
        ```json
        {
          "cards": [
            {
              "kind": "answer",
              "title": "User Count",
              "body": "Last year we had 18,420 active users.",
              "source_references": ["Bob [00:18]"],
              "confidence": 0.82
            },
            {
              "kind": "not_supported",
              "title": "Bad",
              "body": "Ignore me"
            },
            {
              "kind": "action_item",
              "title": "Follow up with Jane",
              "body": "Send Jane the final user count.",
              "source_references": [],
              "confidence": 0.7
            }
          ]
        }
        ```
        """

        let cards = ConversationInsightSynthesis.cardRequests(from: response)

        XCTAssertEqual(cards.count, 2)
        XCTAssertEqual(cards[0].kind, .answer)
        XCTAssertEqual(cards[0].title, "User Count")
        XCTAssertEqual(cards[0].sourceReferences, ["Bob [00:18]"])
        XCTAssertEqual(cards[0].confidence, 0.82)
        XCTAssertEqual(cards[1].kind, .actionItem)
    }

    func testConversationInsightSynthesisBuildsStrictJSONPromptWithTranscript() {
        let detail = ConversationDetail(
            session: ConversationSession(
                id: "session-1",
                title: "Roadmap call",
                startedAt: "2026-05-17T08:00:00Z",
                captureMode: .microphoneOnly,
                asrProvider: "parakeet-tdt",
                diarizationProvider: "none",
                externalProcessingEnabled: false
            ),
            segments: [
                ConversationSegment(
                    id: "seg-1",
                    sessionID: "session-1",
                    speakerID: "speaker-1",
                    speakerDisplayName: "Bob",
                    startMs: 18_130,
                    text: "How many users did we have last year?",
                    state: .settled
                )
            ],
            assistCards: []
        )

        let prompt = ConversationInsightSynthesis.userPrompt(for: detail)

        XCTAssertTrue(prompt.contains("\"cards\""))
        XCTAssertTrue(prompt.contains("question, answer, time_zone, follow_up, action_item, warning"))
        XCTAssertTrue(prompt.contains("Bob [00:18]: How many users did we have last year?"))
        XCTAssertTrue(prompt.contains("Return only JSON"))
    }

    func testConversationInsightSynthesisUsesDiarizedTranscriptLines() {
        let detail = ConversationDetail(
            session: ConversationSession(
                id: "session-1",
                title: "Roadmap call",
                startedAt: "2026-05-17T08:00:00Z",
                captureMode: .microphoneOnly,
                asrProvider: "parakeet-tdt-mlx",
                diarizationProvider: "mlx-sortformer-streaming-fp32",
                externalProcessingEnabled: false
            ),
            segments: [
                ConversationSegment(
                    id: "seg-1",
                    sessionID: "session-1",
                    speakerID: "speaker-1",
                    speakerDisplayName: "Bob",
                    startMs: 0,
                    endMs: 2_000,
                    text: "Bob asked. Sarah answered.",
                    state: .settled,
                    speakerTurns: [
                        SpeakerTurn(
                            id: "turn-1",
                            sessionID: "session-1",
                            speakerID: "speaker-1",
                            startMs: 0,
                            endMs: 1_000,
                            overlap: false,
                            sourceProvider: "mlx-sortformer-streaming-fp32"
                        ),
                        SpeakerTurn(
                            id: "turn-2",
                            sessionID: "session-1",
                            speakerID: "speaker-2",
                            startMs: 1_000,
                            endMs: 2_000,
                            overlap: false,
                            sourceProvider: "mlx-sortformer-streaming-fp32"
                        ),
                    ]
                )
            ],
            assistCards: []
        )

        let prompt = ConversationInsightSynthesis.userPrompt(for: detail)

        XCTAssertTrue(prompt.contains("Bob [00:00]: Bob asked."))
        XCTAssertTrue(prompt.contains("Speaker 2 [00:01]: Sarah answered."))
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
