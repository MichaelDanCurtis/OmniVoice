import Foundation

public enum ConversationCaptureMode: String, Codable, CaseIterable, Equatable, Sendable {
    case microphoneOnly = "microphone_only"
    case systemAudioOnly = "system_audio_only"
    case microphoneAndSystemAudio = "microphone_and_system_audio"
    case mixedFallback = "mixed_fallback"

    public var displayName: String {
        switch self {
        case .microphoneOnly: "Microphone"
        case .systemAudioOnly: "System Audio"
        case .microphoneAndSystemAudio: "Mic + System"
        case .mixedFallback: "Mixed"
        }
    }
}

public enum ConversationSegmentState: String, Codable, Equatable, Sendable {
    case live
    case settled
    case correctedSpeaker = "corrected_speaker"
}

public enum ConversationSpeakerOrigin: String, Codable, Equatable, Sendable {
    case generic
    case inferred
    case userConfirmed = "user_confirmed"
}

public enum ConversationAssistCardKind: String, Codable, Equatable, Sendable {
    case question
    case answer
    case timeZone = "time_zone"
    case followUp = "follow_up"
    case actionItem = "action_item"
    case warning
}

public enum ConversationAssistCardStatus: String, Codable, Equatable, Sendable {
    case active
    case copied
    case spoken
    case pinned
    case dismissed
}

public enum ConversationAudioSourceKind: String, Codable, Equatable, Sendable {
    case microphone
    case systemAudio = "system_audio"
    case appAudio = "app_audio"
    case mixed
}

public struct ConversationSession: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let startedAt: String
    public let endedAt: String?
    public let captureMode: ConversationCaptureMode
    public let asrProvider: String
    public let diarizationProvider: String
    public let externalProcessingEnabled: Bool
    public let sourceIds: [String]

    public var isActive: Bool { endedAt == nil }
    public var sourceIDs: [String] { sourceIds }

    public init(
        id: String,
        title: String,
        startedAt: String,
        endedAt: String? = nil,
        captureMode: ConversationCaptureMode,
        asrProvider: String,
        diarizationProvider: String,
        externalProcessingEnabled: Bool,
        sourceIDs: [String] = []
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.captureMode = captureMode
        self.asrProvider = asrProvider
        self.diarizationProvider = diarizationProvider
        self.externalProcessingEnabled = externalProcessingEnabled
        self.sourceIds = sourceIDs
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case startedAt
        case endedAt
        case captureMode
        case asrProvider
        case diarizationProvider
        case externalProcessingEnabled
        case sourceIds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.startedAt = try container.decode(String.self, forKey: .startedAt)
        self.endedAt = try container.decodeIfPresent(String.self, forKey: .endedAt)
        self.captureMode = try container.decode(ConversationCaptureMode.self, forKey: .captureMode)
        self.asrProvider = try container.decode(String.self, forKey: .asrProvider)
        self.diarizationProvider = try container.decode(String.self, forKey: .diarizationProvider)
        self.externalProcessingEnabled = try container.decode(Bool.self, forKey: .externalProcessingEnabled)
        self.sourceIds = try container.decodeIfPresent([String].self, forKey: .sourceIds) ?? []
    }
}

public struct ConversationAudioSource: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let sessionId: String
    public let kind: ConversationAudioSourceKind
    public let displayName: String
    public let isSeparatedTrack: Bool

    public var sessionID: String { sessionId }

    public init(
        id: String,
        sessionID: String,
        kind: ConversationAudioSourceKind,
        displayName: String,
        isSeparatedTrack: Bool
    ) {
        self.id = id
        self.sessionId = sessionID
        self.kind = kind
        self.displayName = displayName
        self.isSeparatedTrack = isSeparatedTrack
    }
}

public struct ConversationSpeakerIdentity: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var displayName: String
    public var origin: ConversationSpeakerOrigin
    public let colorHex: String

    public init(id: String, displayName: String, origin: ConversationSpeakerOrigin, colorHex: String) {
        self.id = id
        self.displayName = displayName
        self.origin = origin
        self.colorHex = colorHex
    }
}

