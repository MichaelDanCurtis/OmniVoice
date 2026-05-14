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

    func testTranscriptUpdateDecodesStreamingPayload() throws {
        let data = #"{"text":"live words","is_final":false}"#.data(using: .utf8)!

        let update = try EngineCoding.decoder.decode(TranscriptUpdate.self, from: data)

        XCTAssertEqual(update, TranscriptUpdate(text: "live words", isFinal: false))
    }
}
