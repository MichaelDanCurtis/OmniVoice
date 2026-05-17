import Foundation

public enum AIProviderPresetID: String, Codable, CaseIterable, Equatable, Sendable {
    case openRouter = "openrouter"
    case lmStudio = "lm_studio"
    case ollama
    case custom
}

public struct AIProviderPreset: Codable, Equatable, Identifiable, Sendable {
    public let id: AIProviderPresetID
    public let name: String
    public let baseURL: String
    public let defaultModel: String
    public let requiresAPIKey: Bool

    public init(
        id: AIProviderPresetID,
        name: String,
        baseURL: String,
        defaultModel: String = "",
        requiresAPIKey: Bool = false
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.defaultModel = defaultModel
        self.requiresAPIKey = requiresAPIKey
    }

    public static let builtIn: [AIProviderPreset] = [
        AIProviderPreset(
            id: .openRouter,
            name: "OpenRouter",
            baseURL: "https://openrouter.ai/api/v1",
            requiresAPIKey: true
        ),
        AIProviderPreset(
            id: .lmStudio,
            name: "LM Studio",
            baseURL: "http://127.0.0.1:1234/v1"
        ),
        AIProviderPreset(
            id: .ollama,
            name: "Ollama",
            baseURL: "http://127.0.0.1:11434/v1"
        ),
        AIProviderPreset(
            id: .custom,
            name: "Custom",
            baseURL: ""
        ),
    ]

    public static func preset(for id: AIProviderPresetID) -> AIProviderPreset? {
        builtIn.first { $0.id == id }
    }
}

public struct PendingAIHandoffCommand: Codable, Equatable, Sendable {
    public let target: AIHandoffTarget
    public let prompt: String
    public let context: String
    public let originalText: String

    public var provider: String { target.rawValue }

    public init(
        target: AIHandoffTarget,
        prompt: String,
        context: String = "",
        originalText: String
    ) {
        self.target = target
        self.prompt = prompt
        self.context = context
        self.originalText = originalText
    }
}