public struct ConversationSegment: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let sessionId: String
    public let speakerId: String
    public let speakerDisplayName: String
    public let startMs: Int
    public let endMs: Int?
    public let text: String
    public let state: ConversationSegmentState
    public let confidence: Double?
    public let speakerTurns: [SpeakerTurn]
    public let speakerLines: [ConversationSpeakerLine]

    public var sessionID: String { sessionId }
    public var speakerID: String { speakerId }

    public var timestampLabel: String {
        let totalSeconds = max(0, startMs / 1000)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    public init(
        id: String,
        sessionID: String,
        speakerID: String,
        speakerDisplayName: String,
        startMs: Int,
        endMs: Int? = nil,
        text: String,
        state: ConversationSegmentState,
        confidence: Double? = nil,
        speakerTurns: [SpeakerTurn] = [],
        speakerLines: [ConversationSpeakerLine] = []
    ) {
        self.id = id
        self.sessionId = sessionID
        self.speakerId = speakerID
        self.speakerDisplayName = speakerDisplayName
        self.startMs = startMs
        self.endMs = endMs
        self.text = text
        self.state = state
        self.confidence = confidence
        self.speakerTurns = speakerTurns
        self.speakerLines = speakerLines
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sessionId
        case speakerId
        case speakerDisplayName
        case startMs
        case endMs
        case text
        case state
        case confidence
        case speakerTurns
        case speakerLines
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.sessionId = try container.decode(String.self, forKey: .sessionId)
        self.speakerId = try container.decode(String.self, forKey: .speakerId)
        self.speakerDisplayName = try container.decode(String.self, forKey: .speakerDisplayName)
        self.startMs = try container.decode(Int.self, forKey: .startMs)
        self.endMs = try container.decodeIfPresent(Int.self, forKey: .endMs)
        self.text = try container.decode(String.self, forKey: .text)
        self.state = try container.decode(ConversationSegmentState.self, forKey: .state)
        self.confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        self.speakerTurns = try container.decodeIfPresent([SpeakerTurn].self, forKey: .speakerTurns) ?? []
        self.speakerLines = try container.decodeIfPresent([ConversationSpeakerLine].self, forKey: .speakerLines) ?? []
    }
}

public struct ConversationAssistCard: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let sessionId: String
    public let kind: ConversationAssistCardKind
    public let title: String
    public let body: String
    public let sourceReferences: [String]
    public let confidence: Double?
    public var status: ConversationAssistCardStatus
    public let createdAt: String

    public var sessionID: String { sessionId }
    public var copyText: String { body.trimmingCharacters(in: .whitespacesAndNewlines) }

    public init(
        id: String,
        sessionID: String,
        kind: ConversationAssistCardKind,
        title: String,
        body: String,
        sourceReferences: [String] = [],
        confidence: Double? = nil,
        status: ConversationAssistCardStatus = .active,
        createdAt: String
    ) {
        self.id = id
        self.sessionId = sessionID
        self.kind = kind
        self.title = title
        self.body = body
        self.sourceReferences = sourceReferences
        self.confidence = confidence
        self.status = status
        self.createdAt = createdAt
    }
}

public struct ConversationSessionCreateRequest: Codable, Equatable, Sendable {
    public let title: String
    public let captureMode: ConversationCaptureMode
    public let asrProvider: String
    public let diarizationProvider: String
    public let externalProcessingEnabled: Bool

    public init(
        title: String,
        captureMode: ConversationCaptureMode,
        asrProvider: String,
        diarizationProvider: String,
        externalProcessingEnabled: Bool = false
    ) {
        self.title = title
        self.captureMode = captureMode
        self.asrProvider = asrProvider
        self.diarizationProvider = diarizationProvider
        self.externalProcessingEnabled = externalProcessingEnabled
    }
}

public struct ConversationSegmentCreateRequest: Codable, Equatable, Sendable {
    public let speakerId: String?
    public let speakerDisplayName: String?
    public let audioStartMs: Int?
    public let startMs: Int
    public let endMs: Int?
    public let text: String
    public let state: ConversationSegmentState
    public let confidence: Double?
    public let audioPcmFloat32Base64: String?
    public let audioSampleRate: Int?

    public var speakerID: String? { speakerId }
    public var audioPCMFloat32Base64: String? { audioPcmFloat32Base64 }

