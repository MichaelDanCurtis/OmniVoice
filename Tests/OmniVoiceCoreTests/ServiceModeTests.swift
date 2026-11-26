import XCTest
@testable import OmniVoiceCore

final class ServiceModeTests: XCTestCase {
    func testServiceModeConfigurationRoundTripsThroughCodable() throws {
        let config = ServiceModeConfiguration(
            enabled: true,
            deepgramModel: .nova3,
            deepgramLanguage: "en-US",
            deepgramSmartFormat: true,
            llmRoute: .subscriptionAgent(agentID: "claude"),
            unloadLocalModelsWhenEnabled: true
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ServiceModeConfiguration.self, from: data)
        XCTAssertEqual(decoded, config)

        var prefs = OmniVoicePreferences.defaults
        prefs.serviceMode = config
        let prefsData = try EngineCoding.encoder.encode(prefs)
        let decodedPrefs = try EngineCoding.decoder.decode(OmniVoicePreferences.self, from: prefsData)
        XCTAssertEqual(decodedPrefs.serviceMode, config)
    }

    func testServiceModeLLMRoutePickerIDRoundTrip() {
        XCTAssertEqual(ServiceModeLLMRoute(pickerID: ServiceModeLLMRoute.auto.pickerID), .auto)
        let agentRoute = ServiceModeLLMRoute.subscriptionAgent(agentID: "codex")
        XCTAssertEqual(ServiceModeLLMRoute(pickerID: agentRoute.pickerID), agentRoute)
        let llmRoute = ServiceModeLLMRoute.configuredTextLLM(provider: .githubCopilot)
        XCTAssertEqual(ServiceModeLLMRoute(pickerID: llmRoute.pickerID), llmRoute)
    }

    func testDeepgramURLBuildersIncludeExpectedParameters() {
        let config = ServiceModeConfiguration(
            enabled: true,
            deepgramModel: .nova3,
            deepgramLanguage: "multi",
            deepgramSmartFormat: true
        )

        let restURL = DeepgramAPIHelper.restListenURL(config: config)
        XCTAssertNotNil(restURL)
        XCTAssertTrue(restURL!.absoluteString.contains("model=nova-3"))
        XCTAssertTrue(restURL!.absoluteString.contains("language=multi"))
        XCTAssertTrue(restURL!.absoluteString.contains("smart_format=true"))

        let wsURL = DeepgramAPIHelper.streamingListenURL(config: config, sampleRate: 48_000)
        XCTAssertNotNil(wsURL)
        XCTAssertTrue(wsURL!.absoluteString.hasPrefix("wss://api.deepgram.com/v1/listen?"))
        XCTAssertTrue(wsURL!.absoluteString.contains("encoding=linear16"))
        XCTAssertTrue(wsURL!.absoluteString.contains("sample_rate=48000"))
        XCTAssertTrue(wsURL!.absoluteString.contains("interim_results=true"))
    }

    func testDeepgramParsersExtractRESTAndStreamingTranscripts() {
        let restJSON = """
        {"results":{"channels":[{"alternatives":[{"transcript":"Hello from Deepgram Nova 3."}]}]}}
        """.data(using: .utf8)!
        XCTAssertEqual(DeepgramAPIHelper.parseRESTTranscript(from: restJSON), "Hello from Deepgram Nova 3.")

        let streamJSON = """
        {"type":"Results","is_final":true,"speech_final":false,"channel":{"alternatives":[{"transcript":"Testing live stream"}]}}
        """
        let event = DeepgramAPIHelper.parseStreamEvent(from: streamJSON)
        XCTAssertEqual(event, DeepgramAPIHelper.StreamEvent(transcript: "Testing live stream", isFinal: true, speechFinal: false))
    }

    func testGeminiAntigravityAgentAndAgentCleanupBackendPreferences() throws {
        let registry = AgentRegistry(custom: [])
        let agy = registry.resolve(keyword: "gemini antigravity")
        XCTAssertEqual(agy?.id, "antigravity")
        XCTAssertEqual(agy?.displayName, "Gemini Antigravity")
        XCTAssertEqual(agy?.binaryName, "agy")
        XCTAssertEqual(registry.resolve(keyword: "agy")?.id, "antigravity")

        var prefs = OmniVoicePreferences.defaults
        prefs.llmCleanupEnabled = true
        prefs.llmCleanupBackend = .agent
        prefs.llmCleanupAgentID = "claude"
        prefs.idleMLXAutoUnloadMinutes = 30

        let encoded = try EngineCoding.encoder.encode(prefs)
        let decoded = try EngineCoding.decoder.decode(OmniVoicePreferences.self, from: encoded)
        XCTAssertEqual(decoded.llmCleanupBackend, .agent)
        XCTAssertEqual(decoded.llmCleanupAgentID, "claude")
        XCTAssertEqual(decoded.idleMLXAutoUnloadMinutes, 30)
    }
}
