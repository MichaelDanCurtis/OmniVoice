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

    func testAskNameIsNoLongerAHandoffCommand() {
        // "ask <name>" is now handled by keyword bindings, not the parser.
        XCTAssertNil(DictationCommandParser.parse("ask claude what rhymes with bill"))
    }

    func testHaveAITakeALookStillHandsOff() {
        let command = DictationCommandParser.parse("have ai take a look at this")
        guard case .aiHandoff(let target, _)? = command?.action else {
            return XCTFail("expected aiHandoff")
        }
        XCTAssertEqual(target, .custom)
    }

    func testAIHandoffParserIgnoresOrdinaryMentions() {
        XCTAssertNil(DictationCommandParser.parse("Claude is a useful app for drafting emails."))
    }
}
