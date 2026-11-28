import XCTest
@testable import OmniVoiceCore

final class CommandModeAndProductivityTests: XCTestCase {
    func testCommandModeParserDetectsEnterExitAndInitialCommand() {
        XCTAssertEqual(CommandModeVoiceParser.parse("Go into command mode."), .enter(initialCommand: nil))
        XCTAssertEqual(
            CommandModeVoiceParser.parse("Command mode, open Safari and search for weather"),
            .enter(initialCommand: "open Safari and search for weather")
        )
        XCTAssertEqual(CommandModeVoiceParser.parse("Exit command mode"), .exit)
        XCTAssertEqual(CommandModeVoiceParser.parse("Hey, please enter command mode."), .enter(initialCommand: nil))
        XCTAssertEqual(CommandModeVoiceParser.parse("Open command mode now"), .enter(initialCommand: nil))
        XCTAssertNil(CommandModeVoiceParser.parse("Command mode doesn't work right now"))
        XCTAssertNil(CommandModeVoiceParser.parse("Let's write a function for command parsing"))
    }

    func testInlineTranslationParserExtractsLanguageAndPayload() {
        let spanish = InlineTranslationParser.parse("In Spanish, can we move our call to 3 PM?")
        XCTAssertEqual(spanish?.targetLanguageCode, "es")
        XCTAssertEqual(spanish?.text, "can we move our call to 3 PM?")

        let japanese = InlineTranslationParser.parse("Translate to Japanese: thank you so much")
        XCTAssertEqual(japanese?.targetLanguageCode, "ja")
        XCTAssertEqual(japanese?.text, "thank you so much")

        XCTAssertNil(InlineTranslationParser.parse("In general, that sounds good."))
    }

    func testVoiceEditDetectorRequiresSelectionAndEditIntent() {
        XCTAssertTrue(VoiceEditDetector.isEditInstruction("Make this shorter and punchier", hasSelectedText: true))
        XCTAssertFalse(VoiceEditDetector.isEditInstruction("Make this shorter and punchier", hasSelectedText: false))
        XCTAssertFalse(VoiceEditDetector.isEditInstruction("Hello team, here are the notes", hasSelectedText: true))
    }

    func testVoiceSnippetExpanderSupportsDynamicPlaceholders() {
        let snippets = [
            VoiceSnippet(id: "1", trigger: "my calendar link", expansion: "Book here: https://cal.com/me ({{clipboard}})"),
        ]
        let expanded = VoiceSnippetExpander.expand(
            "My calendar link.",
            snippets: snippets,
            clipboardText: "30m"
        )
        XCTAssertEqual(expanded, "Book here: https://cal.com/me (30m)")
    }

    func testAppToneContextDetectsCodingChatAndEmail() {
        XCTAssertEqual(
            AppToneContext.detect(bundleIdentifier: "com.microsoft.VSCode", appName: "Code"),
            .coding(appName: "Code")
        )
        XCTAssertEqual(
            AppToneContext.detect(bundleIdentifier: "com.tinyspeck.slackmacgap", appName: "Slack"),
            .chat(appName: "Slack")
        )
        XCTAssertEqual(
            AppToneContext.detect(bundleIdentifier: "com.apple.mail", appName: "Mail"),
            .email(appName: "Mail")
        )
    }

    func testDictationStatsTrackWordsWPMAndTopApps() {
        var stats = DictationStatsSnapshot()
        stats.record(text: "one two three four five six seven eight nine ten", speakingSeconds: 5.0, appName: "Antigravity")
        XCTAssertEqual(stats.totalWords, 10)
        XCTAssertEqual(stats.todayWords, 10)
        XCTAssertEqual(stats.averageWPM, 120)
        XCTAssertEqual(stats.topApps.first?.name, "Antigravity")
    }

    func testNativeDesktopFastPathMatchesCommonVoiceCommands() {
        XCTAssertEqual(
            NativeDesktopFastPath.match("Scroll down"),
            NativeDesktopFastAction(tool: "scroll", stringArgs: ["direction": "down"], intArgs: ["amount": 8])
        )
        XCTAssertEqual(
            NativeDesktopFastPath.match("Open Safari."),
            NativeDesktopFastAction(tool: "open_app", stringArgs: ["name": "Safari"])
        )
        XCTAssertEqual(
            NativeDesktopFastPath.match("Go to github.com"),
            NativeDesktopFastAction(tool: "open_url", stringArgs: ["url": "github.com"])
        )
        XCTAssertEqual(
            NativeDesktopFastPath.match("Click Send"),
            NativeDesktopFastAction(tool: "click_element", stringArgs: ["label": "Send"])
        )
        XCTAssertEqual(
            NativeDesktopFastPath.match("New tab"),
            NativeDesktopFastAction(tool: "press_key", stringArgs: ["key": "t"], arrayArgs: ["modifiers": ["cmd"]])
        )
        XCTAssertEqual(
            NativeDesktopFastPath.match("Reload page"),
            NativeDesktopFastAction(tool: "press_key", stringArgs: ["key": "r"], arrayArgs: ["modifiers": ["cmd"]])
        )
        XCTAssertEqual(
            NativeDesktopFastPath.match("Google Swift concurrency"),
            NativeDesktopFastAction(tool: "open_url", stringArgs: ["url": "https://www.google.com/search?q=Swift%20concurrency"])
        )
        // Multi-step commands fall through to the AI planner
        XCTAssertNil(NativeDesktopFastPath.match("Open Safari and go to github.com"))
    }
}