    public init(
        speakerID: String? = nil,
        speakerDisplayName: String? = nil,
        audioStartMs: Int? = nil,
        startMs: Int,
        endMs: Int? = nil,
        text: String,
        state: ConversationSegmentState,
        confidence: Double? = nil,
        audioPCMFloat32: Data? = nil,
        audioSampleRate: Int? = nil
    ) {
        self.speakerId = speakerID
        self.speakerDisplayName = speakerDisplayName
        self.audioStartMs = audioPCMFloat32 == nil ? nil : audioStartMs ?? startMs
        self.startMs = startMs
        self.endMs = endMs
        self.text = text
        self.state = state
        self.confidence = confidence
        self.audioPcmFloat32Base64 = audioPCMFloat32?.base64EncodedString()
        self.audioSampleRate = audioPCMFloat32 == nil ? nil : audioSampleRate
    }
}

public struct ConversationAssistCardCreateRequest: Codable, Equatable, Sendable {
    public let kind: ConversationAssistCardKind
    public let title: String
    public let body: String
    public let sourceReferences: [String]
    public let confidence: Double?

    public init(
        kind: ConversationAssistCardKind,
        title: String,
        body: String,
        sourceReferences: [String] = [],
        confidence: Double? = nil
    ) {
        self.kind = kind
        self.title = title
        self.body = body
        self.sourceReferences = sourceReferences
        self.confidence = confidence
    }
}

public struct ConversationSegmentUpdateRequest: Codable, Equatable, Sendable {
    public let id: String
    public let text: String

    public init(id: String, text: String) {
        self.id = id
        self.text = text
    }
}

public struct ConversationDetailUpdateRequest: Codable, Equatable, Sendable {
    public let title: String?
    public let speakerNames: [String: String]
    public let segments: [ConversationSegmentUpdateRequest]

    public init(
        title: String? = nil,
        speakerNames: [String: String] = [:],
        segments: [ConversationSegmentUpdateRequest] = []
    ) {
        self.title = title
        self.speakerNames = speakerNames
        self.segments = segments
    }
}

public struct ConversationDetail: Codable, Equatable, Sendable {
    public let session: ConversationSession
    public let segments: [ConversationSegment]
    public let assistCards: [ConversationAssistCard]

    public init(
        session: ConversationSession,
        segments: [ConversationSegment] = [],
        assistCards: [ConversationAssistCard] = []
    ) {
        self.session = session
        self.segments = segments
        self.assistCards = assistCards
    }
}

public struct ConversationImportResult: Codable, Equatable, Sendable {
    public let status: String
    public let sessionId: String
    public let segments: Int
    public let assistCards: Int

    public var sessionID: String { sessionId }

    public init(status: String, sessionID: String, segments: Int, assistCards: Int) {
        self.status = status
        self.sessionId = sessionID
        self.segments = segments
        self.assistCards = assistCards
    }
}

public struct SpeakerTurn: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let sessionId: String
    public let speakerId: String
    public let startMs: Int
    public let endMs: Int?
    public let confidence: Double?
    public let overlap: Bool
    public let sourceProvider: String

    public var sessionID: String { sessionId }
    public var speakerID: String { speakerId }

    public init(
        id: String,
        sessionID: String,
        speakerID: String,
        startMs: Int,
        endMs: Int? = nil,
        confidence: Double? = nil,
        overlap: Bool,
        sourceProvider: String
    ) {
        self.id = id
        self.sessionId = sessionID
        self.speakerId = speakerID
        self.startMs = startMs
        self.endMs = endMs
        self.confidence = confidence
        self.overlap = overlap
        self.sourceProvider = sourceProvider
    }
}

public struct ConversationSpeakerLine: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let sessionId: String
    public let speakerId: String
    public let startMs: Int
    public let endMs: Int?
    public let text: String
    public let confidence: Double?
    public let sourceProvider: String

    public var sessionID: String { sessionId }
    public var speakerID: String { speakerId }

    public init(
        id: String,
        sessionID: String,
        speakerID: String,
        startMs: Int,
        endMs: Int? = nil,
        text: String,
        confidence: Double? = nil,
        sourceProvider: String
    ) {
        self.id = id
        self.sessionId = sessionID
        self.speakerId = speakerID
        self.startMs = startMs
        self.endMs = endMs
        self.text = text
        self.confidence = confidence
        self.sourceProvider = sourceProvider
    }
}
