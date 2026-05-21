public struct RecordingCueTone: Equatable, Sendable {
    public let frequency: Double
    public let duration: Double
    public let amplitude: Double

    public init(frequency: Double, duration: Double, amplitude: Double = 1.0) {
        self.frequency = frequency
        self.duration = duration
        self.amplitude = amplitude
    }
}

public enum RecordingCueSet: String, CaseIterable, Codable, Hashable, Sendable {
    case softClick = "soft_click"
    case glassTap = "glass_tap"
    case neonBlip = "neon_blip"
    case studioBeep = "studio_beep"
    case radioChirp = "radio_chirp"
    case cassettePunch = "cassette_punch"
    case gentleChime = "gentle_chime"
    case minimalTick = "minimal_tick"
    case digitalPing = "digital_ping"
    case warmPop = "warm_pop"
    case synthPulse = "synth_pulse"
    case airlock = "airlock"
    case whisperTone = "whisper_tone"
    case vuTap = "vu_tap"
    case classicRecorder = "classic_recorder"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .softClick: "Soft Click"
        case .glassTap: "Glass Tap"
        case .neonBlip: "Neon Blip"
        case .studioBeep: "Studio Beep"
        case .radioChirp: "Radio Chirp"
        case .cassettePunch: "Cassette Punch"
        case .gentleChime: "Gentle Chime"
        case .minimalTick: "Minimal Tick"
        case .digitalPing: "Digital Ping"
        case .warmPop: "Warm Pop"
        case .synthPulse: "Synth Pulse"
        case .airlock: "Airlock"
        case .whisperTone: "Whisper Tone"
        case .vuTap: "VU Tap"
        case .classicRecorder: "Classic Recorder"
        }
    }

    public var startTones: [RecordingCueTone] {
        switch self {
        case .softClick:
            [RecordingCueTone(frequency: 1_760, duration: 0.035, amplitude: 0.75)]
        case .glassTap:
            [
                RecordingCueTone(frequency: 1_320, duration: 0.055, amplitude: 0.55),
                RecordingCueTone(frequency: 2_480, duration: 0.080, amplitude: 0.42),
            ]
        case .neonBlip:
            [
                RecordingCueTone(frequency: 740, duration: 0.070, amplitude: 0.55),
                RecordingCueTone(frequency: 1_480, duration: 0.070, amplitude: 0.48),
            ]
        case .studioBeep:
            [RecordingCueTone(frequency: 880, duration: 0.140, amplitude: 0.50)]
        case .radioChirp:
            [
                RecordingCueTone(frequency: 1_080, duration: 0.045, amplitude: 0.48),
                RecordingCueTone(frequency: 1_240, duration: 0.045, amplitude: 0.44),
                RecordingCueTone(frequency: 1_420, duration: 0.055, amplitude: 0.40),
            ]
        case .cassettePunch:
            [
                RecordingCueTone(frequency: 220, duration: 0.035, amplitude: 0.60),
                RecordingCueTone(frequency: 660, duration: 0.070, amplitude: 0.45),
            ]
        case .gentleChime:
            [
                RecordingCueTone(frequency: 784, duration: 0.090, amplitude: 0.44),
                RecordingCueTone(frequency: 1_176, duration: 0.120, amplitude: 0.38),
            ]
        case .minimalTick:
            [RecordingCueTone(frequency: 1_960, duration: 0.028, amplitude: 0.55)]
        case .digitalPing:
            [
                RecordingCueTone(frequency: 1_024, duration: 0.060, amplitude: 0.50),
                RecordingCueTone(frequency: 2_048, duration: 0.060, amplitude: 0.46),
            ]
        case .warmPop:
            [
                RecordingCueTone(frequency: 330, duration: 0.045, amplitude: 0.52),
                RecordingCueTone(frequency: 660, duration: 0.085, amplitude: 0.42),
            ]
        case .synthPulse:
            [
                RecordingCueTone(frequency: 520, duration: 0.060, amplitude: 0.50),
                RecordingCueTone(frequency: 780, duration: 0.060, amplitude: 0.46),
                RecordingCueTone(frequency: 1_040, duration: 0.060, amplitude: 0.42),
            ]
        case .airlock:
            [
                RecordingCueTone(frequency: 180, duration: 0.080, amplitude: 0.48),
                RecordingCueTone(frequency: 540, duration: 0.090, amplitude: 0.38),
            ]
        case .whisperTone:
            [
                RecordingCueTone(frequency: 1_120, duration: 0.110, amplitude: 0.30),
                RecordingCueTone(frequency: 1_680, duration: 0.110, amplitude: 0.24),
            ]
        case .vuTap:
            [
                RecordingCueTone(frequency: 500, duration: 0.035, amplitude: 0.54),
                RecordingCueTone(frequency: 1_000, duration: 0.035, amplitude: 0.48),
                RecordingCueTone(frequency: 1_500, duration: 0.050, amplitude: 0.42),
            ]
        case .classicRecorder:
            [
                RecordingCueTone(frequency: 1_000, duration: 0.060, amplitude: 0.54),
                RecordingCueTone(frequency: 1_000, duration: 0.060, amplitude: 0.46),
            ]
        }
    }

    public var stopTones: [RecordingCueTone] {
        switch self {
        case .softClick:
            [RecordingCueTone(frequency: 1_280, duration: 0.032, amplitude: 0.62)]
        case .glassTap:
            [
                RecordingCueTone(frequency: 2_120, duration: 0.055, amplitude: 0.40),
                RecordingCueTone(frequency: 1_080, duration: 0.075, amplitude: 0.46),
            ]
        case .neonBlip:
            [
                RecordingCueTone(frequency: 1_480, duration: 0.060, amplitude: 0.46),
                RecordingCueTone(frequency: 740, duration: 0.080, amplitude: 0.52),
            ]
        case .studioBeep:
            [RecordingCueTone(frequency: 660, duration: 0.120, amplitude: 0.48)]
        case .radioChirp:
            [
                RecordingCueTone(frequency: 1_420, duration: 0.040, amplitude: 0.38),
                RecordingCueTone(frequency: 1_080, duration: 0.040, amplitude: 0.44),
                RecordingCueTone(frequency: 840, duration: 0.055, amplitude: 0.48),
            ]
        case .cassettePunch:
            [
                RecordingCueTone(frequency: 660, duration: 0.050, amplitude: 0.42),
                RecordingCueTone(frequency: 220, duration: 0.050, amplitude: 0.50),
            ]
        case .gentleChime:
            [
                RecordingCueTone(frequency: 1_176, duration: 0.080, amplitude: 0.36),
                RecordingCueTone(frequency: 784, duration: 0.130, amplitude: 0.42),
            ]
        case .minimalTick:
            [RecordingCueTone(frequency: 1_360, duration: 0.026, amplitude: 0.50)]
        case .digitalPing:
            [
                RecordingCueTone(frequency: 2_048, duration: 0.050, amplitude: 0.40),
                RecordingCueTone(frequency: 1_024, duration: 0.070, amplitude: 0.48),
            ]
        case .warmPop:
            [
                RecordingCueTone(frequency: 660, duration: 0.045, amplitude: 0.38),
                RecordingCueTone(frequency: 330, duration: 0.085, amplitude: 0.48),
            ]
        case .synthPulse:
            [
                RecordingCueTone(frequency: 1_040, duration: 0.055, amplitude: 0.40),
                RecordingCueTone(frequency: 780, duration: 0.055, amplitude: 0.44),
                RecordingCueTone(frequency: 520, duration: 0.070, amplitude: 0.48),
            ]
        case .airlock:
            [
                RecordingCueTone(frequency: 540, duration: 0.070, amplitude: 0.34),
                RecordingCueTone(frequency: 180, duration: 0.120, amplitude: 0.48),
            ]
        case .whisperTone:
            [
                RecordingCueTone(frequency: 1_680, duration: 0.090, amplitude: 0.22),
                RecordingCueTone(frequency: 1_120, duration: 0.130, amplitude: 0.30),
            ]
        case .vuTap:
            [
                RecordingCueTone(frequency: 1_500, duration: 0.030, amplitude: 0.38),
                RecordingCueTone(frequency: 1_000, duration: 0.035, amplitude: 0.44),
                RecordingCueTone(frequency: 500, duration: 0.055, amplitude: 0.50),
            ]
        case .classicRecorder:
            [
                RecordingCueTone(frequency: 760, duration: 0.080, amplitude: 0.46),
                RecordingCueTone(frequency: 520, duration: 0.090, amplitude: 0.52),
            ]
        }
    }
}
