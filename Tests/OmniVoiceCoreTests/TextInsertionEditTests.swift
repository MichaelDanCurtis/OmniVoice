import XCTest
@testable import OmniVoiceCore

final class TextInsertionEditTests: XCTestCase {
    func testInsertsIntoExistingValueAtSelectedRange() {
        let edit = TextInsertionEdit.make(
            currentValue: "Hello world",
            selectedRange: NSRange(location: 6, length: 5),
            insertion: "there",
            placeholderValues: []
        )

        XCTAssertEqual(edit, TextInsertionEdit(text: "Hello there", cursorLocation: 11, ignoredPlaceholder: false))
    }

    func testTreatsAccessibilityPlaceholderValueAsEmptyField() {
        let edit = TextInsertionEdit.make(
            currentValue: "Ask for follow-up changes",
            selectedRange: NSRange(location: 0, length: 0),
            insertion: "This is the dictated text.",
            placeholderValues: ["Ask for follow-up changes"]
        )

        XCTAssertEqual(
            edit,
            TextInsertionEdit(text: "This is the dictated text.", cursorLocation: 26, ignoredPlaceholder: true)
        )
    }

    func testTreatsKnownCodexPlaceholderAsEmptyWithoutAccessibilityPlaceholderValue() {
        let edit = TextInsertionEdit.make(
            currentValue: "Ask for follow-up changes",
            selectedRange: NSRange(location: 0, length: 0),
            insertion: "Fix this permanently.",
            placeholderValues: []
        )

        XCTAssertEqual(
            edit,
            TextInsertionEdit(text: "Fix this permanently.", cursorLocation: 21, ignoredPlaceholder: true)
        )
    }

    func testTreatsKnownClaudeCommandHintAsEmptyWithoutAccessibilityPlaceholderValue() {
        let edit = TextInsertionEdit.make(
            currentValue: "Type / for commands",
            selectedRange: NSRange(location: 0, length: 0),
            insertion: "Open the release notes.",
            placeholderValues: []
        )

        XCTAssertEqual(
            edit,
            TextInsertionEdit(text: "Open the release notes.", cursorLocation: 23, ignoredPlaceholder: true)
        )
    }

    func testStripsKnownCodexPlaceholderWhenItIsAppendedToInsertedText() {
        let edit = TextInsertionEdit.make(
            currentValue: "",
            selectedRange: NSRange(location: 0, length: 0),
            insertion: "Fix this permanently. Ask for follow-up changes",
            placeholderValues: []
        )

        XCTAssertEqual(
            edit,
            TextInsertionEdit(text: "Fix this permanently.", cursorLocation: 21, ignoredPlaceholder: false)
        )
    }

    func testStripsKnownClaudeCommandHintWhenItIsAppendedToInsertedText() {
        let edit = TextInsertionEdit.make(
            currentValue: "",
            selectedRange: NSRange(location: 0, length: 0),
            insertion: "Open the release notes. Type / for commands",
            placeholderValues: []
        )

        XCTAssertEqual(
            edit,
            TextInsertionEdit(text: "Open the release notes.", cursorLocation: 23, ignoredPlaceholder: false)
        )
    }

    func testStripsSpokenClaudeCommandHintWhenItIsAppendedToInsertedText() {
        let edit = TextInsertionEdit.make(
            currentValue: "",
            selectedRange: NSRange(location: 0, length: 0),
            insertion: "Open the release notes. Type slash for commands",
            placeholderValues: []
        )

        XCTAssertEqual(
            edit,
            TextInsertionEdit(text: "Open the release notes.", cursorLocation: 23, ignoredPlaceholder: false)
        )
    }

    func testStripsAccessibilityPlaceholderWhenItIsAppendedToInsertedText() {
        let edit = TextInsertionEdit.make(
            currentValue: "",
            selectedRange: NSRange(location: 0, length: 0),
            insertion: "Open the release notes. Message the assistant",
            placeholderValues: ["Message the assistant"]
        )

        XCTAssertEqual(
            edit,
            TextInsertionEdit(text: "Open the release notes.", cursorLocation: 23, ignoredPlaceholder: false)
        )
    }

    func testRejectsOutOfBoundsRangesWhenCurrentValueIsRealText() {
        let edit = TextInsertionEdit.make(
            currentValue: "Real text",
            selectedRange: NSRange(location: 99, length: 0),
            insertion: "ignored",
            placeholderValues: ["Ask for follow-up changes"]
        )

        XCTAssertNil(edit)
    }

    func testRestoresPreviousValueWhenInsertedValueIsUnchanged() {
        let restored = TextInsertionEdit.restoredPreviousValue(
            currentValue: "Hello dictated",
            insertedValue: "Hello dictated",
            previousValue: "Hello "
        )

        XCTAssertEqual(restored, "Hello ")
    }

    func testRefusesRestoreWhenFieldChangedAfterInsertion() {
        let restored = TextInsertionEdit.restoredPreviousValue(
            currentValue: "Hello dictated plus later typing",
            insertedValue: "Hello dictated",
            previousValue: "Hello "
        )

        XCTAssertNil(restored)
    }
}
