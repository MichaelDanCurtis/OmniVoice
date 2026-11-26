import XCTest
@testable import OmniVoiceCore

final class CoreMLProviderTests: XCTestCase {
    func testParakeetCoreMLANEIsUserSelectableAndPersists() throws {
        XCTAssertTrue(ASRProviderKind.userSelectableCases.contains(.parakeetCoreMLANE))
        XCTAssertEqual(ASRProviderKind.parakeetCoreMLANE.normalizedForUserSelection, .parakeetCoreMLANE)

        var prefs = OmniVoicePreferences.defaults
        prefs.asrProvider = .parakeetCoreMLANE
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(OmniVoicePreferences.self, from: data)
        XCTAssertEqual(decoded.asrProvider, .parakeetCoreMLANE)
    }

    func testParakeetCoreMLANEIsNotEngineBackedAndNotDemandedFromEngine() {
        XCTAssertFalse(ASRProviderKind.parakeetCoreMLANE.isEngineBacked)
        XCTAssertFalse(EngineProviderContract.requiredASRProviderIDs.contains("parakeet-tdt-coreml-ane"))
    }

    func testEngineBackendModeRoutingAndPersistence() throws {
        var prefs = OmniVoicePreferences.defaults
        XCTAssertEqual(prefs.engineBackendMode, .auto)
        XCTAssertFalse(prefs.prefersRustEngine(rustBinaryAvailable: true))

        prefs.asrProvider = .parakeetCoreMLANE
        XCTAssertTrue(prefs.prefersRustEngine(rustBinaryAvailable: true))
        XCTAssertFalse(prefs.prefersRustEngine(rustBinaryAvailable: false))

        prefs.asrProvider = .parakeetTDTMLX
        prefs.engineBackendMode = .rustNative
        XCTAssertTrue(prefs.prefersRustEngine(rustBinaryAvailable: false))

        prefs.asrProvider = .parakeetCoreMLANE
        prefs.engineBackendMode = .pythonLegacy
        XCTAssertFalse(prefs.prefersRustEngine(rustBinaryAvailable: true))

        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(OmniVoicePreferences.self, from: data)
        XCTAssertEqual(decoded.engineBackendMode, .pythonLegacy)
    }
}
