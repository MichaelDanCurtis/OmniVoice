import XCTest
@testable import OmniVoiceCore

final class AIHandoffConfigurationTests: XCTestCase {
    func testBuiltInProviderPresetsExposeExpectedEndpoints() throws {
        let presets = AIProviderPreset.builtIn

        XCTAssertEqual(presets.map(\.id), [.openRouter, .lmStudio, .ollama, .custom])
        XCTAssertEqual(try XCTUnwrap(AIProviderPreset.preset(for: .openRouter)).baseURL, "https://openrouter.ai/api/v1")
        XCTAssertEqual(try XCTUnwrap(AIProviderPreset.preset(for: .lmStudio)).baseURL, "http://127.0.0.1:1234/v1")
        XCTAssertEqual(try XCTUnwrap(AIProviderPreset.preset(for: .ollama)).baseURL, "http://127.0.0.1:11434/v1")
        XCTAssertEqual(try XCTUnwrap(AIProviderPreset.preset(for: .custom)).baseURL, "")
    }

    func testProviderPresetApplicationKeepsExistingModelWhenPresetHasNoDefaultModel() throws {
        var preferences = OmniVoicePreferences.defaults
        preferences.openAICompatibleModel = "anthropic/claude-sonnet"

        preferences.applyAIProviderPreset(try XCTUnwrap(AIProviderPreset.preset(for: .openRouter)))

        XCTAssertEqual(preferences.aiProviderPresetID, .openRouter)
        XCTAssertEqual(preferences.openAICompatibleBaseURL, "https://openrouter.ai/api/v1")
        XCTAssertEqual(preferences.openAICompatibleModel, "anthropic/claude-sonnet")
    }

    func testPendingAIHandoffCommandPreservesRetryAndOriginalText() {
        let pending = PendingAIHandoffCommand(
            target: .claude,
            prompt: "write a quick reply to Jane",
            context: "Jane asked for a Spanish response.",
            originalText: "Ask Claude, write a quick reply to Jane."
        )

        XCTAssertEqual(pending.target, .claude)
        XCTAssertEqual(pending.provider, "claude")
        XCTAssertEqual(pending.context, "Jane asked for a Spanish response.")
        XCTAssertEqual(pending.originalText, "Ask Claude, write a quick reply to Jane.")
    }
}
