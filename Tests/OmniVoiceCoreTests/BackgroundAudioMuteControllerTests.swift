import Foundation
import OmniVoiceCore
import XCTest

private final class MockSystemAudioOutputControl: SystemAudioOutputControl {
    var nextSnapshot: BackgroundAudioMuteSnapshot?
    private(set) var captureCallCount = 0
    private(set) var restoredSnapshots: [BackgroundAudioMuteSnapshot] = []

    func captureAndMuteDefaultOutput() -> BackgroundAudioMuteSnapshot? {
        captureCallCount += 1
        return nextSnapshot
    }

    func restore(_ snapshot: BackgroundAudioMuteSnapshot) {
        restoredSnapshots.append(snapshot)
    }
}

final class BackgroundAudioMuteControllerTests: XCTestCase {
    @MainActor
    func testHardwareMuteCapturesAndRestoresOnce() {
        let backend = MockSystemAudioOutputControl()
        let snapshot = BackgroundAudioMuteSnapshot.hardwareMute(deviceID: 42, elements: [0])
        backend.nextSnapshot = snapshot

        let controller = BackgroundAudioMuteController(outputControl: backend)
        XCTAssertFalse(controller.isHoldingMute)

        controller.beginDictationMute()
        XCTAssertTrue(controller.isHoldingMute)
        XCTAssertEqual(backend.captureCallCount, 1)

        // Re-entrant call while already holding mute must NOT overwrite original snapshot.
        controller.beginDictationMute()
        XCTAssertEqual(backend.captureCallCount, 1)

        controller.endDictationMute()
        XCTAssertFalse(controller.isHoldingMute)
        XCTAssertEqual(backend.restoredSnapshots, [snapshot])

        // Second end is a no-op.
        controller.endDictationMute()
        XCTAssertEqual(backend.restoredSnapshots.count, 1)
    }

    @MainActor
    func testAlreadyMutedOutputIsNotUnmutedOnRelease() {
        let backend = MockSystemAudioOutputControl()
        backend.nextSnapshot = .alreadyMuted

        let controller = BackgroundAudioMuteController(outputControl: backend)
        controller.beginDictationMute()
        XCTAssertTrue(controller.isHoldingMute)

        controller.endDictationMute()
        XCTAssertFalse(controller.isHoldingMute)
        XCTAssertTrue(backend.restoredSnapshots.isEmpty)
    }

    @MainActor
    func testVirtualVolumeFallbackRestoresExactVolume() {
        let backend = MockSystemAudioOutputControl()
        let snapshot = BackgroundAudioMuteSnapshot.virtualMainVolume(deviceID: 77, previousVolume: 0.65)
        backend.nextSnapshot = snapshot

        let controller = BackgroundAudioMuteController(outputControl: backend)
        controller.beginDictationMute()
        controller.endDictationMute()

        XCTAssertEqual(backend.restoredSnapshots, [snapshot])
    }

    func testPreferencesRoundTripMuteBackgroundAudioWhileDictating() throws {
        XCTAssertFalse(OmniVoicePreferences.defaults.muteBackgroundAudioWhileDictating)

        var prefs = OmniVoicePreferences.defaults
        prefs.muteBackgroundAudioWhileDictating = true

        let encoded = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(OmniVoicePreferences.self, from: encoded)
        XCTAssertTrue(decoded.muteBackgroundAudioWhileDictating)

        let rawJSON = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        XCTAssertEqual(rawJSON?["mute_background_audio_while_dictating"] as? Bool, true)

        // Verify EngineCoding (camelCase converted decoding path) works too.
        let convertedDecoded = try EngineCoding.decoder.decode(OmniVoicePreferences.self, from: encoded)
        XCTAssertTrue(convertedDecoded.muteBackgroundAudioWhileDictating)
    }
}
