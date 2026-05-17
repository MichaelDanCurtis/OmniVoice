import XCTest
@testable import OmniVoiceCore

final class DictationCommandParserTests: XCTestCase {
    func testParsesOpenApplicationCommand() {
        let command = DictationCommandParser.parse("Command. Let's open Safari.")

        XCTAssertEqual(
            command,
            DictationCommand(action: .openApplication(name: "Safari"), displayText: "Opening Safari")
        )
    }

    func testParsesLaunchApplicationCommandWithoutPunctuation() {
        let command = DictationCommandParser.parse("command launch Google Chrome")

        XCTAssertEqual(
            command,
            DictationCommand(action: .openApplication(name: "Google Chrome"), displayText: "Opening Google Chrome")
        )
    }

    func testIgnoresNormalDictation() {
        XCTAssertNil(DictationCommandParser.parse("Let's open Safari tomorrow."))
    }

    func testParsesCommandPaletteCommand() {
        let command = DictationCommandParser.parse("Command, show commands")

        XCTAssertEqual(
            command,
            DictationCommand(action: .showCommandPalette, displayText: "Showing commands")
        )
    }

    func testParsesUndoCommand() {
        let command = DictationCommandParser.parse("Command, undo last dictation")

        XCTAssertEqual(
            command,
            DictationCommand(action: .undoLastDictation, displayText: "Undoing last dictation")
        )
    }

    func testAskClaudeCommandRoutesPromptToAIHandoff() {
        let command = DictationCommandParser.parse("Ask Claude, write a quick reply to Jane.")

        XCTAssertEqual(
            command,
            DictationCommand(
                action: .aiHandoff(target: .claude, prompt: "write a quick reply to Jane"),
                displayText: "Asking Claude"
            )
        )
    }

    func testHeyCodexCommandRoutesPromptToAIHandoff() {
        let command = DictationCommandParser.parse("Hey Codex I need a two sentence summary")

        XCTAssertEqual(
            command,
            DictationCommand(
                action: .aiHandoff(target: .codex, prompt: "I need a two sentence summary"),
                displayText: "Asking Codex"
            )
        )
    }

    func testHaveOpenRouterTakeALookRoutesPromptToAIHandoff() {
        let command = DictationCommandParser.parse("Have OpenRouter take a look at this and respond in Spanish")

        XCTAssertEqual(
            command,
            DictationCommand(
                action: .aiHandoff(target: .openRouter, prompt: "at this and respond in Spanish"),
                displayText: "Asking OpenRouter"
            )
        )
    }

    func testAskOpenAICommandRoutesPromptToAIHandoff() {
        let command = DictationCommandParser.parse("Ask OpenAI, make this sound more professional")

        XCTAssertEqual(
            command,
            DictationCommand(
                action: .aiHandoff(target: .openAI, prompt: "make this sound more professional"),
                displayText: "Asking OpenAI"
            )
        )
    }

    func testAIHandoffParserIgnoresOrdinaryMentions() {
        XCTAssertNil(DictationCommandParser.parse("Claude is a useful app for drafting emails."))
    }
}
