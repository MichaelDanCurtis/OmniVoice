import XCTest
@testable import OmniVoiceCore

final class RecordingCueSetTests: XCTestCase {
    func testCueCatalogExposesFifteenSelectableCueSets() {
        XCTAssertEqual(RecordingCueSet.allCases.count, 15)
        XCTAssertEqual(RecordingCueSet.allCases.map(\.displayName), [
            "Soft Click",
            "Glass Tap",
            "Neon Blip",
            "Studio Beep",
            "Radio Chirp",
            "Cassette Punch",
            "Gentle Chime",
            "Minimal Tick",
            "Digital Ping",
            "Warm Pop",
            "Synth Pulse",
            "Airlock",
            "Whisper Tone",
            "VU Tap",
            "Classic Recorder",
        ])
    }

    func testCueSetsProvideShortStartAndStopTonePatterns() {
        for cueSet in RecordingCueSet.allCases {
            XCTAssertFalse(cueSet.startTones.isEmpty, "\(cueSet.displayName) needs a start cue")
            XCTAssertFalse(cueSet.stopTones.isEmpty, "\(cueSet.displayName) needs a stop cue")
            XCTAssertLessThanOrEqual(cueSet.startTones.reduce(0) { $0 + $1.duration }, 0.45)
            XCTAssertLessThanOrEqual(cueSet.stopTones.reduce(0) { $0 + $1.duration }, 0.45)
        }
    }

    func testCueCatalogUsesDiverseTimbresAndPitchMotion() {
        let tones = RecordingCueSet.allCases.flatMap { $0.startTones + $0.stopTones }

        XCTAssertGreaterThanOrEqual(Set(tones.map(\.waveform)).count, 5)
        XCTAssertGreaterThanOrEqual(tones.filter { $0.hasPitchMotion }.count, 12)
        XCTAssertTrue(RecordingCueSet.softClick.startTones.contains { $0.waveform == .noise })
        XCTAssertTrue(RecordingCueSet.glassTap.startTones.contains { $0.waveform == .triangle })
        XCTAssertTrue(RecordingCueSet.cassettePunch.startTones.contains { $0.waveform == .square })
        XCTAssertTrue(RecordingCueSet.warmPop.startTones.contains { $0.waveform == .sawtooth })
    }

    func testRecordingCueVolumeClampsToUsefulRange() {
        XCTAssertEqual(OmniVoicePreferences.clampedRecordingCueVolume(-1), 0)
        XCTAssertEqual(OmniVoicePreferences.clampedRecordingCueVolume(2), 1)
        XCTAssertEqual(OmniVoicePreferences.clampedRecordingCueVolume(0.28), 0.28)
    }
}
