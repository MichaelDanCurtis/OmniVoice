import XCTest
@testable import OmniVoiceCore

final class WorkspaceModelsTests: XCTestCase {
    func testSubjectMarkdownContextIncludesAllNotes() {
        let subject = TranscriptionSubject(
            id: "subject-1",
            title: "Fixing the new car",
            createdAt: "2026-05-19T08:00:00Z",
            updatedAt: "2026-05-19T08:10:00Z",
            notes: [
                TranscriptionNote(
                    id: "note-1",
                    subjectID: "subject-1",
                    title: "Engine ideas",
                    body: "We could change the intake and inspect the engine mounts.",
                    createdAt: "2026-05-19T08:01:00Z",
                    updatedAt: "2026-05-19T08:01:00Z"
                ),
                TranscriptionNote(
                    id: "note-2",
                    subjectID: "subject-1",
                    title: "Mechanic",
                    body: "Talk to the auto mechanic on Saturday.",
                    createdAt: "2026-05-19T08:05:00Z",
                    updatedAt: "2026-05-19T08:05:00Z"
                ),
            ]
        )

        let markdown = subject.markdownContext()

        XCTAssertTrue(markdown.contains("# Fixing the new car"))
        XCTAssertTrue(markdown.contains("## Engine ideas"))
        XCTAssertTrue(markdown.contains("We could change the intake"))
        XCTAssertTrue(markdown.contains("Talk to the auto mechanic on Saturday."))
    }

    func testEditorDocumentCreatedFromSubjectCarriesContext() {
        let subject = TranscriptionSubject(
            id: "subject-1",
            title: "Fixing the new car",
            notes: [
                TranscriptionNote(
                    subjectID: "subject-1",
                    title: "Parts",
                    body: "Order belts and check the intake."
                )
            ]
        )

        let document = EditorDocument.from(subject: subject, prompt: "Write a letter to the mechanic.")

        XCTAssertEqual(document.title, "Fixing the new car")
        XCTAssertEqual(document.sourceSubjectID, "subject-1")
        XCTAssertTrue(document.bodyMarkdown.contains("Write a letter to the mechanic."))
        XCTAssertTrue(document.contextMarkdown.contains("Order belts"))
        XCTAssertTrue(document.aiContext.contains("## Parts"))
    }

