import Foundation
import XCTest
@testable import OmniVoiceCore

final class StreamPunctuatorTests: XCTestCase {
    func testIntroductoryCommasAndQuestionDetection() {
        let intro = StreamPunctuator.punctuate("however we should ship this before noon", isFinal: true)
        XCTAssertEqual(intro, "However, we should ship this before noon.")

        let multiIntro = StreamPunctuator.punctuate("for example we can run this locally", isFinal: true)
        XCTAssertEqual(multiIntro, "For example, we can run this locally.")

        let question = StreamPunctuator.punctuate("is there a way we can run this locally", isFinal: true)
        XCTAssertEqual(question, "Is there a way we can run this locally?")

        let wellQuestion = StreamPunctuator.punctuate("well can we make this configurable", isFinal: true)
        XCTAssertEqual(wellQuestion, "Well, can we make this configurable?")
    }

    func testCoordinatingClauseCommasWithoutOverPunctuatingShortPhrases() {
        let clause = StreamPunctuator.punctuate("we built the fast local pass but we can also add a CoreML model", isFinal: true)
        XCTAssertEqual(clause, "We built the fast local pass, but we can also add a CoreML model.")

        let shortPhrase = StreamPunctuator.punctuate("cats and dogs", isFinal: true)
        XCTAssertEqual(shortPhrase, "Cats and dogs.")
    }

    func testLivePartialAddsCommasWithoutPrematureTerminalPeriod() {
        let partial = StreamPunctuator.punctuate("however i think we should keep going", isFinal: false)
        XCTAssertEqual(partial, "However, I think we should keep going")
        XCTAssertFalse(partial.hasSuffix("."))
    }

    func testLocalStreamPolishConfigurationRoundTripsInPreferences() throws {
        var prefs = OmniVoicePreferences.defaults
        XCTAssertEqual(prefs.localStreamPolish, .defaults)
        XCTAssertEqual(prefs.localStreamPolish.punctuationEngine, .coreMLAuto)
        XCTAssertEqual(prefs.localStreamPolish.grammarEngine, .harperAndMacOS)
        XCTAssertTrue(prefs.localStreamPolish.liveStreamPunctuationEnabled)
        XCTAssertTrue(prefs.localStreamPolish.activeWindowVocabularyEnabled)

        prefs.localStreamPolish = LocalStreamPolishConfiguration(
            punctuationEngine: .fastRules,
            grammarEngine: .harperRust,
            liveStreamPunctuationEnabled: false,
            activeWindowVocabularyEnabled: false
        )
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(OmniVoicePreferences.self, from: data)
        XCTAssertEqual(decoded.localStreamPolish, prefs.localStreamPolish)
        XCTAssertFalse(decoded.localStreamPolish.activeWindowVocabularyEnabled)

        let snakeDecoded = try EngineCoding.decoder.decode(OmniVoicePreferences.self, from: data)
        XCTAssertEqual(snakeDecoded.localStreamPolish, prefs.localStreamPolish)
        XCTAssertFalse(snakeDecoded.localStreamPolish.activeWindowVocabularyEnabled)
    }

    func testSpokenNumberedListThreeItemExampleWithLeadIn() {
        let input = "Tell me what you got. First I want to know how long it is. Second, I want to know how big it is. Third, I want to know how wide it is?"
        let expected = """
        Tell me what you got.
        1. I want to know how long it is.
        2. I want to know how big it is.
        3. I want to know how wide it is?
        """
        XCTAssertEqual(StreamPunctuator.formatNumberedLists(input), expected)
        XCTAssertEqual(StreamPunctuator.punctuate(input, isFinal: true), expected)
    }

    func testSpokenNumberedListExplicitPrefixesAndAndFinalConnector() {
        let numberList = "Number one, check the logs. Number two, restart the service. And number three, verify the metrics."
        XCTAssertEqual(
            StreamPunctuator.formatNumberedLists(numberList),
            """
            1. Check the logs.
            2. Restart the service.
            3. Verify the metrics.
            """
        )

        let stepList = "Here is the rollout plan. Step one, run tests. Step two, sign the app. And step three, deploy!"
        XCTAssertEqual(
            StreamPunctuator.formatNumberedLists(stepList),
            """
            Here is the rollout plan.
            1. Run tests.
            2. Sign the app.
            3. Deploy!
            """
        )

        let andThird = "First, open settings. Second, enable fast rules. And third, dictate a list?"
        XCTAssertEqual(
            StreamPunctuator.formatNumberedLists(andThird),
            """
            1. Open settings.
            2. Enable fast rules.
            3. Dictate a list?
            """
        )

        let lyOrdinals = "Firstly, check CPU usage. Secondly, inspect memory. Thirdly, check disk I/O."
        XCTAssertEqual(
            StreamPunctuator.formatNumberedLists(lyOrdinals),
            """
            1. Check CPU usage.
            2. Inspect memory.
            3. Check disk I/O.
            """
        )
    }

    func testSpokenNumberedListGuardrailsLeaveSingleOutOfOrderAndIdiomsUntouched() {
        let singleMarker = "First, let's check the logs."
        XCTAssertEqual(StreamPunctuator.formatNumberedLists(singleMarker), singleMarker)
        XCTAssertEqual(StreamPunctuator.punctuate(singleMarker, isFinal: true), singleMarker)

        let outOfOrder = "Second, review the diff. First, pull main."
        XCTAssertEqual(StreamPunctuator.formatNumberedLists(outOfOrder), outOfOrder)

        let timeIdiom = "First time we shipped it worked. Second time we shipped it was even faster."
        XCTAssertEqual(StreamPunctuator.formatNumberedLists(timeIdiom), timeIdiom)
        XCTAssertEqual(StreamPunctuator.punctuate(timeIdiom, isFinal: true), timeIdiom)

        let articleIdiom = "The first step is easy and the second step takes a second."
        XCTAssertEqual(StreamPunctuator.formatNumberedLists(articleIdiom), articleIdiom)

        let livePartial = "First I want to know how long it is. Second, I want to know how big it is"
        XCTAssertFalse(StreamPunctuator.punctuate(livePartial, isFinal: false).contains("\n1. "))
    }
}
