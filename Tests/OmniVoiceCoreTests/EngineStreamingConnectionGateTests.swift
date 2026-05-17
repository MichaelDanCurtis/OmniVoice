import XCTest
@testable import OmniVoiceCore

final class EngineStreamingConnectionGateTests: XCTestCase {
    func testStartingNewConnectionRejectsOldToken() {
        let gate = EngineStreamingConnectionGate()

        let first = gate.start()
        let second = gate.start()

        XCTAssertFalse(gate.isCurrent(first))
        XCTAssertTrue(gate.isCurrent(second))
    }

    func testClearingOldTokenDoesNotClearCurrentToken() {
        let gate = EngineStreamingConnectionGate()

        let first = gate.start()
        let second = gate.start()
        gate.clear(first)

        XCTAssertTrue(gate.isCurrent(second))
    }
}