    func testEditorDocumentCreatedFromConversationCarriesTranscriptContext() {
        let conversation = ConversationDetail(
            session: ConversationSession(
                id: "conversation-1",
                title: "Mechanic call",
                startedAt: "2026-05-19T08:00:00Z",
                endedAt: "2026-05-19T08:20:00Z",
                captureMode: .microphoneOnly,
                asrProvider: "parakeet-tdt-mlx",
                diarizationProvider: "mlx-sortformer-streaming-fp16",
                externalProcessingEnabled: false
            ),
            segments: [
                ConversationSegment(
                    id: "segment-1",
                    sessionID: "conversation-1",
                    speakerID: "speaker-1",
                    speakerDisplayName: "Bob",
                    startMs: 1_000,
                    text: "Can you send me the repair notes?",
                    state: .settled
                )
            ],
            assistCards: []
        )

        let document = EditorDocument.from(conversation: conversation)

        XCTAssertEqual(document.title, "Mechanic call")
        XCTAssertTrue(document.bodyMarkdown.contains("Bob [00:01]: Can you send me the repair notes?"))
        XCTAssertTrue(document.contextMarkdown.contains("- Diarization: mlx-sortformer-streaming-fp16"))
        XCTAssertEqual(document.aiContext, document.contextMarkdown.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func testMarkdownExportWritesReadableDocument() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let document = EditorDocument(
            id: "doc-1",
            title: "Mechanic letter",
            bodyMarkdown: "# Mechanic letter\n\nPlease inspect the engine mounts."
        )

        let url = try OmniWorkspaceArchive.writeMarkdown(document, rootURL: root)

        XCTAssertEqual(url.lastPathComponent, "Mechanic letter.md")
        let markdown = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(markdown.contains("# Mechanic letter"))
        XCTAssertTrue(markdown.contains("Please inspect the engine mounts."))
    }

    func testDocxExportWritesOpenXMLPackage() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let document = EditorDocument(
            id: "doc-1",
            title: "Mechanic letter",
            bodyMarkdown: "# Mechanic letter\n\nPlease inspect the engine mounts.",
            style: EditorDocumentStyle(fontName: "Avenir Next", fontSize: 14)
        )

        let url = try OmniWorkspaceArchive.writeDocx(document, rootURL: root)

        XCTAssertEqual(url.lastPathComponent, "Mechanic letter.docx")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertGreaterThan((try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0, 0)
    }

    func testAskAIContextAttachmentCanUseSubjectAndConversation() {
        let subject = TranscriptionSubject(
            id: "subject-1",
            title: "Fixing the new car",
            notes: [TranscriptionNote(subjectID: "subject-1", title: "Mechanic", body: "Saturday appointment.")]
        )
        let conversation = ConversationDetail(
            session: ConversationSession(
                id: "conversation-1",
                title: "Mechanic call",
                startedAt: "2026-05-19T08:00:00Z",
                captureMode: .microphoneOnly,
                asrProvider: "parakeet-tdt-mlx",
                diarizationProvider: "none",
                externalProcessingEnabled: false
            ),
            segments: [
                ConversationSegment(
                    id: "segment-1",
                    sessionID: "conversation-1",
                    speakerID: "speaker-1",
                    speakerDisplayName: "Mike",
                    startMs: 1_000,
                    text: "Ask whether they can inspect the belts.",
                    state: .settled
                )
            ],
            assistCards: []
        )

        let attachments = [
            AskAIContextAttachment(subject: subject),
            AskAIContextAttachment(conversation: conversation),
        ]

        XCTAssertTrue(attachments[0].text.contains("Saturday appointment."))
        XCTAssertTrue(attachments[1].text.contains("Mike [00:01]"))
    }

    func testAskAIImageAttachmentCarriesDataURLMetadata() {
        let attachment = AskAIContextAttachment(
            kind: .image,
            title: "dashboard.png",
            text: "Screenshot from OmniVoice.",
            filePath: "/tmp/dashboard.png",
            mimeType: "image/png",
            dataURL: "data:image/png;base64,abc123"
        )

        XCTAssertEqual(attachment.mimeType, "image/png")
        XCTAssertEqual(attachment.dataURL, "data:image/png;base64,abc123")
        XCTAssertTrue(attachment.contextMarkdown.contains("dashboard.png"))
    }

    func testAskAIAudioAttachmentCarriesPlayableMetadata() {
        let attachment = AskAIContextAttachment(
            kind: .audio,
            title: "meeting.wav",
            text: "Audio attached: meeting.wav",
            filePath: "/tmp/meeting.wav",
            mimeType: "audio/wav",
            dataURL: "data:audio/wav;base64,abc123"
        )

        XCTAssertEqual(attachment.kind, .audio)
        XCTAssertEqual(attachment.mimeType, "audio/wav")
        XCTAssertEqual(attachment.dataURL, "data:audio/wav;base64,abc123")
    }

    func testAskAIThreadStoresSessionProviderAndModelSelection() throws {
        let thread = AskAIThread(
            id: "thread-1",
            title: "Question",
            subjectID: "subject-1",
            providerOverride: .claude,
            modelOverride: "claude-sonnet-4",
            webSearchEnabled: true,
            messages: [
                AskAIMessage(role: .user, text: "What should I ask?")
            ]
        )

        let data = try JSONEncoder().encode(thread)
        let decoded = try JSONDecoder().decode(AskAIThread.self, from: data)

        XCTAssertEqual(decoded.subjectID, "subject-1")
        XCTAssertEqual(decoded.providerOverride, .claude)
        XCTAssertEqual(decoded.modelOverride, "claude-sonnet-4")
        XCTAssertTrue(decoded.webSearchEnabled)
    }

    func testAskAIThreadDecodesLegacyThreadWithoutSessionProvider() throws {
        let data = """
        {
          "id": "thread-1",
          "title": "Legacy",
          "createdAt": "2026-05-19T00:00:00Z",
          "updatedAt": "2026-05-19T00:00:00Z",
          "messages": [],
          "attachments": []
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AskAIThread.self, from: data)

        XCTAssertNil(decoded.subjectID)
        XCTAssertNil(decoded.providerOverride)
        XCTAssertNil(decoded.modelOverride)
        XCTAssertFalse(decoded.webSearchEnabled)
    }

    func testAskAIContextAttachmentCanUseEditorDocument() {
        let document = EditorDocument(
            id: "doc-1",
            title: "Mechanic letter",
            bodyMarkdown: "# Mechanic letter\n\nPlease inspect the belts.",
            contextMarkdown: "# Fixing the car\n\nSaturday appointment."
        )

        let attachment = AskAIContextAttachment(document: document)

        XCTAssertEqual(attachment.kind, .document)
        XCTAssertEqual(attachment.title, "Mechanic letter")
        XCTAssertTrue(attachment.text.contains("Please inspect the belts."))
        XCTAssertTrue(attachment.text.contains("Saturday appointment."))
    }

    func testAskAIContextAttachmentCanUseTranscriptRecord() {
        let transcript = EngineTranscriptRecord(
            id: "transcript-1",
            createdAt: "2026-05-19T09:00:00Z",
            source: "dictation",
            rawText: "raw text",
            cleanedText: "Cleaned transcript.",
            provider: "parakeet-tdt-mlx",
            style: "professional",
            audioBytes: 64_000,
            sampleRate: 16_000,
            durationMs: 2_500
        )

        let attachment = AskAIContextAttachment(transcript: transcript)

        XCTAssertEqual(attachment.kind, .transcript)
        XCTAssertEqual(attachment.title, "Transcript 2026-05-19T09:00:00Z")
        XCTAssertTrue(attachment.text.contains("Cleaned transcript."))
        XCTAssertTrue(attachment.text.contains("parakeet-tdt-mlx"))
    }

    func testWorkspaceStorePersistsSnapshot() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let store = OmniWorkspaceStore(rootURL: root)
        let snapshot = OmniWorkspaceSnapshot(
            subjects: [
                TranscriptionSubject(
                    id: "subject-1",
                    title: "Fixing the new car",
                    notes: [TranscriptionNote(subjectID: "subject-1", title: "Parts", body: "Order belts.")]
                )
            ],
            editorDocuments: [
                EditorDocument(id: "doc-1", title: "Letter", bodyMarkdown: "Hello")
            ],
            askAIThreads: [
                AskAIThread(id: "thread-1", title: "Question", subjectID: "subject-1", messages: [
                    AskAIMessage(role: .user, text: "What should I ask?")
                ])
            ]
        )

        try store.save(snapshot)
        let loaded = try store.load()

        XCTAssertEqual(loaded.subjects.first?.title, "Fixing the new car")
        XCTAssertEqual(loaded.editorDocuments.first?.title, "Letter")
        XCTAssertEqual(loaded.askAIThreads.first?.subjectID, "subject-1")
        XCTAssertEqual(loaded.askAIThreads.first?.messages.first?.text, "What should I ask?")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "Transcriber").appending(path: "Fixing the new car").appending(path: "Parts.md").path))
    }

    func testDictationTriggerStateLatchesOnDoubleTap() {
        var state = DictationTriggerState()

        XCTAssertEqual(state.press(at: 10.0), .startMomentary)
        XCTAssertTrue(state.release(at: 10.1))
        XCTAssertEqual(state.press(at: 10.3), .startLatched)
        XCTAssertFalse(state.release(at: 10.4))
        XCTAssertEqual(state.press(at: 11.0), .finishLatched)
        XCTAssertEqual(state.mode, nil)
    }
}
