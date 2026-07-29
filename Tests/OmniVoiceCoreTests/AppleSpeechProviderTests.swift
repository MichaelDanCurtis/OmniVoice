import XCTest
@testable import OmniVoiceCore

final class AppleSpeechProviderTests: XCTestCase {
    func testAppleSpeechIsUserSelectableAndPersists() {
        XCTAssertTrue(ASRProviderKind.userSelectableCases.contains(.appleSpeech))
        // Normalization must not reset a persisted apple-speech selection.
        XCTAssertEqual(ASRProviderKind.appleSpeech.normalizedForUserSelection, .appleSpeech)
    }

    func testAppleSpeechIsNotDemandedFromTheEngine() {
        // The engine never serves apple-speech (it is a native Swift provider);
        // requiring it engine-side would permanently trip the provider-sync check.
        XCTAssertFalse(EngineProviderContract.requiredASRProviderIDs.contains("apple-speech"))
        XCTAssertTrue(EngineProviderContract.requiredASRProviderIDs.contains("parakeet-tdt-mlx"))
    }

    func testAppleSpeechIsNotEngineBacked() {
        XCTAssertFalse(ASRProviderKind.appleSpeech.isEngineBacked)
        XCTAssertTrue(ASRProviderKind.parakeetTDTMLX.isEngineBacked)
        XCTAssertTrue(ASRProviderKind.whisperLargeV3TurboMLX6Bit.isEngineBacked)
    }

    func testCycleVisitsAppleSpeechThenReturnsToParakeet() {
        var prefs = OmniVoicePreferences.defaults
        prefs.asrProvider = .canaryQwen25B
        prefs.cycleASRProvider()
        XCTAssertEqual(prefs.asrProvider, .appleSpeech)
        prefs.cycleASRProvider()
        XCTAssertEqual(prefs.asrProvider, .parakeetTDTMLX)
    }
}

final class AppleSpeechTranscriptAssemblerTests: XCTestCase {
    func testVolatileResultsReplaceTheCurrentHypothesis() {
        var assembler = AppleSpeechTranscriptAssembler()
        assembler.receive(text: "hello", isFinal: false)
        assembler.receive(text: "hello wor", isFinal: false)
        XCTAssertEqual(assembler.displayText, "hello wor")
    }

    func testFinalResultsAccumulateAndClearTheVolatileTail() {
        var assembler = AppleSpeechTranscriptAssembler()
        assembler.receive(text: "hello world", isFinal: false)
        assembler.receive(text: "Hello world.", isFinal: true)
        assembler.receive(text: "how are", isFinal: false)
        XCTAssertEqual(assembler.displayText, "Hello world. how are")
        assembler.receive(text: "How are you?", isFinal: true)
        XCTAssertEqual(assembler.finalText, "Hello world. How are you?")
    }

    func testFinishReturnsFinalizedPlusUnfinalizedVolatileTail() {
        // If the analyzer never finalizes the last hypothesis, we still keep it.
        var assembler = AppleSpeechTranscriptAssembler()
        assembler.receive(text: "First sentence.", isFinal: true)
        assembler.receive(text: "trailing words", isFinal: false)
        XCTAssertEqual(assembler.finishedText, "First sentence. trailing words")
    }

    func testEmptyAssemblerFinishesEmpty() {
        XCTAssertEqual(AppleSpeechTranscriptAssembler().finishedText, "")
    }
}
