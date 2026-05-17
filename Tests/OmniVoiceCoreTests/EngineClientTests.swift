import XCTest
@testable import OmniVoiceCore

final class EngineClientTests: XCTestCase {
    func testCleanupRequestEncodesSnakeCasePayload() throws {
        let request = CleanupRequest(
            rawTranscript: "Schedule it for Monday, actually Tuesday.",
            style: .neutral,
            dictionaryTerms: ["OmniVoice"]
        )
        let data = try EngineCoding.encoder.encode(request)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(json.contains("raw_transcript"))
        XCTAssertTrue(json.contains("dictionary_terms"))
        XCTAssertTrue(json.contains("OmniVoice"))
        XCTAssertTrue(json.contains("neutral"))
    }

    func testCleanupResponseDecodesSnakeCasePayload() throws {
        let data = #"{"text":"Schedule it for Tuesday.","cleanup_applied":true}"#.data(using: .utf8)!

        let response = try EngineCoding.decoder.decode(CleanupResult.self, from: data)

        XCTAssertEqual(response, CleanupResult(text: "Schedule it for Tuesday.", cleanupApplied: true))
    }

    func testTranscribeResponseDecodesProviderPayload() throws {
        let data = #"{"text":"hello","provider":"fake"}"#.data(using: .utf8)!

        let response = try EngineCoding.decoder.decode(TranscribeResult.self, from: data)

        XCTAssertEqual(response.text, "hello")
        XCTAssertEqual(response.provider, .fake)
    }

    func testProviderInfoDecodesEnginePayload() throws {
        let data = #"{"id":"parakeet-tdt","label":"Parakeet TDT","available":false,"reason":"model files not found"}"#.data(using: .utf8)!

        let provider = try EngineCoding.decoder.decode(EngineProviderInfo.self, from: data)

        XCTAssertEqual(provider.id, "parakeet-tdt")
        XCTAssertEqual(provider.label, "Parakeet TDT")
        XCTAssertFalse(provider.available)
        XCTAssertEqual(provider.reason, "model files not found")
    }

    func testModelStatusDecodesHuggingFacePayload() throws {
        let data = #"{"provider_id":"parakeet-tdt","label":"Parakeet TDT","repo_id":"csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8","local_path":"/models/parakeet-tdt","installed":false,"installed_revision":null,"remote_revision":null,"update_available":null,"missing_files":["encoder.int8.onnx"],"download_state":"idle","download_message":null}"#.data(using: .utf8)!

        let status = try EngineCoding.decoder.decode(EngineModelStatus.self, from: data)

        XCTAssertEqual(status.providerID, "parakeet-tdt")
        XCTAssertEqual(status.repoID, "csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8")
        XCTAssertFalse(status.installed)
        XCTAssertEqual(status.missingFiles, ["encoder.int8.onnx"])
        XCTAssertEqual(status.downloadState, "idle")
    }

    func testModelUpdateDecodesRemoteRevisionPayload() throws {
        let data = #"{"provider_id":"parakeet-tdt","repo_id":"repo","installed_revision":"old-sha","remote_revision":"new-sha","update_available":true}"#.data(using: .utf8)!

        let update = try EngineCoding.decoder.decode(EngineModelUpdateInfo.self, from: data)

        XCTAssertEqual(update.installedRevision, "old-sha")
        XCTAssertEqual(update.remoteRevision, "new-sha")
        XCTAssertTrue(update.updateAvailable)
    }

    func testModelDownloadStatusDecodesQueuedPayload() throws {
        let data = #"{"provider_id":"parakeet-tdt","state":"queued","message":"Download queued","local_path":"/models/parakeet-tdt","revision":null}"#.data(using: .utf8)!

        let status = try EngineCoding.decoder.decode(EngineModelDownloadStatus.self, from: data)

        XCTAssertEqual(status.providerID, "parakeet-tdt")
        XCTAssertEqual(status.state, "queued")
        XCTAssertEqual(status.message, "Download queued")
    }

    func testTranscriptRecordDecodesEnginePayload() throws {
        let data = #"{"id":"t1","created_at":"2026-05-16T08:12:30Z","source":"dictation","raw_text":"no wait house","cleaned_text":"I'm going to the house.","provider":"parakeet-tdt","style":"neutral","audio_bytes":128000,"sample_rate":16000,"duration_ms":1500}"#.data(using: .utf8)!

        let record = try EngineCoding.decoder.decode(EngineTranscriptRecord.self, from: data)

        XCTAssertEqual(record.id, "t1")
        XCTAssertEqual(record.createdAt, "2026-05-16T08:12:30Z")
        XCTAssertEqual(record.source, "dictation")
        XCTAssertEqual(record.rawText, "no wait house")
        XCTAssertEqual(record.cleanedText, "I'm going to the house.")
        XCTAssertEqual(record.provider, "parakeet-tdt")
        XCTAssertEqual(record.style, "neutral")
        XCTAssertEqual(record.audioBytes, 128000)
        XCTAssertEqual(record.sampleRate, 16000)
        XCTAssertEqual(record.durationMs, 1500)
        XCTAssertEqual(record.displayText, "I'm going to the house.")
    }

    func testTranscriptUpdateDecodesStreamingPayload() throws {
        let data = #"{"text":"live words","is_final":false}"#.data(using: .utf8)!

        let update = try EngineCoding.decoder.decode(TranscriptUpdate.self, from: data)

        XCTAssertEqual(update, TranscriptUpdate(text: "live words", isFinal: false))
    }

    func testStreamingDiagnosticsCanSkipCurrentSnapshot() {
        let client = EngineStreamingClient()
        let diagnostics = expectation(description: "diagnostics should not be delivered immediately")
        diagnostics.isInverted = true

        client.setOnDiagnostics({ _ in diagnostics.fulfill() }, emitCurrent: false)

        wait(for: [diagnostics], timeout: 0.05)
        client.setOnDiagnostics(nil)
    }

