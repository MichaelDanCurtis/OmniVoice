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

        let wsURL = DeepgramAPIHelper.streamingListenURL(config: config, sampleRate: 48_000, diarize: true)
        XCTAssertNotNil(wsURL)
        XCTAssertTrue(wsURL!.absoluteString.hasPrefix("wss://api.deepgram.com/v1/listen?"))
        XCTAssertTrue(wsURL!.absoluteString.contains("encoding=linear16"))
        XCTAssertTrue(wsURL!.absoluteString.contains("sample_rate=48000"))
        XCTAssertTrue(wsURL!.absoluteString.contains("interim_results=true"))
        XCTAssertTrue(wsURL!.absoluteString.contains("diarize=true"))
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

        let diarizedJSON = """
        {"type":"Results","is_final":true,"speech_final":true,"start":1.0,"duration":3.0,"channel":{"alternatives":[{"transcript":"Hey Alice. Hi Bob!","words":[{"word":"hey","punctuated_word":"Hey","start":1.0,"end":1.2,"speaker":0},{"word":"alice","punctuated_word":"Alice.","start":1.25,"end":1.6,"speaker":0},{"word":"hi","punctuated_word":"Hi","start":2.0,"end":2.2,"speaker":1},{"word":"bob","punctuated_word":"Bob!","start":2.25,"end":2.7,"speaker":1}]}]}}
        """
        let segments = DeepgramAPIHelper.parseStreamDiarizedSegments(from: diarizedJSON)
        XCTAssertEqual(segments?.count, 2)
        XCTAssertEqual(segments?[0].speakerDisplayName, "Speaker 1")
        XCTAssertEqual(segments?[0].text, "Hey Alice.")
        XCTAssertEqual(segments?[0].startMs, 1000)
        XCTAssertEqual(segments?[0].endMs, 1600)
        XCTAssertEqual(segments?[1].speakerDisplayName, "Speaker 2")
        XCTAssertEqual(segments?[1].text, "Hi Bob!")
        XCTAssertEqual(segments?[1].startMs, 2000)
        XCTAssertEqual(segments?[1].endMs, 2700)
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

    func testUnifiedAIRouteRoundTripsAndMigratesLegacyDefaultAgent() throws {
        // Picker ID round-trip for every category
        XCTAssertEqual(UnifiedAIRoute(pickerID: UnifiedAIRoute.auto.pickerID), .auto)
        XCTAssertEqual(UnifiedAIRoute(pickerID: UnifiedAIRoute.localMLX.pickerID), .localMLX)
        let agentRoute = UnifiedAIRoute.agent(agentID: "antigravity")
        XCTAssertEqual(UnifiedAIRoute(pickerID: agentRoute.pickerID), agentRoute)
        let apiRoute = UnifiedAIRoute.textLLM(provider: .githubCopilot)
        XCTAssertEqual(UnifiedAIRoute(pickerID: apiRoute.pickerID), apiRoute)

        // OmniVoicePreferences round-trip through EngineCoding (convertFromSnakeCase!)
        var prefs = OmniVoicePreferences.defaults
        prefs.defaultAIRoute = .agent(agentID: "antigravity")
        prefs.llmCleanupEnabled = true
        prefs.llmCleanupBackend = .aiConfiguration

        let encoded = try EngineCoding.encoder.encode(prefs)
        let decoded = try EngineCoding.decoder.decode(OmniVoicePreferences.self, from: encoded)
        XCTAssertEqual(decoded.defaultAIRoute, .agent(agentID: "antigravity"))
        XCTAssertEqual(decoded.llmCleanupBackend, .aiConfiguration)
        // Agent routes are executed in Swift via AgentRunner, so engine cleanup config stays nil
        XCTAssertNil(decoded.resolvedLLMCleanupConfig())

        // When defaultAIRoute switches to a configured API/OAuth provider, aiConfiguration cleanup resolves it
        var apiPrefs = OmniVoicePreferences.defaults
        apiPrefs.llmCleanupEnabled = true
        apiPrefs.llmCleanupBackend = .aiConfiguration
        apiPrefs.defaultAIRoute = .textLLM(provider: .custom)
        apiPrefs.setTextLLMConfiguration(
            TextLLMProviderConfiguration(
                provider: .custom,
                baseURL: "http://127.0.0.1:11434/v1",
                model: "qwen2.5:3b"
            )
        )
        let resolved = try XCTUnwrap(apiPrefs.resolvedLLMCleanupConfig())
        XCTAssertEqual(resolved.provider, TextLLMProviderKind.custom.rawValue)
        XCTAssertEqual(resolved.model, "qwen2.5:3b")

        // When defaultAIRoute switches to localMLX, aiConfiguration cleanup resolves to local_mlx
        apiPrefs.defaultAIRoute = .localMLX
        let localResolved = try XCTUnwrap(apiPrefs.resolvedLLMCleanupConfig())
        XCTAssertEqual(localResolved.transport, .localMLX)

        // Legacy JSON without default_ai_route migrates from the "ai" agent keyword binding
        var legacy = OmniVoicePreferences.defaults
        legacy.askKeywordBindings = [
            AskKeywordBinding(id: "builtin-ai", keyword: "ai", target: AskTarget(kind: .agent, id: "claude")),
        ]
        let legacyData = try JSONEncoder().encode(legacy)
        var rawJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: legacyData) as? [String: Any])
        rawJSON.removeValue(forKey: "default_ai_route")
        let strippedData = try JSONSerialization.data(withJSONObject: rawJSON)
        let migrated = try JSONDecoder().decode(OmniVoicePreferences.self, from: strippedData)
        XCTAssertEqual(migrated.defaultAIRoute, .agent(agentID: "claude"))
    }
}
