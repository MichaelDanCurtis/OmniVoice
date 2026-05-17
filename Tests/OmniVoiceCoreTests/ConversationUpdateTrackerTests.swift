import XCTest
@testable import OmniVoiceCore

final class ConversationUpdateTrackerTests: XCTestCase {
    func testRejectsUpdatesForRetiredGeneration() {
        let tracker = ConversationUpdateTracker()
        let generation = UUID()

        tracker.start(generation: generation)
        tracker.retire(generation: generation)

        XCTAssertNil(tracker.begin(generation: generation))
    }

    func testRetiredGenerationCompletionDoesNotIdleNewGeneration() {
        let tracker = ConversationUpdateTracker()
        let oldGeneration = UUID()
        let newGeneration = UUID()

        tracker.start(generation: oldGeneration)
        let oldToken = tracker.begin(generation: oldGeneration)
        tracker.retire(generation: oldGeneration)

        tracker.start(generation: newGeneration)
        let newToken = tracker.begin(generation: newGeneration)
        let idleExpectation = expectation(description: "new generation remains busy")
        idleExpectation.isInverted = true

        Task {
            await tracker.waitForIdle(generation: newGeneration)
            idleExpectation.fulfill()
        }

        if let oldToken {
            tracker.end(oldToken)
        }

        wait(for: [idleExpectation], timeout: 0.05)

        let finishedExpectation = expectation(description: "new generation finishes after its own token ends")
        Task {
            await tracker.waitForIdle(generation: newGeneration)
            finishedExpectation.fulfill()
        }

        if let newToken {
            tracker.end(newToken)
        }

        wait(for: [finishedExpectation], timeout: 1)
    }
}
