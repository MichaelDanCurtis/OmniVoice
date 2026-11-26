import Foundation

/// Deepgram speech-to-text models selectable in Service Mode (Cloud / Outbound).
public enum DeepgramModel: String, CaseIterable, Codable, Equatable, Hashable, Identifiable, Sendable {
    case nova3 = "nova-3"
    case nova3Medical = "nova-3-medical"
    case nova2 = "nova-2"
    case flux = "flux-general-en"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .nova3:
            "Nova-3"
        case .nova3Medical:
            "Nova-3 Medical"
        case .nova2:
            "Nova-2"
        case .flux:
            "Flux (Conversational)"
        }
    }

    public var badge: String {
        switch self {
        case .nova3:
            "Fastest · Highest Accuracy"
        case .nova3Medical:
            "Clinical Terms"
        case .nova2:
            "Legacy"
        case .flux:
            "Turn-Taking"
        }
    }
}

/// How Service Mode routes LLM work (dictation cleanup, translation, Voice Edit,
/// Command Mode planning, and Meeting Co-Pilot) through the user's subscriptions.
public enum ServiceModeLLMRoute: Codable, Equatable, Hashable, Sendable {
    /// Prefers a configured OAuth / API Text LLM provider, then falls back to the first
    /// installed subscription CLI agent (e.g. Claude, Codex, Gemini, Copilot).
    case auto
    /// Routes directly through an installed subscription CLI agent (`claude`, `codex`, `gemini`, etc.).
    case subscriptionAgent(agentID: String)
    /// Routes through a configured Text LLM provider (OAuth subscription like Codex/Copilot or API key).
    case configuredTextLLM(provider: TextLLMProviderKind)

    public var pickerID: String {
        switch self {
        case .auto:
            "auto"
        case .subscriptionAgent(let agentID):
            "agent:\(agentID)"
        case .configuredTextLLM(let provider):
            "llm:\(provider.rawValue)"
        }
    }

    public init(pickerID: String) {
        if pickerID.hasPrefix("agent:") {
            let id = String(pickerID.dropFirst("agent:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            self = id.isEmpty ? .auto : .subscriptionAgent(agentID: id)
        } else if pickerID.hasPrefix("llm:") {
            let raw = String(pickerID.dropFirst("llm:".count))
            self = .configuredTextLLM(provider: TextLLMProviderKind(providerID: raw))
        } else {
            self = .auto
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "subscription_agent":
            let agentID = try container.decode(String.self, forKey: .value)
            self = .subscriptionAgent(agentID: agentID)
        case "configured_text_llm":
            let raw = try container.decode(String.self, forKey: .value)
            self = .configuredTextLLM(provider: TextLLMProviderKind(providerID: raw))
        default:
            self = .auto
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .auto:
            try container.encode("auto", forKey: .kind)
        case .subscriptionAgent(let agentID):
            try container.encode("subscription_agent", forKey: .kind)
            try container.encode(agentID, forKey: .value)
        case .configuredTextLLM(let provider):
            try container.encode("configured_text_llm", forKey: .kind)
            try container.encode(provider.rawValue, forKey: .value)
        }
    }
}

/// Configuration for **Service Mode** (Cloud / Outbound): uses Deepgram for low-latency
/// cloud voice input and the user's existing AI subscriptions for LLM cleanup and actions.
public struct ServiceModeConfiguration: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var deepgramModel: DeepgramModel
    public var deepgramLanguage: String
    public var deepgramSmartFormat: Bool
    public var llmRoute: ServiceModeLLMRoute
    public var unloadLocalModelsWhenEnabled: Bool

    public static let defaults = ServiceModeConfiguration(
        enabled: false,
        deepgramModel: .nova3,
        deepgramLanguage: "multi",
        deepgramSmartFormat: true,
        llmRoute: .auto,
        unloadLocalModelsWhenEnabled: true
    )

    public static let languageOptions: [(code: String, label: String)] = [
        ("multi", "Auto (Multilingual)"),
        ("en", "English"),
        ("en-US", "English (US)"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("ja", "Japanese"),
        ("zh", "Chinese"),
        ("pt", "Portuguese"),
        ("it", "Italian"),
        ("ko", "Korean"),
    ]

    public init(
        enabled: Bool = false,
        deepgramModel: DeepgramModel = .nova3,
        deepgramLanguage: String = "multi",
        deepgramSmartFormat: Bool = true,
        llmRoute: ServiceModeLLMRoute = .auto,
        unloadLocalModelsWhenEnabled: Bool = true
    ) {
        self.enabled = enabled
        self.deepgramModel = deepgramModel
        let cleanLang = deepgramLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        self.deepgramLanguage = cleanLang.isEmpty ? "multi" : cleanLang
        self.deepgramSmartFormat = deepgramSmartFormat
        self.llmRoute = llmRoute
        self.unloadLocalModelsWhenEnabled = unloadLocalModelsWhenEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case deepgramModel
        case deepgramLanguage
        case deepgramSmartFormat
        case llmRoute
        case unloadLocalModelsWhenEnabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
            deepgramModel: try c.decodeIfPresent(DeepgramModel.self, forKey: .deepgramModel) ?? .nova3,
            deepgramLanguage: try c.decodeIfPresent(String.self, forKey: .deepgramLanguage) ?? "multi",
            deepgramSmartFormat: try c.decodeIfPresent(Bool.self, forKey: .deepgramSmartFormat) ?? true,
            llmRoute: try c.decodeIfPresent(ServiceModeLLMRoute.self, forKey: .llmRoute) ?? .auto,
            unloadLocalModelsWhenEnabled: try c.decodeIfPresent(Bool.self, forKey: .unloadLocalModelsWhenEnabled) ?? true
        )
    }
}

/// Pure URL construction and JSON parsing for Deepgram REST & WebSocket APIs.
public enum DeepgramAPIHelper {
    public struct StreamEvent: Equatable, Sendable {
        public let transcript: String
        public let isFinal: Bool
        public let speechFinal: Bool

