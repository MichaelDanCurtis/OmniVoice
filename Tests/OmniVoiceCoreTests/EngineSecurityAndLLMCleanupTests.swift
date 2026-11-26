import XCTest
@testable import OmniVoiceCore

final class EngineSecurityAndLLMCleanupTests: XCTestCase {
    func testEngineAuthTokenStoreGeneratesUnique64CharHexTokens() {
        let first = EngineAuthTokenStore.generateToken()
        let second = EngineAuthTokenStore.generateToken()

        XCTAssertEqual(first.count, 64)
        XCTAssertEqual(second.count, 64)
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.allSatisfy { $0.isHexDigit })
    }

    func testEngineAuthTokenStoreAuthenticatesDashboardURLs() {
        let store = EngineAuthTokenStore(initialToken: "secret-token-123")
        let base = URL(string: "http://127.0.0.1:8765/")!

        let authenticated = store.authenticatedURL(base)
        let components = URLComponents(url: authenticated, resolvingAgainstBaseURL: false)
        XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "token" })?.value, "secret-token-123")

        store.token = nil
        XCTAssertEqual(store.authenticatedURL(base), base)
    }

    func testStreamingClientRequestAttachesEngineTokenHeader() {
        let url = URL(string: "ws://127.0.0.1:8765/stream?provider=fake&sample_rate=16000")!

        let authed = EngineStreamingClient.streamRequest(url: url, authToken: "abc123")
        XCTAssertEqual(authed.value(forHTTPHeaderField: EngineAuthTokenStore.headerName), "abc123")

        let unauthed = EngineStreamingClient.streamRequest(url: url, authToken: "   ")
        XCTAssertNil(unauthed.value(forHTTPHeaderField: EngineAuthTokenStore.headerName))
    }

    func testCleanupResultDecodesLegacyPayloadWithoutLLMFields() throws {
        let data = Data(#"{"text":"Hello.","cleanup_applied":true}"#.utf8)
        let result = try EngineCoding.decoder.decode(CleanupResult.self, from: data)

        XCTAssertEqual(result.text, "Hello.")
        XCTAssertTrue(result.cleanupApplied)
        XCTAssertFalse(result.llmApplied)
        XCTAssertNil(result.llmFallbackReason)
    }

    func testCleanupRequestEncodesLLMConfigInSnakeCase() throws {
        let request = CleanupRequest(
            rawTranscript: "hello",
            style: .professional,
            dictionaryTerms: ["OmniSpeak"],
            appContext: "Mail",
            llm: CleanupLLMConfig(
                enabled: true,
                provider: "openai",
                baseURL: "https://api.openai.com/v1",
                model: "gpt-4o-mini",
                apiKey: "sk-test",
                transport: .openAICompatible,
                timeoutSeconds: 5.0
            )
        )

        let data = try EngineCoding.encoder.encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["app_context"] as? String, "Mail")
        let llm = try XCTUnwrap(object["llm"] as? [String: Any])
        XCTAssertEqual(llm["enabled"] as? Bool, true)
        XCTAssertEqual(llm["base_url"] as? String, "https://api.openai.com/v1")
        XCTAssertEqual(llm["api_key"] as? String, "sk-test")
        XCTAssertEqual(llm["timeout_seconds"] as? Double, 5.0)
    }

    func testPreferencesResolvesLLMCleanupConfigOnlyWhenEnabledAndConfigured() throws {
        var prefs = OmniVoicePreferences.defaults
        XCTAssertNil(prefs.resolvedLLMCleanupConfig())

        // Local MLX backend resolves immediately to the selected curated cleanup model
        prefs.llmCleanupEnabled = true
        prefs.llmCleanupBackend = .localMLX
        let localResolved = try XCTUnwrap(prefs.resolvedLLMCleanupConfig())
        XCTAssertTrue(localResolved.enabled)
        XCTAssertEqual(localResolved.transport, .localMLX)
        XCTAssertEqual(localResolved.model, CleanupModelRecommendation.defaultProviderID)

        // Switching to external Text LLM requires a configured provider
        prefs.llmCleanupBackend = .textLLM
        XCTAssertNil(prefs.resolvedLLMCleanupConfig())

        prefs.setTextLLMConfiguration(
            TextLLMProviderConfiguration(
                provider: .custom,
                baseURL: "http://127.0.0.1:11434/v1",
                model: "qwen2.5:3b"
            )
        )
        let resolved = try XCTUnwrap(prefs.resolvedLLMCleanupConfig())
        XCTAssertTrue(resolved.enabled)
        XCTAssertEqual(resolved.transport, .openAICompatible)
        XCTAssertEqual(resolved.baseURL, "http://127.0.0.1:11434/v1")
        XCTAssertEqual(resolved.model, "qwen2.5:3b")

        // Round-trip persistence preserves new fields
        let encoded = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(OmniVoicePreferences.self, from: encoded)
        XCTAssertTrue(decoded.llmCleanupEnabled)
        XCTAssertEqual(decoded.llmCleanupBackend, .textLLM)
        XCTAssertEqual(decoded.llmCleanupLocalModelID, CleanupModelRecommendation.defaultProviderID)
        XCTAssertEqual(decoded.llmCleanupProvider, prefs.llmCleanupProvider)
    }
}
