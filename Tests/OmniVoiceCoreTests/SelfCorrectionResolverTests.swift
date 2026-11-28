import Foundation
import XCTest
@testable import OmniVoiceCore

final class SelfCorrectionResolverTests: XCTestCase {
    func testAnchorOverlapSpliceResolvesPageLeftRightExample() {
        let input = "Let's look at this page to the right. Oops, I mean the page to the left."
        let result = SelfCorrectionResolver.resolve(input)
        XCTAssertEqual(result.text, "Let's look at the page to the left.")
        XCTAssertEqual(result.kind, .anchorSplice)
        XCTAssertFalse(result.needsLLMEscalation)
    }

    func testAnchorOverlapPreservesEarlierCompletedSentence() {
        let input = "First check the metrics. Let's look at this page to the right. Oops, I mean the page to the left."
        let result = SelfCorrectionResolver.resolve(input)
        XCTAssertEqual(result.text, "First check the metrics. Let's look at the page to the left.")
        XCTAssertEqual(result.kind, .anchorSplice)
        XCTAssertFalse(result.needsLLMEscalation)
    }

    func testAnchorOverlapHandlesShortDeterminerAndPrepositionPhrases() {
        let storeToHouse = SelfCorrectionResolver.resolve("Going to the store, no wait, the house.")
        XCTAssertEqual(storeToHouse.text, "Going to the house.")
        XCTAssertEqual(storeToHouse.kind, .anchorSplice)
        XCTAssertFalse(storeToHouse.needsLLMEscalation)

        let folderColor = SelfCorrectionResolver.resolve("Open the red folder, sorry I mean blue folder.")
        XCTAssertEqual(folderColor.text, "Open the blue folder.")
        XCTAssertEqual(folderColor.kind, .anchorSplice)
        XCTAssertFalse(folderColor.needsLLMEscalation)
    }

    func testSentenceResetHandlesRephraseAndScratchThatWhileKeepingPriorSentences() {
        let fullRephrase = SelfCorrectionResolver.resolve(
            "We should ship it Friday. Oops, I'm sorry. No, let me rephrase. We should ship it next Tuesday."
        )
        XCTAssertEqual(fullRephrase.text, "We should ship it next Tuesday.")
        XCTAssertEqual(fullRephrase.kind, .sentenceReset)
        XCTAssertFalse(fullRephrase.needsLLMEscalation)

        let scopedRephrase = SelfCorrectionResolver.resolve(
            "The build is green. Ship it Friday. No, let me rephrase. Let's ship it Monday."
        )
        XCTAssertEqual(scopedRephrase.text, "The build is green. Let's ship it Monday.")
        XCTAssertEqual(scopedRephrase.kind, .sentenceReset)
        XCTAssertFalse(scopedRephrase.needsLLMEscalation)
    }

    func testTypedSlotSwapReplacesNumbersTimesCurrencyWeekdaysOrdinalsAndDirections() {
        let timeout = SelfCorrectionResolver.resolve("Change the timeout to 30 seconds, oops, sorry, 45.")
        XCTAssertEqual(timeout.text, "Change the timeout to 45 seconds.")
        XCTAssertEqual(timeout.kind, .typedSlotSwap)
        XCTAssertFalse(timeout.needsLLMEscalation)

        let copies = SelfCorrectionResolver.resolve("Send 5 copies, oops I mean 10")
        XCTAssertEqual(copies.text, "Send 10 copies")
        XCTAssertEqual(copies.kind, .typedSlotSwap)
        XCTAssertFalse(copies.needsLLMEscalation)

        let budget = SelfCorrectionResolver.resolve("Set the budget to $500, no wait, $750")
        XCTAssertEqual(budget.text, "Set the budget to $750")
        XCTAssertEqual(budget.kind, .typedSlotSwap)
        XCTAssertFalse(budget.needsLLMEscalation)

        let weekday = SelfCorrectionResolver.resolve("Meet on Tuesday at 2 PM, wait no, Thursday")
        XCTAssertEqual(weekday.text, "Meet on Thursday at 2 PM")
        XCTAssertEqual(weekday.kind, .typedSlotSwap)
        XCTAssertFalse(weekday.needsLLMEscalation)

        let time = SelfCorrectionResolver.resolve("Meet on Tuesday at 2 PM, wait no, 4 PM")
        XCTAssertEqual(time.text, "Meet on Tuesday at 4 PM")
        XCTAssertEqual(time.kind, .typedSlotSwap)
        XCTAssertFalse(time.needsLLMEscalation)

        let direction = SelfCorrectionResolver.resolve("Look to the right, oops I mean left.")
        XCTAssertEqual(direction.text, "Look to the left.")
        XCTAssertEqual(direction.kind, .typedSlotSwap)
        XCTAssertFalse(direction.needsLLMEscalation)

        let ordinal = SelfCorrectionResolver.resolve("Pick the third option, sorry, fourth.")
        XCTAssertEqual(ordinal.text, "Pick the fourth option.")
        XCTAssertEqual(ordinal.kind, .typedSlotSwap)
        XCTAssertFalse(ordinal.needsLLMEscalation)
    }

    func testAmbiguousSemanticRewriteFlagsSmartHybridLLMEscalation() {
        let input = "Tell Sarah I can make the meeting tomorrow. Oops, sorry, actually let her know I'm double-booked and ask if Friday works instead."
        let result = SelfCorrectionResolver.resolve(input)
        XCTAssertEqual(result.kind, .ambiguousNeedsLLM)
        XCTAssertTrue(result.needsLLMEscalation)
    }

    func testNormalProseDoesNotFalselyTriggerSelfCorrection() {
        let samples = [
            "I mean it works great.",
            "That actually works really well.",
            "I'm sorry about the delay.",
            "Please wait for the build to finish.",
            "There is no correction needed here.",
        ]
        for sample in samples {
            let result = SelfCorrectionResolver.resolve(sample)
            XCTAssertEqual(result.text, sample, "Unexpected mutation for: \(sample)")
            XCTAssertEqual(result.kind, .none, "Unexpected cue match for: \(sample)")
            XCTAssertFalse(result.needsLLMEscalation, "Unexpected LLM escalation for: \(sample)")
        }
    }
}
