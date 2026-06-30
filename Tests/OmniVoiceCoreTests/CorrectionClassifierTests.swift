import XCTest
@testable import OmniVoiceCore

final class CorrectionClassifierTests: XCTestCase {
    private func range(of substring: String, in text: String) -> Range<String.Index> {
        text.range(of: substring)!
    }

    func testCasingCorrectionLearned() {
        let before = "I love figma today"
        let after = "I love Figma today"
        let result = CorrectionClassifier.classify(before: before, after: after,
                                                   insertedRange: range(of: "figma", in: before))
        XCTAssertEqual(result, LearnedCorrection(from: "figma", to: "Figma"))
    }

    func testMishearingLearned() {
        let before = "open fig ma now"
        let after = "open Figma now"
        let result = CorrectionClassifier.classify(before: before, after: after,
                                                   insertedRange: range(of: "fig ma", in: before))
        XCTAssertEqual(result, LearnedCorrection(from: "fig ma", to: "Figma"))
    }

    func testHomophoneRejected() {
        let before = "put it over there"
        let after = "put it over their"
        let result = CorrectionClassifier.classify(before: before, after: after,
                                                   insertedRange: range(of: "there", in: before))
        XCTAssertNil(result) // "their" is a common word — never a learned rule
    }

    func testUnrelatedEditIgnored() {
        let before = "hello figma world"
        let after = "HELLO figma world" // edit is outside the inserted span
        let result = CorrectionClassifier.classify(before: before, after: after,
                                                   insertedRange: range(of: "figma", in: before))
        XCTAssertNil(result)
    }

    func testMultiWordChangeRejected() {
        let before = "the quick fox"
        let after = "the very fast fox"
        let result = CorrectionClassifier.classify(before: before, after: after,
                                                   insertedRange: range(of: "quick", in: before))
        XCTAssertNil(result)
    }

    func testNoChangeReturnsNil() {
        let before = "same text"
        let result = CorrectionClassifier.classify(before: before, after: before,
                                                   insertedRange: range(of: "same", in: before))
        XCTAssertNil(result)
    }
}
