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

    func testTranscriptUpdateDecodesStreamingPayload() throws {
        let data = #"{"text":"live words","is_final":false}"#.data(using: .utf8)!

        let update = try EngineCoding.decoder.decode(TranscriptUpdate.self, from: data)

        XCTAssertEqual(update, TranscriptUpdate(text: "live words", isFinal: false))
    }
}