        public init(transcript: String, isFinal: Bool, speechFinal: Bool) {
            self.transcript = transcript
            self.isFinal = isFinal
            self.speechFinal = speechFinal
        }
    }

    public static func restListenURL(config: ServiceModeConfiguration) -> URL? {
        var components = URLComponents(string: "https://api.deepgram.com/v1/listen")
        var items: [URLQueryItem] = [
            URLQueryItem(name: "model", value: config.deepgramModel.rawValue),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "smart_format", value: config.deepgramSmartFormat ? "true" : "false"),
        ]
        if config.deepgramModel != .flux {
            items.append(URLQueryItem(name: "language", value: config.deepgramLanguage))
        }
        components?.queryItems = items
        return components?.url
    }

    public static func streamingListenURL(
        config: ServiceModeConfiguration,
        sampleRate: Int
    ) -> URL? {
        var components = URLComponents(string: "wss://api.deepgram.com/v1/listen")
        let clampedRate = max(8_000, sampleRate)
        var items: [URLQueryItem] = [
            URLQueryItem(name: "model", value: config.deepgramModel.rawValue),
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: String(clampedRate)),
            URLQueryItem(name: "channels", value: "1"),
            URLQueryItem(name: "interim_results", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "smart_format", value: config.deepgramSmartFormat ? "true" : "false"),
        ]
        if config.deepgramModel != .flux {
            items.append(URLQueryItem(name: "language", value: config.deepgramLanguage))
        }
        components?.queryItems = items
        return components?.url
    }

    public static func parseRESTTranscript(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [String: Any],
              let channels = results["channels"] as? [[String: Any]],
              let firstChannel = channels.first,
              let alternatives = firstChannel["alternatives"] as? [[String: Any]],
              let firstAlt = alternatives.first,
              let transcript = firstAlt["transcript"] as? String else {
            return nil
        }
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func parseStreamEvent(from text: String) -> StreamEvent? {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = root["type"] as? String,
              type == "Results",
              let channel = root["channel"] as? [String: Any],
              let alternatives = channel["alternatives"] as? [[String: Any]],
              let firstAlt = alternatives.first,
              let transcript = firstAlt["transcript"] as? String else {
            return nil
        }
        let isFinal = (root["is_final"] as? Bool) ?? false
        let speechFinal = (root["speech_final"] as? Bool) ?? false
        return StreamEvent(
            transcript: transcript.trimmingCharacters(in: .whitespacesAndNewlines),
            isFinal: isFinal,
            speechFinal: speechFinal
        )
    }
}