    func testAIHandoffRequestEncodesSnakeCasePayload() throws {
        let request = AIHandoffRequest(
            prompt: "write a reply",
            provider: "claude",
            baseURL: "https://openrouter.ai/api/v1",
            model: "anthropic/claude-sonnet",
            apiKey: "secret",
            context: "Jane asked for an update."
        )

        let data = try EngineCoding.encoder.encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["prompt"] as? String, "write a reply")
        XCTAssertEqual(object["provider"] as? String, "claude")
        XCTAssertEqual(object["base_url"] as? String, "https://openrouter.ai/api/v1")
        XCTAssertEqual(object["model"] as? String, "anthropic/claude-sonnet")
        XCTAssertEqual(object["api_key"] as? String, "secret")
        XCTAssertEqual(object["context"] as? String, "Jane asked for an update.")
    }

    func testAIHandoffResultDecodesEnginePayload() throws {
        let data = #"{"text":"Hi Jane, here is the update.","provider":"claude","model":"anthropic/claude-sonnet"}"#.data(using: .utf8)!

        let result = try EngineCoding.decoder.decode(AIHandoffResult.self, from: data)

        XCTAssertEqual(
            result,
            AIHandoffResult(
                text: "Hi Jane, here is the update.",
                provider: "claude",
                model: "anthropic/claude-sonnet"
            )
        )
    }

    func testConversationDetailDecodesEnginePayload() throws {
        let data = """
        {
          "session": {
            "id": "s1",
            "title": "Roadmap call",
            "started_at": "2026-05-17T08:00:00Z",
            "ended_at": null,
            "capture_mode": "microphone_only",
            "asr_provider": "parakeet-tdt",
            "diarization_provider": "mock",
            "external_processing_enabled": false
          },
          "segments": [
            {
              "id": "seg1",
              "session_id": "s1",
              "speaker_id": "speaker-1",
              "speaker_display_name": "Speaker 1",
              "start_ms": 18130,
              "end_ms": 21900,
              "text": "How many users did we have last year?",
              "state": "settled",
              "confidence": 0.91
            }
          ],
          "assist_cards": [
            {
              "id": "card1",
              "session_id": "s1",
              "kind": "answer",
              "title": "Answer Found",
              "body": "Last year we had 18,420 active users.",
              "source_references": ["Obsidian/adoption-2025.md"],
              "confidence": 0.78,
              "status": "active",
              "created_at": "2026-05-17T08:00:10Z"
            }
          ]
        }
        """.data(using: .utf8)!

        let detail = try EngineCoding.decoder.decode(ConversationDetail.self, from: data)

        XCTAssertEqual(detail.session.id, "s1")
        XCTAssertEqual(detail.segments[0].speakerDisplayName, "Speaker 1")
        XCTAssertEqual(detail.assistCards[0].copyText, "Last year we had 18,420 active users.")
        XCTAssertEqual(detail.assistCards[0].sourceReferences, ["Obsidian/adoption-2025.md"])
    }

    func testConversationSessionCreateRequestEncodesSnakeCasePayload() throws {
        let request = ConversationSessionCreateRequest(
            title: "Roadmap call",
            captureMode: .microphoneOnly,
            asrProvider: "parakeet-tdt",
            diarizationProvider: "mock",
            externalProcessingEnabled: false
        )

        let data = try EngineCoding.encoder.encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["title"] as? String, "Roadmap call")
        XCTAssertEqual(object["capture_mode"] as? String, "microphone_only")
        XCTAssertEqual(object["asr_provider"] as? String, "parakeet-tdt")
        XCTAssertEqual(object["diarization_provider"] as? String, "mock")
        XCTAssertEqual(object["external_processing_enabled"] as? Bool, false)
    }

    func testConversationSegmentCreateRequestEncodesSpeakerIDAsSnakeCasePayload() throws {
        let request = ConversationSegmentCreateRequest(
            speakerID: "speaker-1",
            speakerDisplayName: "Speaker 1",
            startMs: 18_130,
            endMs: 21_900,
            text: "How many users did we have last year?",
            state: .settled,
            confidence: 0.91
        )

        let data = try EngineCoding.encoder.encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["speaker_id"] as? String, "speaker-1")
        XCTAssertEqual(object["speaker_display_name"] as? String, "Speaker 1")
        XCTAssertEqual(object["start_ms"] as? Int, 18_130)
        XCTAssertEqual(object["end_ms"] as? Int, 21_900)
        XCTAssertEqual(object["text"] as? String, "How many users did we have last year?")
        XCTAssertEqual(object["state"] as? String, "settled")
        XCTAssertEqual(object["confidence"] as? Double, 0.91)
        XCTAssertNil(object["speaker_i_d"])
    }

    func testConversationAssistCardCreateRequestEncodesSourceReferencesAsSnakeCasePayload() throws {
        let request = ConversationAssistCardCreateRequest(
            kind: .answer,
            title: "Answer Found",
            body: "Last year we had 18,420 active users.",
            sourceReferences: ["Obsidian/adoption-2025.md"],
            confidence: 0.78
        )

        let data = try EngineCoding.encoder.encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["kind"] as? String, "answer")
        XCTAssertEqual(object["title"] as? String, "Answer Found")
        XCTAssertEqual(object["body"] as? String, "Last year we had 18,420 active users.")
        XCTAssertEqual(object["source_references"] as? [String], ["Obsidian/adoption-2025.md"])
        XCTAssertEqual(object["confidence"] as? Double, 0.78)
    }
}
