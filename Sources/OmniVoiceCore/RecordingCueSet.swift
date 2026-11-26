public enum RecordingCueWaveform: String, CaseIterable, Codable, Hashable, Sendable {
    case sine
    case triangle
    case square
    case sawtooth
    case noise
    case bell
    case marimba
    case pluck
    case pad
    case drop
}

public enum RecordingCueEvent: String, CaseIterable, Codable, Hashable, Sendable {
    case start
    case stop
    case empty
}

public enum RecordingCueTiming: String, CaseIterable, Codable, Hashable, Sendable {
    case start
    case stop
    case both

    public var displayName: String {
        switch self {
        case .start: "Start"
        case .stop: "Stop"
        case .both: "Both"
        }
    }
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
    case warmMarimba = "warm_marimba"
    case softKalimba = "soft_kalimba"
    case silkHarp = "silk_harp"
    case waterDrop = "water_drop"
    case velvetChime = "velvet_chime"
    case zenBowl = "zen_bowl"
    case pebbleTap = "pebble_tap"
    case bambooPluck = "bamboo_pluck"
    case celestaSpark = "celesta_spark"
    case rhodesChord = "rhodes_chord"
    case cloudSwell = "cloud_swell"
    case mellowFifth = "mellow_fifth"
    case musicBox = "music_box"
    case morningDew = "morning_dew"
    case softWoodblock = "soft_woodblock"
    case crystalBell = "crystal_bell"
    case lofiKey = "lofi_key"
    case harpGliss = "harp_gliss"
    case celloPluck = "cello_pluck"
    case silkWhisper = "silk_whisper"

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
        case .warmMarimba: "Warm Marimba"
        case .softKalimba: "Soft Kalimba"
        case .silkHarp: "Silk Harp"
        case .waterDrop: "Water Droplet"
        case .velvetChime: "Velvet Chime"
        case .zenBowl: "Zen Singing Bowl"
        case .pebbleTap: "Pebble Tap"
        case .bambooPluck: "Bamboo Pluck"
        case .celestaSpark: "Celesta Spark"
        case .rhodesChord: "Electric Piano"
        case .cloudSwell: "Cloud Swell"
        case .mellowFifth: "Mellow Fifth"
        case .musicBox: "Music Box"
        case .morningDew: "Morning Dew"
        case .softWoodblock: "Soft Woodblock"
        case .crystalBell: "Crystal Bell"
        case .lofiKey: "Lo-Fi Key"
        case .harpGliss: "Harp Gliss"
        case .celloPluck: "Cello Pluck"
        case .silkWhisper: "Silk Whisper"
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
        case .warmMarimba:
            [
                RecordingCueTone(frequency: 523.25, duration: 0.095, amplitude: 0.42, waveform: .marimba),
                RecordingCueTone(frequency: 659.25, duration: 0.135, amplitude: 0.38, waveform: .marimba),
            ]
        case .softKalimba:
            [
                RecordingCueTone(frequency: 587.33, duration: 0.085, amplitude: 0.36, waveform: .pluck),
                RecordingCueTone(frequency: 880.0, duration: 0.145, amplitude: 0.32, waveform: .pluck),
            ]
        case .silkHarp:
            [
                RecordingCueTone(frequency: 440.0, duration: 0.065, amplitude: 0.30, waveform: .pluck),
                RecordingCueTone(frequency: 554.37, duration: 0.065, amplitude: 0.32, waveform: .pluck),
                RecordingCueTone(frequency: 659.25, duration: 0.130, amplitude: 0.34, waveform: .pluck),
            ]
        case .waterDrop:
            [
                RecordingCueTone(frequency: 480, endFrequency: 960, duration: 0.078, amplitude: 0.38, waveform: .drop),
            ]
        case .velvetChime:
            [
                RecordingCueTone(frequency: 659.25, duration: 0.105, amplitude: 0.30, waveform: .bell),
                RecordingCueTone(frequency: 987.77, duration: 0.165, amplitude: 0.26, waveform: .bell),
            ]
        case .zenBowl:
            [
                RecordingCueTone(frequency: 396.0, endFrequency: 398.5, duration: 0.240, amplitude: 0.34, waveform: .bell),
            ]
        case .pebbleTap:
            [
                RecordingCueTone(frequency: 720, endFrequency: 1_080, duration: 0.042, amplitude: 0.36, waveform: .drop),
                RecordingCueTone(frequency: 1_180, duration: 0.056, amplitude: 0.28, waveform: .marimba),
            ]
        case .bambooPluck:
            [
                RecordingCueTone(frequency: 493.88, duration: 0.072, amplitude: 0.38, waveform: .marimba),
                RecordingCueTone(frequency: 739.99, duration: 0.108, amplitude: 0.34, waveform: .marimba),
            ]
        case .celestaSpark:
            [
                RecordingCueTone(frequency: 1_046.5, duration: 0.070, amplitude: 0.26, waveform: .bell),
                RecordingCueTone(frequency: 1_318.5, duration: 0.130, amplitude: 0.24, waveform: .bell),
            ]
        case .rhodesChord:
            [
                RecordingCueTone(frequency: 440.0, duration: 0.110, amplitude: 0.34, waveform: .pad),
                RecordingCueTone(frequency: 554.37, duration: 0.150, amplitude: 0.30, waveform: .pad),
            ]
        case .cloudSwell:
            [
                RecordingCueTone(frequency: 349.23, endFrequency: 523.25, duration: 0.185, amplitude: 0.32, waveform: .pad),
            ]
        case .mellowFifth:
            [
                RecordingCueTone(frequency: 392.0, duration: 0.088, amplitude: 0.34, waveform: .pad),
                RecordingCueTone(frequency: 587.33, duration: 0.135, amplitude: 0.30, waveform: .pad),
            ]
        case .musicBox:
            [
                RecordingCueTone(frequency: 1_174.66, duration: 0.068, amplitude: 0.24, waveform: .pluck),
                RecordingCueTone(frequency: 1_567.98, duration: 0.132, amplitude: 0.22, waveform: .bell),
            ]
        case .morningDew:
            [
                RecordingCueTone(frequency: 620, endFrequency: 1_120, duration: 0.068, amplitude: 0.32, waveform: .drop),
                RecordingCueTone(frequency: 1_174.66, duration: 0.115, amplitude: 0.24, waveform: .bell),
            ]
        case .softWoodblock:
            [
                RecordingCueTone(frequency: 640, endFrequency: 690, duration: 0.044, amplitude: 0.40, waveform: .marimba),
                RecordingCueTone(frequency: 860, duration: 0.056, amplitude: 0.34, waveform: .marimba),
            ]
        case .crystalBell:
            [
                RecordingCueTone(frequency: 987.77, duration: 0.080, amplitude: 0.26, waveform: .bell),
                RecordingCueTone(frequency: 1_479.98, duration: 0.155, amplitude: 0.22, waveform: .bell),
            ]
        case .lofiKey:
            [
                RecordingCueTone(frequency: 329.63, duration: 0.095, amplitude: 0.36, waveform: .pad),
                RecordingCueTone(frequency: 493.88, duration: 0.135, amplitude: 0.30, waveform: .pluck),
            ]
        case .harpGliss:
            [
                RecordingCueTone(frequency: 523.25, duration: 0.048, amplitude: 0.26, waveform: .pluck),
                RecordingCueTone(frequency: 659.25, duration: 0.048, amplitude: 0.28, waveform: .pluck),
                RecordingCueTone(frequency: 783.99, duration: 0.052, amplitude: 0.30, waveform: .pluck),
                RecordingCueTone(frequency: 1_046.50, duration: 0.115, amplitude: 0.28, waveform: .bell),
            ]
        case .celloPluck:
            [
                RecordingCueTone(frequency: 220.0, duration: 0.088, amplitude: 0.44, waveform: .pluck),
                RecordingCueTone(frequency: 329.63, duration: 0.125, amplitude: 0.38, waveform: .pluck),
            ]
        case .silkWhisper:
            [
                RecordingCueTone(frequency: 587.33, endFrequency: 783.99, duration: 0.155, amplitude: 0.28, waveform: .pad),
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
        case .warmMarimba:
            [
                RecordingCueTone(frequency: 659.25, duration: 0.085, amplitude: 0.36, waveform: .marimba),
                RecordingCueTone(frequency: 523.25, duration: 0.130, amplitude: 0.40, waveform: .marimba),
            ]
        case .softKalimba:
            [
                RecordingCueTone(frequency: 880.0, duration: 0.080, amplitude: 0.30, waveform: .pluck),
                RecordingCueTone(frequency: 587.33, duration: 0.140, amplitude: 0.34, waveform: .pluck),
            ]
        case .silkHarp:
            [
                RecordingCueTone(frequency: 659.25, duration: 0.060, amplitude: 0.30, waveform: .pluck),
                RecordingCueTone(frequency: 554.37, duration: 0.060, amplitude: 0.28, waveform: .pluck),
                RecordingCueTone(frequency: 440.0, duration: 0.125, amplitude: 0.32, waveform: .pluck),
            ]
        case .waterDrop:
            [
                RecordingCueTone(frequency: 860, endFrequency: 430, duration: 0.082, amplitude: 0.36, waveform: .drop),
            ]
        case .velvetChime:
            [
                RecordingCueTone(frequency: 987.77, duration: 0.095, amplitude: 0.24, waveform: .bell),
                RecordingCueTone(frequency: 659.25, duration: 0.155, amplitude: 0.28, waveform: .bell),
            ]
        case .zenBowl:
            [
                RecordingCueTone(frequency: 330.0, endFrequency: 328.0, duration: 0.220, amplitude: 0.32, waveform: .bell),
            ]
        case .pebbleTap:
            [
                RecordingCueTone(frequency: 1_040, duration: 0.042, amplitude: 0.28, waveform: .marimba),
                RecordingCueTone(frequency: 760, endFrequency: 520, duration: 0.056, amplitude: 0.34, waveform: .drop),
            ]
        case .bambooPluck:
            [
                RecordingCueTone(frequency: 739.99, duration: 0.068, amplitude: 0.32, waveform: .marimba),
                RecordingCueTone(frequency: 493.88, duration: 0.108, amplitude: 0.36, waveform: .marimba),
            ]
        case .celestaSpark:
            [
                RecordingCueTone(frequency: 1_318.5, duration: 0.068, amplitude: 0.22, waveform: .bell),
                RecordingCueTone(frequency: 1_046.5, duration: 0.125, amplitude: 0.26, waveform: .bell),
            ]
        case .rhodesChord:
            [
                RecordingCueTone(frequency: 554.37, duration: 0.100, amplitude: 0.28, waveform: .pad),
                RecordingCueTone(frequency: 440.0, duration: 0.145, amplitude: 0.32, waveform: .pad),
            ]
        case .cloudSwell:
            [
                RecordingCueTone(frequency: 523.25, endFrequency: 349.23, duration: 0.175, amplitude: 0.30, waveform: .pad),
            ]
        case .mellowFifth:
            [
                RecordingCueTone(frequency: 587.33, duration: 0.084, amplitude: 0.28, waveform: .pad),
                RecordingCueTone(frequency: 392.0, duration: 0.130, amplitude: 0.32, waveform: .pad),
            ]
        case .musicBox:
            [
                RecordingCueTone(frequency: 1_567.98, duration: 0.064, amplitude: 0.20, waveform: .bell),
                RecordingCueTone(frequency: 1_174.66, duration: 0.128, amplitude: 0.24, waveform: .pluck),
            ]
        case .morningDew:
            [
                RecordingCueTone(frequency: 1_174.66, duration: 0.072, amplitude: 0.24, waveform: .bell),
                RecordingCueTone(frequency: 860, endFrequency: 520, duration: 0.095, amplitude: 0.30, waveform: .drop),
            ]
        case .softWoodblock:
            [
                RecordingCueTone(frequency: 860, duration: 0.042, amplitude: 0.32, waveform: .marimba),
                RecordingCueTone(frequency: 640, endFrequency: 590, duration: 0.056, amplitude: 0.38, waveform: .marimba),
            ]
        case .crystalBell:
            [
                RecordingCueTone(frequency: 1_479.98, duration: 0.076, amplitude: 0.20, waveform: .bell),
                RecordingCueTone(frequency: 987.77, duration: 0.145, amplitude: 0.26, waveform: .bell),
            ]
        case .lofiKey:
            [
                RecordingCueTone(frequency: 493.88, duration: 0.090, amplitude: 0.28, waveform: .pluck),
                RecordingCueTone(frequency: 329.63, duration: 0.130, amplitude: 0.34, waveform: .pad),
            ]
        case .harpGliss:
            [
                RecordingCueTone(frequency: 1_046.50, duration: 0.048, amplitude: 0.24, waveform: .bell),
                RecordingCueTone(frequency: 783.99, duration: 0.048, amplitude: 0.28, waveform: .pluck),
                RecordingCueTone(frequency: 659.25, duration: 0.052, amplitude: 0.28, waveform: .pluck),
                RecordingCueTone(frequency: 523.25, duration: 0.110, amplitude: 0.30, waveform: .pluck),
            ]
        case .celloPluck:
            [
                RecordingCueTone(frequency: 329.63, duration: 0.084, amplitude: 0.36, waveform: .pluck),
                RecordingCueTone(frequency: 220.0, duration: 0.120, amplitude: 0.42, waveform: .pluck),
            ]
        case .silkWhisper:
            [
                RecordingCueTone(frequency: 783.99, endFrequency: 523.25, duration: 0.145, amplitude: 0.26, waveform: .pad),
            ]
        }
    }

    /// Soft, unmistakable cue played when dictation finishes with no detected speech
    /// or cannot be transcribed. Matched to each cue set's acoustic character.
    public var emptyTones: [RecordingCueTone] {
        switch self {
        case .warmMarimba, .bambooPluck, .softWoodblock:
            return [
                RecordingCueTone(frequency: 370.0, duration: 0.068, amplitude: 0.30, waveform: .marimba),
                RecordingCueTone(frequency: 277.18, endFrequency: 246.94, duration: 0.115, amplitude: 0.28, waveform: .marimba),
            ]
        case .softKalimba, .silkHarp, .harpGliss, .celloPluck, .musicBox:
            return [
                RecordingCueTone(frequency: 349.23, duration: 0.068, amplitude: 0.28, waveform: .pluck),
                RecordingCueTone(frequency: 261.63, endFrequency: 233.08, duration: 0.120, amplitude: 0.26, waveform: .pluck),
            ]
        case .waterDrop, .pebbleTap, .morningDew:
            return [
                RecordingCueTone(frequency: 420.0, endFrequency: 260.0, duration: 0.070, amplitude: 0.30, waveform: .drop),
                RecordingCueTone(frequency: 290.0, endFrequency: 185.0, duration: 0.095, amplitude: 0.24, waveform: .drop),
            ]
        case .velvetChime, .zenBowl, .celestaSpark, .crystalBell, .gentleChime:
            return [
                RecordingCueTone(frequency: 415.30, duration: 0.075, amplitude: 0.24, waveform: .bell),
                RecordingCueTone(frequency: 311.13, endFrequency: 293.66, duration: 0.135, amplitude: 0.22, waveform: .bell),
            ]
        case .rhodesChord, .cloudSwell, .mellowFifth, .lofiKey, .silkWhisper, .whisperTone:
            return [
                RecordingCueTone(frequency: 329.63, endFrequency: 277.18, duration: 0.085, amplitude: 0.26, waveform: .pad),
                RecordingCueTone(frequency: 246.94, endFrequency: 207.65, duration: 0.135, amplitude: 0.24, waveform: .pad),
            ]
        case .softClick, .glassTap, .minimalTick, .vuTap, .studioBeep:
            return [
                RecordingCueTone(frequency: 392.0, endFrequency: 311.13, duration: 0.058, amplitude: 0.26, waveform: .triangle),
                RecordingCueTone(frequency: 261.63, endFrequency: 207.65, duration: 0.092, amplitude: 0.24, waveform: .sine),
            ]
        case .neonBlip, .radioChirp, .cassettePunch, .digitalPing, .warmPop, .synthPulse, .airlock, .classicRecorder:
            return [
                RecordingCueTone(frequency: 340.0, endFrequency: 260.0, duration: 0.062, amplitude: 0.26, waveform: .triangle),
                RecordingCueTone(frequency: 230.0, endFrequency: 165.0, duration: 0.105, amplitude: 0.26, waveform: .sine),
            ]
        }
    }
}
