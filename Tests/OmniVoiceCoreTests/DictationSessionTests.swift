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
        XCTAssertTrue(session.canStartCapture)

        session.reset()

        XCTAssertEqual(session.state, .idle)
    }

    func testCanStartCaptureOnlyForIdleOrFailedSessions() {
        var session = DictationSession()
        XCTAssertTrue(session.canStartCapture)

        session.pressHotkey()
        XCTAssertFalse(session.canStartCapture)

        session.releaseHotkey(finalTranscript: "raw")
        XCTAssertFalse(session.canStartCapture)

        session.finishCleanup("Cleaned.")
        XCTAssertFalse(session.canStartCapture)

        session.fail("No speech detected")
        XCTAssertTrue(session.canStartCapture)
    }
}
