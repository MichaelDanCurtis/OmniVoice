import XCTest
@testable import OmniVoiceCore

final class DictationSessionTests: XCTestCase {
    func testPressHotkeyMovesFromIdleToListening() {
        var session = DictationSession()

        session.pressHotkey()

        XCTAssertEqual(session.state, .listening)
        XCTAssertEqual(session.partialTranscript, "")
    }

    func testPartialTranscriptUpdatesOnlyWhileListening() {
        var session = DictationSession()

        session.receivePartial("ignored")
        XCTAssertEqual(session.partialTranscript, "")

        session.pressHotkey()
        session.receivePartial("hello there")

        XCTAssertEqual(session.partialTranscript, "hello there")
    }

    func testReleaseMovesToCleaningWithFinalTranscript() {
        var session = DictationSession()
        session.pressHotkey()
        session.receivePartial("going to the store")

        session.releaseHotkey(finalTranscript: "going to the house")

        XCTAssertEqual(session.state, .cleaning)
        XCTAssertEqual(session.finalTranscript, "going to the house")
    }

    func testCleanupResultMovesToInserting() {
        var session = DictationSession()
        session.pressHotkey()
        session.releaseHotkey(finalTranscript: "raw")

        session.finishCleanup("Cleaned.")

        XCTAssertEqual(session.state, .inserting)
        XCTAssertEqual(session.finalTextToInsert, "Cleaned.")
    }

    func testResetReturnsToIdle() {
        var session = DictationSession()
        session.pressHotkey()
        session.releaseHotkey(finalTranscript: "raw")
        session.finishCleanup("Cleaned.")

        session.reset()

        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.partialTranscript, "")
        XCTAssertEqual(session.finalTranscript, "")
        XCTAssertEqual(session.finalTextToInsert, "")
    }

    func testFailurePreservesMessageUntilReset() {
        var session = DictationSession()

        session.fail("Engine unavailable")

        XCTAssertEqual(session.state, .failed("Engine unavailable"))

        session.reset()

        XCTAssertEqual(session.state, .idle)
    }
}
