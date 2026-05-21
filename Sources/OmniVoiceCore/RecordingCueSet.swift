public enum RecordingCueWaveform: String, CaseIterable, Codable, Hashable, Sendable {
    case sine
    case triangle
    case square
    case sawtooth
    case noise
}

public enum RecordingCueEvent: String, CaseIterable, Codable, Hashable, Sendable {
    case start
    case stop
}

public struct RecordingCueTone: Equatable, Sendable {
    public let frequency: Double
    public let endFrequency: Double?
    public let duration: Double
    public let amplitude: Double
    public let waveform: RecordingCueWaveform

    public init(
        frequency: Double,
        endFrequency: Double? = nil,
        duration: Double,
        amplitude: Double = 1.0,
        waveform: RecordingCueWaveform = .sine
    ) {
        self.frequency = frequency
        self.endFrequency = endFrequency
        self.duration = duration
        self.amplitude = amplitude
        self.waveform = waveform
    }

    public var hasPitchMotion: Bool {
        guard let endFrequency else {
            return false
        }
        return abs(endFrequency - frequency) > 0.1
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
            [
                RecordingCueTone(frequency: 3_200, duration: 0.018, amplitude: 0.40, waveform: .noise),
                RecordingCueTone(frequency: 1_900, endFrequency: 1_420, duration: 0.024, amplitude: 0.36, waveform: .triangle),
            ]
        case .glassTap:
            [
                RecordingCueTone(frequency: 1_420, endFrequency: 2_760, duration: 0.040, amplitude: 0.34, waveform: .triangle),
                RecordingCueTone(frequency: 3_140, endFrequency: 2_360, duration: 0.072, amplitude: 0.26, waveform: .sine),
            ]
        case .neonBlip:
            [
                RecordingCueTone(frequency: 510, endFrequency: 980, duration: 0.060, amplitude: 0.42, waveform: .square),
                RecordingCueTone(frequency: 1_420, endFrequency: 1_960, duration: 0.050, amplitude: 0.34, waveform: .sine),
            ]
        case .studioBeep:
            [
                RecordingCueTone(frequency: 880, duration: 0.090, amplitude: 0.32, waveform: .sine),
                RecordingCueTone(frequency: 1_320, endFrequency: 1_180, duration: 0.050, amplitude: 0.22, waveform: .triangle),
            ]
        case .radioChirp:
            [
                RecordingCueTone(frequency: 860, endFrequency: 1_360, duration: 0.034, amplitude: 0.32, waveform: .sawtooth),
                RecordingCueTone(frequency: 1_240, endFrequency: 1_740, duration: 0.040, amplitude: 0.30, waveform: .square),
                RecordingCueTone(frequency: 1_820, endFrequency: 1_260, duration: 0.052, amplitude: 0.28, waveform: .triangle),
            ]
        case .cassettePunch:
            [
                RecordingCueTone(frequency: 160, duration: 0.028, amplitude: 0.44, waveform: .square),
                RecordingCueTone(frequency: 2_800, duration: 0.032, amplitude: 0.22, waveform: .noise),
                RecordingCueTone(frequency: 420, endFrequency: 660, duration: 0.060, amplitude: 0.28, waveform: .sawtooth),
            ]
        case .gentleChime:
            [
                RecordingCueTone(frequency: 784, duration: 0.078, amplitude: 0.28, waveform: .sine),
                RecordingCueTone(frequency: 1_176, endFrequency: 1_254, duration: 0.120, amplitude: 0.22, waveform: .triangle),
            ]
        case .minimalTick:
            [
                RecordingCueTone(frequency: 4_400, duration: 0.016, amplitude: 0.34, waveform: .noise),
                RecordingCueTone(frequency: 2_060, duration: 0.018, amplitude: 0.28, waveform: .triangle),
            ]
        case .digitalPing:
            [
                RecordingCueTone(frequency: 1_024, duration: 0.040, amplitude: 0.32, waveform: .square),
                RecordingCueTone(frequency: 2_048, endFrequency: 2_304, duration: 0.050, amplitude: 0.26, waveform: .sine),
            ]
        case .warmPop:
            [
                RecordingCueTone(frequency: 240, endFrequency: 140, duration: 0.040, amplitude: 0.38, waveform: .sawtooth),
                RecordingCueTone(frequency: 520, endFrequency: 760, duration: 0.084, amplitude: 0.24, waveform: .triangle),
            ]
        case .synthPulse:
            [
                RecordingCueTone(frequency: 440, endFrequency: 520, duration: 0.052, amplitude: 0.34, waveform: .square),
                RecordingCueTone(frequency: 760, endFrequency: 1_140, duration: 0.052, amplitude: 0.30, waveform: .sawtooth),
                RecordingCueTone(frequency: 1_240, endFrequency: 1_640, duration: 0.052, amplitude: 0.24, waveform: .sine),
            ]
        case .airlock:
            [
                RecordingCueTone(frequency: 120, endFrequency: 260, duration: 0.090, amplitude: 0.34, waveform: .sawtooth),
                RecordingCueTone(frequency: 2_600, duration: 0.038, amplitude: 0.18, waveform: .noise),
                RecordingCueTone(frequency: 540, duration: 0.055, amplitude: 0.24, waveform: .triangle),
            ]
        case .whisperTone:
            [
                RecordingCueTone(frequency: 1_040, endFrequency: 1_380, duration: 0.110, amplitude: 0.18, waveform: .sine),
                RecordingCueTone(frequency: 3_600, duration: 0.040, amplitude: 0.09, waveform: .noise),
            ]
        case .vuTap:
            [
                RecordingCueTone(frequency: 360, duration: 0.026, amplitude: 0.32, waveform: .triangle),
                RecordingCueTone(frequency: 720, duration: 0.026, amplitude: 0.30, waveform: .triangle),
                RecordingCueTone(frequency: 1_440, endFrequency: 1_620, duration: 0.042, amplitude: 0.26, waveform: .triangle),
            ]
        case .classicRecorder:
            [
                RecordingCueTone(frequency: 1_000, duration: 0.052, amplitude: 0.34, waveform: .square),
                RecordingCueTone(frequency: 2_400, duration: 0.028, amplitude: 0.18, waveform: .noise),
                RecordingCueTone(frequency: 1_000, duration: 0.052, amplitude: 0.28, waveform: .sine),
            ]
        }
    }

    public var stopTones: [RecordingCueTone] {
        switch self {
        case .softClick:
            [
                RecordingCueTone(frequency: 2_600, duration: 0.016, amplitude: 0.34, waveform: .noise),
                RecordingCueTone(frequency: 1_240, endFrequency: 920, duration: 0.022, amplitude: 0.32, waveform: .triangle),
            ]
        case .glassTap:
            [
                RecordingCueTone(frequency: 2_520, endFrequency: 1_480, duration: 0.042, amplitude: 0.28, waveform: .triangle),
                RecordingCueTone(frequency: 1_060, duration: 0.066, amplitude: 0.28, waveform: .sine),
            ]
        case .neonBlip:
            [
                RecordingCueTone(frequency: 1_760, endFrequency: 1_040, duration: 0.052, amplitude: 0.32, waveform: .square),
                RecordingCueTone(frequency: 740, duration: 0.070, amplitude: 0.34, waveform: .sine),
            ]
        case .studioBeep:
            [
                RecordingCueTone(frequency: 660, duration: 0.086, amplitude: 0.32, waveform: .sine),
                RecordingCueTone(frequency: 440, endFrequency: 390, duration: 0.044, amplitude: 0.22, waveform: .triangle),
            ]
        case .radioChirp:
            [
                RecordingCueTone(frequency: 1_640, endFrequency: 1_180, duration: 0.034, amplitude: 0.28, waveform: .sawtooth),
                RecordingCueTone(frequency: 980, endFrequency: 640, duration: 0.040, amplitude: 0.30, waveform: .square),
                RecordingCueTone(frequency: 760, duration: 0.052, amplitude: 0.28, waveform: .triangle),
            ]
        case .cassettePunch:
            [
                RecordingCueTone(frequency: 520, duration: 0.032, amplitude: 0.30, waveform: .square),
                RecordingCueTone(frequency: 2_200, duration: 0.030, amplitude: 0.16, waveform: .noise),
                RecordingCueTone(frequency: 190, endFrequency: 120, duration: 0.058, amplitude: 0.34, waveform: .sawtooth),
            ]
        case .gentleChime:
            [
                RecordingCueTone(frequency: 1_176, endFrequency: 1_058, duration: 0.074, amplitude: 0.22, waveform: .triangle),
                RecordingCueTone(frequency: 784, duration: 0.116, amplitude: 0.28, waveform: .sine),
            ]
        case .minimalTick:
            [
                RecordingCueTone(frequency: 3_600, duration: 0.014, amplitude: 0.30, waveform: .noise),
                RecordingCueTone(frequency: 1_420, duration: 0.018, amplitude: 0.24, waveform: .triangle),
            ]
        case .digitalPing:
            [
                RecordingCueTone(frequency: 2_048, endFrequency: 1_536, duration: 0.040, amplitude: 0.28, waveform: .square),
                RecordingCueTone(frequency: 1_024, duration: 0.060, amplitude: 0.30, waveform: .sine),
            ]
        case .warmPop:
            [
                RecordingCueTone(frequency: 620, endFrequency: 360, duration: 0.040, amplitude: 0.26, waveform: .sawtooth),
                RecordingCueTone(frequency: 220, duration: 0.078, amplitude: 0.34, waveform: .triangle),
            ]
        case .synthPulse:
            [
                RecordingCueTone(frequency: 1_420, endFrequency: 980, duration: 0.050, amplitude: 0.26, waveform: .sawtooth),
                RecordingCueTone(frequency: 760, endFrequency: 520, duration: 0.050, amplitude: 0.30, waveform: .square),
                RecordingCueTone(frequency: 440, duration: 0.060, amplitude: 0.32, waveform: .sine),
            ]
        case .airlock:
            [
                RecordingCueTone(frequency: 540, duration: 0.046, amplitude: 0.24, waveform: .triangle),
                RecordingCueTone(frequency: 260, endFrequency: 110, duration: 0.110, amplitude: 0.36, waveform: .sawtooth),
                RecordingCueTone(frequency: 1_800, duration: 0.025, amplitude: 0.12, waveform: .noise),
            ]
        case .whisperTone:
            [
                RecordingCueTone(frequency: 1_380, endFrequency: 960, duration: 0.092, amplitude: 0.16, waveform: .sine),
                RecordingCueTone(frequency: 2_800, duration: 0.042, amplitude: 0.08, waveform: .noise),
            ]
        case .vuTap:
            [
                RecordingCueTone(frequency: 1_440, duration: 0.024, amplitude: 0.24, waveform: .triangle),
                RecordingCueTone(frequency: 720, duration: 0.026, amplitude: 0.28, waveform: .triangle),
                RecordingCueTone(frequency: 360, endFrequency: 320, duration: 0.046, amplitude: 0.30, waveform: .triangle),
            ]
        case .classicRecorder:
            [
                RecordingCueTone(frequency: 760, duration: 0.060, amplitude: 0.30, waveform: .square),
                RecordingCueTone(frequency: 520, endFrequency: 460, duration: 0.078, amplitude: 0.32, waveform: .sine),
                RecordingCueTone(frequency: 1_800, duration: 0.024, amplitude: 0.12, waveform: .noise),
            ]
        }
    }
}
