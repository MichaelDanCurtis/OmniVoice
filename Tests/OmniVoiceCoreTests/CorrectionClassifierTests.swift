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

    func testApostropheAndPunctuationCustomWordLearned() {
        let before = "Let's open neuron's."
        let after = "Let's open NeroNook."
        let result = CorrectionClassifier.classify(before: before, after: after,
                                                   insertedRange: range(of: "Let's open neuron's.", in: before))
        XCTAssertEqual(result, LearnedCorrection(from: "neuron's", to: "NeroNook"))
    }

    func testMidTypingSingleCharAndDanglingBackspaceRejected() {
        let before = "Let's open neuron's."
        XCTAssertNil(
            CorrectionClassifier.classify(
                before: before,
                after: "Let's open N.",
                insertedRange: range(of: "Let's open neuron's.", in: before)
            )
        )
        XCTAssertNil(
            CorrectionClassifier.classify(
                before: before,
                after: "Let's open neuron'.",
                insertedRange: range(of: "Let's open neuron's.", in: before)
            )
        )
    }

    func testMultiWordProperNounBrandLearned() {
        let before = "Open fuego desktop now"
        let after = "Open Fuego Desktop now"
        let result = CorrectionClassifier.classify(
            before: before,
            after: after,
            insertedRange: range(of: "Open fuego desktop now", in: before)
        )
        XCTAssertEqual(result, LearnedCorrection(from: "fuego desktop", to: "Fuego Desktop"))
    }

    func testDictionaryMatcherFixesExactApostropheAndPhoneticNearMisses() {
        let entries = [
            DictionaryEntry(
                id: "1",
                canonical: "NeroNook",
                aliases: ["neuron's"],
                source: .learned,
                enabled: true,
                createdAt: Date(),
                updatedAt: Date()
            ),
        ]

        XCTAssertEqual(
            DictionaryMatcher.apply(to: "Check neuron's and neuron’s today.", dictionaryTerms: [], dictionaryEntries: entries),
            "Check NeroNook and NeroNook today."
        )
        XCTAssertEqual(
            DictionaryMatcher.apply(to: "Open nero nook or neural nook or nuronook.", dictionaryTerms: [], dictionaryEntries: entries),
            "Open NeroNook or NeroNook or NeroNook."
        )
        XCTAssertEqual(
            DictionaryMatcher.apply(to: "Check neurons right now.", dictionaryTerms: [], dictionaryEntries: entries),
            "Check NeroNook right now."
        )
        // Normal English words must never be touched
        XCTAssertEqual(
            DictionaryMatcher.apply(to: "Read a new book near the nook.", dictionaryTerms: [], dictionaryEntries: entries),
            "Read a new book near the nook."
        )
    }
}
