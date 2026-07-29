import Foundation

public enum StyleProfile: String, CaseIterable, Codable, Equatable, Sendable {
    case neutral = "neutral"
    case professional = "professional"
    case concise = "concise"
    case expanded = "expanded"
    case raw = "raw"

    public var displayName: String {
        switch self {
        case .neutral:
            "Neutral"
        case .professional:
            "Professional"
        case .concise:
            "Concise"
        case .expanded:
            "Expanded"
        case .raw:
            "Raw Dictation"
        }
    }

    public func next() -> StyleProfile {
        let values = Self.allCases
        let index = values.firstIndex(of: self) ?? 0
        return values[(index + 1) % values.count]
    }
}

public enum ASRProviderKind: String, CaseIterable, Codable, Equatable, Sendable {
    case fake = "fake"
    case parakeetTDT = "parakeet-tdt"
    case parakeetTDTMLX = "parakeet-tdt-mlx"
    case whisperLargeV3TurboMLX6Bit = "whisper-large-v3-turbo-mlx-6bit"
    case canaryQwen25B = "canary-qwen-2.5b"
    /// Apple's built-in on-device SpeechAnalyzer/SpeechTranscriber (macOS 26+).
    /// Native Swift — transcription bypasses the Python engine entirely; the OS
    /// downloads and manages the model, so dictation works even with the engine
    /// offline (cleanup then degrades to light punctuation).
    case appleSpeech = "apple-speech"

    public static let userSelectableCases: [ASRProviderKind] = [
        .parakeetTDTMLX,
        .whisperLargeV3TurboMLX6Bit,
        .canaryQwen25B,
        .appleSpeech,
    ]

    /// Whether transcription for this provider is served by the local Python
    /// engine. `appleSpeech` runs natively in the app, so the engine must never
    /// be asked for it — neither for transcription nor in provider-sync checks.
    public var isEngineBacked: Bool {
        self != .appleSpeech
    }

    public var normalizedForUserSelection: ASRProviderKind {
        Self.userSelectableCases.contains(self) ? self : .parakeetTDTMLX
    }

    public var displayName: String {
        switch self {
        case .fake:
            "Fake ASR"
        case .parakeetTDT:
            "Parakeet TDT"
        case .parakeetTDTMLX:
            "Parakeet TDT MLX"
        case .whisperLargeV3TurboMLX6Bit:
            "Whisper Large v3 Turbo MLX 6-bit"
        case .canaryQwen25B:
            "Canary-Qwen-2.5B"
        case .appleSpeech:
            "Apple Speech (Built-in)"
        }
    }
}

public enum SpeechModelRecommendation: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case parakeetTDTMLX = "parakeet-tdt-mlx"
    case whisperLargeV3TurboMLX6Bit = "whisper-large-v3-turbo-mlx-6bit"
    case canaryQwen25B = "canary-qwen-2.5b"

    public static let defaultProviderID = Self.parakeetTDTMLX.providerID

    public init(providerID: String) {
        self = Self(rawValue: providerID) ?? .parakeetTDTMLX
    }

    public var id: String { rawValue }
    public var providerID: String { rawValue }

    public var providerKind: ASRProviderKind {
        ASRProviderKind(rawValue: providerID) ?? .parakeetTDTMLX
    }

    public var displayName: String {
        providerKind.displayName
    }

    public var badge: String {
        switch self {
        case .parakeetTDTMLX:
            "Fast / Default"
        case .whisperLargeV3TurboMLX6Bit:
            "Multilingual"
        case .canaryQwen25B:
            "English Accuracy"
        }
    }

    public var detail: String {
        switch self {
        case .parakeetTDTMLX:
            "Best daily driver for low-latency English dictation on Apple Silicon."
        case .whisperLargeV3TurboMLX6Bit:
            "Local MLX Whisper path for multilingual speech input and Chinese/Japanese/Korean captions."
        case .canaryQwen25B:
            "NVIDIA NeMo-backed English ASR accuracy mode. Heavier than the MLX models and requires the Canary runtime."
        }
    }
}

public enum EngineProviderContract {
    public static let requiredASRProviderIDs: [String] =
        ASRProviderKind.userSelectableCases.filter(\.isEngineBacked).map(\.rawValue)

    public static func missingRequiredASRProviderIDs(in providers: [EngineProviderInfo]) -> [String] {
        let availableIDs = Set(providers.map(\.id))
        return requiredASRProviderIDs.filter { !availableIDs.contains($0) }
    }
}

public enum TranslationProviderKind: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case fake = "fake"
    case translateGemmaMLX = "translategemma-mlx"
    case nllbDistilled600M = "nllb-200-distilled-600m"

    public init(providerID: String) {
        self = Self(rawValue: providerID) ?? .fake
    }

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fake:
            "Fake Local Translator"
        case .translateGemmaMLX:
            "TranslateGemma MLX"
        case .nllbDistilled600M:
            "NLLB-200 Distilled 600M"
        }
    }

    public var detail: String {
        switch self {
        case .fake:
            "Deterministic local test backend"
        case .translateGemmaMLX:
            "Primary Apple Silicon local translation backend"
        case .nllbDistilled600M:
            "Fallback many-to-many translation backend"
        }
    }

    public var modelProviderID: String? {
        switch self {
        case .fake, .nllbDistilled600M:
            nil
        case .translateGemmaMLX:
            rawValue
        }
    }
}

public enum TranslationModelRecommendation: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case translateGemma4B4Bit = "translategemma-mlx"
    case translateGemma4B8Bit = "translategemma-mlx-4b-8bit"
    case translateGemma12B4Bit = "translategemma-mlx-12b-4bit"
    case sarvamTranslate4Bit = "sarvam-translate-mlx-4bit"
    case plamo2Translate = "plamo-2-translate-mlx"

    public static let defaultProviderID = Self.translateGemma4B4Bit.providerID

    public init(providerID: String) {
        self = Self(rawValue: providerID) ?? .translateGemma4B4Bit
    }

    public var id: String { rawValue }
    public var providerID: String { rawValue }

    public var displayName: String {
        switch self {
        case .translateGemma4B4Bit:
            "TranslateGemma 4B 4-bit"
        case .translateGemma4B8Bit:
            "TranslateGemma 4B 8-bit"
        case .translateGemma12B4Bit:
            "TranslateGemma 12B 4-bit"
        case .sarvamTranslate4Bit:
            "Sarvam Translate 4-bit"
        case .plamo2Translate:
            "PLaMo 2 Translate"
        }
    }

    public var badge: String {
        switch self {
        case .translateGemma4B4Bit:
            "Fast / Recommended"
        case .translateGemma4B8Bit:
            "Balanced Quality"
        case .translateGemma12B4Bit:
            "Quality / High-End Mac"
        case .sarvamTranslate4Bit:
            "Indic Languages"
        case .plamo2Translate:
            "Japanese / English Specialist"
        }
    }

    public var agreementURL: String? {
        switch self {
        case .translateGemma4B4Bit:
            "https://huggingface.co/google/translategemma-4b-it"
        case .translateGemma4B8Bit:
            "https://huggingface.co/google/translategemma-4b-it"
        case .translateGemma12B4Bit:
            "https://huggingface.co/google/translategemma-12b-it"
        case .sarvamTranslate4Bit:
            "https://huggingface.co/mlx-community/sarvam-translate-mlx-4bit"
        case .plamo2Translate:
            "https://huggingface.co/mlx-community/plamo-2-translate"
        }
    }
}

public enum DiarizationPrecision: String, CaseIterable, Codable, Equatable, Sendable {
    case fp16
    case fp32

    public init(providerID: String) {
        self = providerID == Self.fp32.providerID ? .fp32 : .fp16
    }

    public var providerID: String {
        switch self {
        case .fp16:
            "mlx-sortformer-streaming-fp16"
        case .fp32:
            "mlx-sortformer-streaming-fp32"
        }
    }

    public var displayName: String {
        switch self {
        case .fp16:
            "FP16"
        case .fp32:
            "FP32"
        }
    }

    public var detail: String {
        switch self {
        case .fp16:
            "Faster, lower memory"
        case .fp32:
            "Higher precision, more memory"
        }
    }
}

public enum TextLLMTransport: String, CaseIterable, Codable, Equatable, Sendable {
    case openAICompatible = "openai_compatible"
    case anthropic = "anthropic"
    case openAICodexOAuth = "openai_codex_oauth"
    case githubCopilotOAuth = "github_copilot_oauth"

    public var displayName: String {
        switch self {
        case .openAICompatible:
            "OpenAI-Compatible"
        case .anthropic:
            "Anthropic"
        case .openAICodexOAuth:
            "OpenAI Codex OAuth"
        case .githubCopilotOAuth:
            "GitHub Copilot OAuth"
        }
    }
}

public enum TextLLMAuthMode: String, CaseIterable, Codable, Equatable, Sendable {
    case apiKey = "api_key"
    case oauth

    public var displayName: String {
        switch self {
        case .apiKey:
            "API Key"
        case .oauth:
            "OAuth"
        }
    }
}

public enum TextLLMProviderKind: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case claude
    case codex = "openai_codex"
    case githubCopilot = "github_copilot"
    case openRouter = "openrouter"
    case openAI = "openai"
    case custom

    public init(providerID: String) {
        self = providerID == "codex" ? .codex : (Self(rawValue: providerID) ?? .custom)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(providerID: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public init(target: AIHandoffTarget) {
        switch target {
        case .claude:
            self = .claude
        case .codex:
            self = .codex
        case .githubCopilot:
            self = .githubCopilot
        case .openRouter:
            self = .openRouter
        case .openAI:
            self = .openAI
        case .custom:
            self = .custom
        }
    }

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude:
            "Claude"
        case .codex:
            "OpenAI Codex"
        case .githubCopilot:
            "GitHub Copilot"
        case .openRouter:
            "OpenRouter"
        case .openAI:
            "OpenAI"
        case .custom:
            "Custom"
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .claude:
            "https://api.anthropic.com/v1"
        case .codex:
            "https://chatgpt.com/backend-api"
        case .openAI:
            "https://api.openai.com/v1"
        case .githubCopilot:
            ""
        case .openRouter:
            "https://openrouter.ai/api/v1"
        case .custom:
            ""
        }
    }

    public var defaultTransport: TextLLMTransport {
        switch self {
        case .claude:
            .anthropic
        case .codex:
            .openAICodexOAuth
        case .githubCopilot:
            .githubCopilotOAuth
        case .openRouter, .openAI, .custom:
            .openAICompatible
        }
    }

    public var defaultAuthMode: TextLLMAuthMode {
        switch self {
        case .codex, .githubCopilot:
            .oauth
        case .claude, .openRouter, .openAI, .custom:
            .apiKey
        }
    }

    public var defaultOAuthClientID: String {
        switch self {
        case .githubCopilot:
            "Iv1.b507a08c87ecfe98"
        case .claude, .codex, .openRouter, .openAI, .custom:
            ""
        }
    }

    public var defaultModel: String {
        ""
    }

    public var authDisplayName: String {
        switch self {
        case .codex:
            "OpenAI Codex user auth"
        case .githubCopilot:
            "GitHub device auth"
        case .claude, .openRouter, .openAI, .custom:
            "API key"
        }
    }

    public var requiresOAuth: Bool {
        switch self {
        case .codex, .githubCopilot:
            true
        case .claude, .openRouter, .openAI, .custom:
            false
        }
    }

    public var systemImage: String {
        switch self {
        case .claude:
            "sparkles"
        case .codex:
            "chevron.left.forwardslash.chevron.right"
        case .githubCopilot:
            "person.crop.circle.badge.checkmark"
        case .openRouter:
            "point.3.connected.trianglepath.dotted"
        case .openAI:
            "brain"
        case .custom:
            "slider.horizontal.3"
        }
    }

    public var voiceExample: String {
        switch self {
        case .claude:
            "Ask Claude, write a quick reply to Jane."
        case .codex:
            "Hey Codex, summarize this in two sentences."
        case .githubCopilot:
            "Ask GitHub Copilot, write a terminal command for this."
        case .openRouter:
            "Have OpenRouter take a look at this."
        case .openAI:
            "Ask OpenAI, make this sound more professional."
        case .custom:
            "Ask AI, respond in Spanish."
        }
    }
}

public struct TextLLMHeader: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var value: String
    public var enabled: Bool

    public init(id: UUID = UUID(), name: String = "", value: String = "", enabled: Bool = true) {
        self.id = id
        self.name = name
        self.value = value
        self.enabled = enabled
    }

    public var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var trimmedValue: String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var resolved: (String, String)? {
        guard enabled, !trimmedName.isEmpty else {
            return nil
        }
        return (trimmedName, trimmedValue)
    }

    public func normalized() -> TextLLMHeader {
        TextLLMHeader(id: id, name: trimmedName, value: trimmedValue, enabled: enabled)
    }
}

public struct TextLLMProviderConfiguration: Codable, Equatable, Identifiable, Sendable {
    public var provider: TextLLMProviderKind
    public var enabled: Bool
    public var manuallyAdded: Bool
    public var customName: String
    public var baseURL: String
    public var model: String
    public var apiKey: String
    public var transport: TextLLMTransport
    public var authMode: TextLLMAuthMode
    public var oauthClientID: String
    public var oauthAccessToken: String
    public var oauthRefreshToken: String
    public var headers: [TextLLMHeader]

    public var id: TextLLMProviderKind { provider }

    public init(
        provider: TextLLMProviderKind,
        enabled: Bool = true,
        manuallyAdded: Bool = false,
        customName: String = "",
        baseURL: String? = nil,
        model: String = "",
        apiKey: String = "",
        transport: TextLLMTransport? = nil,
        authMode: TextLLMAuthMode? = nil,
        oauthClientID: String = "",
        oauthAccessToken: String = "",
        oauthRefreshToken: String = "",
        headers: [TextLLMHeader] = []
    ) {
        self.provider = provider
        self.enabled = enabled
        self.manuallyAdded = manuallyAdded
        self.customName = customName
        self.baseURL = baseURL ?? provider.defaultBaseURL
        self.model = model.isEmpty ? provider.defaultModel : model
        self.apiKey = apiKey
        self.transport = transport ?? provider.defaultTransport
        self.authMode = authMode ?? provider.defaultAuthMode
        self.oauthClientID = oauthClientID
        self.oauthAccessToken = oauthAccessToken
        self.oauthRefreshToken = oauthRefreshToken
        self.headers = headers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let provider = try container.decode(TextLLMProviderKind.self, forKey: .provider)
        self.init(
            provider: provider,
            enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
            manuallyAdded: try container.decodeIfPresent(Bool.self, forKey: .manuallyAdded) ?? false,
            customName: try container.decodeIfPresent(String.self, forKey: .customName) ?? "",
            baseURL: try container.decodeIfPresent(String.self, forKey: .baseURL),
            model: try container.decodeIfPresent(String.self, forKey: .model) ?? "",
            apiKey: try container.decodeIfPresent(String.self, forKey: .apiKey) ?? "",
            transport: try container.decodeIfPresent(TextLLMTransport.self, forKey: .transport),
            authMode: try container.decodeIfPresent(TextLLMAuthMode.self, forKey: .authMode),
            oauthClientID: try container.decodeIfPresent(String.self, forKey: .oauthClientID) ?? "",
            oauthAccessToken: try container.decodeIfPresent(String.self, forKey: .oauthAccessToken) ?? "",
            oauthRefreshToken: try container.decodeIfPresent(String.self, forKey: .oauthRefreshToken) ?? "",
            headers: try container.decodeIfPresent([TextLLMHeader].self, forKey: .headers) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(provider, forKey: .provider)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(manuallyAdded, forKey: .manuallyAdded)
        try container.encode(customName, forKey: .customName)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(model, forKey: .model)
        try container.encode(apiKey, forKey: .apiKey)
        try container.encode(transport, forKey: .transport)
        try container.encode(authMode, forKey: .authMode)
        try container.encode(oauthClientID, forKey: .oauthClientID)
        try container.encode(oauthAccessToken, forKey: .oauthAccessToken)
        try container.encode(oauthRefreshToken, forKey: .oauthRefreshToken)
        try container.encode(headers, forKey: .headers)
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case enabled
        case manuallyAdded = "manually_added"
        case customName = "custom_name"
        case baseURL = "base_url"
        case model
        case apiKey = "api_key"
        case transport
        case authMode = "auth_mode"
        case oauthClientID = "oauth_client_id"
        case oauthAccessToken = "oauth_access_token"
        case oauthRefreshToken = "oauth_refresh_token"
        case headers
    }

    public static let defaults = TextLLMProviderKind.allCases.map {
        TextLLMProviderConfiguration(provider: $0, enabled: false)
    }

    public var resolvedBaseURL: String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? provider.defaultBaseURL : trimmed
    }

    public var trimmedModel: String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var displayName: String {
        let trimmed = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider == .custom, !trimmed.isEmpty {
            return trimmed
        }
        return provider.displayName
    }

    public var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var trimmedOAuthAccessToken: String {
        oauthAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var trimmedOAuthRefreshToken: String {
        oauthRefreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var trimmedOAuthClientID: String {
        oauthClientID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var resolvedOAuthClientID: String {
        let trimmed = trimmedOAuthClientID
        return trimmed.isEmpty ? provider.defaultOAuthClientID : trimmed
    }

    public var resolvedHeaders: [String: String] {
        var resolved: [String: String] = [:]
        for header in headers {
            if let (name, value) = header.resolved {
                resolved[name] = value
            }
        }
        return resolved
    }

    public var runtimeUnavailableReason: String? {
        nil
    }

    public var hasUserSuppliedConfiguration: Bool {
        let trimmedCustomName = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultBaseURL = provider.defaultBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return manuallyAdded
            || !trimmedCustomName.isEmpty
            || !trimmedModel.isEmpty
            || !trimmedAPIKey.isEmpty
            || !trimmedOAuthAccessToken.isEmpty
            || !trimmedOAuthRefreshToken.isEmpty
            || !trimmedOAuthClientID.isEmpty
            || headers.contains { $0.resolved != nil }
            || (provider == .custom && !trimmedBaseURL.isEmpty)
            || (provider != .custom && !trimmedBaseURL.isEmpty && trimmedBaseURL != defaultBaseURL)
    }

    public var isVisibleInSettings: Bool {
        enabled && hasUserSuppliedConfiguration
    }

    public var isConfigured: Bool {
        guard enabled, runtimeUnavailableReason == nil, !trimmedModel.isEmpty else {
            return false
        }

        switch authMode {
        case .apiKey:
            return !resolvedBaseURL.isEmpty
        case .oauth:
            return !trimmedOAuthAccessToken.isEmpty
        }
    }

    public func normalized() -> TextLLMProviderConfiguration {
        TextLLMProviderConfiguration(
            provider: provider,
            enabled: enabled,
            manuallyAdded: manuallyAdded,
            customName: customName.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: resolvedBaseURL,
            model: trimmedModel,
            apiKey: trimmedAPIKey,
            transport: provider.defaultTransport,
            authMode: provider.defaultAuthMode,
            oauthClientID: trimmedOAuthClientID,
            oauthAccessToken: trimmedOAuthAccessToken,
            oauthRefreshToken: trimmedOAuthRefreshToken,
            headers: headers.map { $0.normalized() }
        )
    }
}

public struct TextLLMModelListRequest: Codable, Equatable, Sendable {
    public let provider: String
    public let baseURL: String
    public let apiKey: String
    public let transport: TextLLMTransport
    public let oauthAccessToken: String
    public let headers: [String: String]

    public init(
        provider: String,
        baseURL: String,
        apiKey: String = "",
        transport: TextLLMTransport = .openAICompatible,
        oauthAccessToken: String = "",
        headers: [String: String] = [:]
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.transport = transport
        self.oauthAccessToken = oauthAccessToken
        self.headers = headers
    }
}

public struct TextLLMModelListResponse: Codable, Equatable, Sendable {
    public let provider: String
    public let models: [String]

    public init(provider: String, models: [String]) {
        self.provider = provider
        self.models = models
    }
}

public struct GitHubDeviceCodeResponse: Codable, Equatable, Sendable {
    public let deviceCode: String
    public let userCode: String
    public let verificationUri: String
    public let verificationUriComplete: String?
    public let expiresIn: Int
    public let interval: Int?

    public init(
        deviceCode: String,
        userCode: String,
        verificationUri: String,
        verificationUriComplete: String? = nil,
        expiresIn: Int,
        interval: Int? = nil
    ) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationUri = verificationUri
        self.verificationUriComplete = verificationUriComplete
        self.expiresIn = expiresIn
        self.interval = interval
    }
}

public struct GitHubDeviceTokenResponse: Codable, Equatable, Sendable {
    public let accessToken: String?
    public let refreshToken: String?
    public let tokenType: String?
    public let scope: String?
    public let error: String?
    public let errorDescription: String?
    public let interval: Int?

    public init(
        accessToken: String? = nil,
        refreshToken: String? = nil,
        tokenType: String? = nil,
        scope: String? = nil,
        error: String? = nil,
        errorDescription: String? = nil,
        interval: Int? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.scope = scope
        self.error = error
        self.errorDescription = errorDescription
        self.interval = interval
    }
}

public struct CodexCLITokens: Codable, Equatable, Sendable {
    public let accessToken: String?
    public let refreshToken: String?
    public let accountId: String?

    public init(accessToken: String? = nil, refreshToken: String? = nil, accountId: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accountId = accountId
    }

    public var trimmedAccessToken: String {
        accessToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    public var trimmedRefreshToken: String {
        refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

public struct CodexCLIAuthFile: Codable, Equatable, Sendable {
    public let authMode: String?
    public let tokens: CodexCLITokens?
    public let lastRefresh: String?

    public init(authMode: String? = nil, tokens: CodexCLITokens? = nil, lastRefresh: String? = nil) {
        self.authMode = authMode
        self.tokens = tokens
        self.lastRefresh = lastRefresh
    }

    public var usableTokens: CodexCLITokens? {
        guard let tokens, !tokens.trimmedAccessToken.isEmpty else {
            return nil
        }
        return tokens
    }
}

public extension Array where Element == TextLLMProviderConfiguration {
    func configuration(for provider: TextLLMProviderKind) -> TextLLMProviderConfiguration {
        first { $0.provider == provider } ?? TextLLMProviderConfiguration(provider: provider)
    }

    func providerSelectionChoices(
        selected: TextLLMProviderKind? = nil,
        defaultProvider: TextLLMProviderKind? = nil
    ) -> [TextLLMProviderKind] {
        var choices: [TextLLMProviderKind] = []
        var seen = Set<TextLLMProviderKind>()

        func append(_ provider: TextLLMProviderKind?) {
            guard let provider, seen.insert(provider).inserted else {
                return
            }
            choices.append(provider)
        }

        append(selected)
        append(defaultProvider)

        for configuration in self where configuration.isVisibleInSettings {
            append(configuration.provider)
        }

        for configuration in self where configuration.isConfigured {
            append(configuration.provider)
        }

        return choices
    }

    func normalizedTextLLMConfigurations(
        legacyBaseURL: String = "",
        legacyModel: String = "",
        legacyAPIKey: String = ""
    ) -> [TextLLMProviderConfiguration] {
        TextLLMProviderKind.allCases.map { provider in
            if let existing = first(where: { $0.provider == provider }) {
                return existing.normalized()
            }

            if provider == .custom,
               !legacyBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !legacyModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return TextLLMProviderConfiguration(
                    provider: .custom,
                    enabled: true,
                    manuallyAdded: true,
                    customName: "Custom",
                    baseURL: legacyBaseURL,
                    model: legacyModel,
                    apiKey: legacyAPIKey,
                    transport: .openAICompatible,
                    authMode: .apiKey
                )
                .normalized()
            }

            return TextLLMProviderConfiguration(provider: provider)
        }
    }
}

public struct HotkeyBinding: Codable, Equatable, Hashable, Sendable {
    public static let modifierOnlyKeyCode = UInt32.max
    public static let modifierMask = carbonModifiers(command: true, option: true, control: true, shift: true)

    public let keyCode: UInt32
    public let modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let defaultDictation = HotkeyBinding(keyCode: 49, modifiers: 2_304)
    public static let defaultStyle = HotkeyBinding(keyCode: 1, modifiers: 2_304)
    public static let defaultHotMenu = HotkeyBinding.modifierOnly(carbonModifiers(option: true, control: true))
    public static let defaultTranscriptCache = HotkeyBinding(keyCode: 8, modifiers: 2_304)
    public static let dictationPresets = [
        HotkeyBinding(keyCode: 49, modifiers: 2_304),
        HotkeyBinding(keyCode: 2, modifiers: 2_304),
        HotkeyBinding(keyCode: 3, modifiers: 2_304),
        HotkeyBinding(keyCode: 49, modifiers: 6_144),
    ]
    public static let stylePresets = [
        HotkeyBinding(keyCode: 1, modifiers: 2_304),
        HotkeyBinding(keyCode: 17, modifiers: 2_304),
        HotkeyBinding(keyCode: 16, modifiers: 2_304),
        HotkeyBinding(keyCode: 1, modifiers: 6_144),
    ]

    public static func modifierOnly(_ modifiers: UInt32) -> HotkeyBinding {
        HotkeyBinding(keyCode: modifierOnlyKeyCode, modifiers: modifiers & modifierMask)
    }

    public var isModifierOnly: Bool {
        keyCode == Self.modifierOnlyKeyCode
    }

    public var displayName: String {
        isModifierOnly ? modifierDisplayName : "\(modifierDisplayName)\(keyDisplayName)"
    }

    public var hasModifier: Bool {
        modifiers & Self.modifierMask != 0
    }

    public var modifierCount: Int {
        Self.modifierCount(in: modifiers)
    }

    public static func modifierCount(in modifiers: UInt32) -> Int {
        [4_096, 2_048, 512, 256].filter { modifiers & UInt32($0) != 0 }.count
    }

    public static func displayName(forModifiers modifiers: UInt32) -> String {
        modifierOnly(modifiers).displayName
    }

    public static func carbonModifiers(
        command: Bool = false,
        option: Bool = false,
        control: Bool = false,
        shift: Bool = false
    ) -> UInt32 {
        var result: UInt32 = 0
        if command { result |= 256 }
        if option { result |= 2_048 }
        if control { result |= 4_096 }
        if shift { result |= 512 }
        return result
    }

    private var modifierDisplayName: String {
        var parts: [String] = []
        if modifiers & 4_096 != 0 { parts.append("⌃") }
        if modifiers & 2_048 != 0 { parts.append("⌥") }
        if modifiers & 512 != 0 { parts.append("⇧") }
        if modifiers & 256 != 0 { parts.append("⌘") }
        return parts.joined()
    }

    private var keyDisplayName: String {
        switch keyCode {
        case 49: "Space"
        case 36: "Return"
        case 48: "Tab"
        case 51: "Delete"
        case 53: "Esc"
        case 18: "1"
        case 19: "2"
        case 20: "3"
        case 21: "4"
        case 23: "5"
        case 22: "6"
        case 26: "7"
        case 28: "8"
        case 25: "9"
        case 29: "0"
        case 0: "A"
        case 1: "S"
        case 2: "D"
        case 3: "F"
        case 4: "H"
        case 5: "G"
        case 6: "Z"
        case 7: "X"
        case 8: "C"
        case 9: "V"
        case 11: "B"
        case 12: "Q"
        case 13: "W"
        case 14: "E"
        case 15: "R"
        case 16: "Y"
        case 17: "T"
        case 31: "O"
        case 32: "U"
        case 34: "I"
        case 35: "P"
        case 37: "L"
        case 38: "J"
        case 40: "K"
        case 45: "N"
        case 46: "M"
        case 123: "←"
        case 124: "→"
        case 125: "↓"
        case 126: "↑"
        default: "Key \(keyCode)"
        }
    }
}

public struct MouseButtonBinding: Codable, Equatable, Hashable, Sendable {
    public static let minimumShortcutButtonNumber = 3
    public static let defaultPushToTalk = MouseButtonBinding(buttonNumber: 3)
    public static let defaultTranscriptCache = MouseButtonBinding(buttonNumber: 4)

    public let buttonNumber: Int

    public init(buttonNumber: Int) {
        self.buttonNumber = buttonNumber
    }

    public var isUsableShortcut: Bool {
        buttonNumber >= Self.minimumShortcutButtonNumber
    }

    public var displayName: String {
        switch buttonNumber {
        case 0:
            "Left Click"
        case 1:
            "Right Click"
        case 2:
            "Middle Click"
        default:
            "Mouse Button \(buttonNumber + 1)"
        }
    }
}

public struct TranscriptCacheSelectionState: Equatable, Sendable {
    public private(set) var selectedIndex: Int

    public init(selectedIndex: Int = 0) {
        self.selectedIndex = max(0, selectedIndex)
    }

    public mutating func reset(count: Int) {
        guard count > 0 else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(selectedIndex, count - 1)
    }

    public mutating func move(delta: Int, count: Int) {
        guard count > 0 else {
            selectedIndex = 0
            return
        }
        let next = (selectedIndex + delta) % count
        selectedIndex = next >= 0 ? next : next + count
    }

    public func selected<Item>(from items: [Item]) -> Item? {
        guard items.indices.contains(selectedIndex) else {
            return nil
        }
        return items[selectedIndex]
    }
}

public enum HotMenuDirection: String, CaseIterable, Codable, Equatable, Sendable {
    case up
    case left
    case right
    case down

    public var displayName: String {
        switch self {
        case .up:
            "Up"
        case .left:
            "Left"
        case .right:
            "Right"
        case .down:
            "Down"
        }
    }
}

public enum HotMenuAction: String, CaseIterable, Codable, Equatable, Sendable {
    public static let visibleSlotCount = 4

    case none
    case openConversation = "open_conversation"
    case transcriptionMode = "transcription_mode"
    case askAI = "ask_ai"
    case selectionRewrite = "selection_rewrite"
    case dictation
    case toggleTranslation = "toggle_translation"
    case translationOff = "translation_off"
    case translationOn = "translation_on"
    case cycleTranslationLanguage = "cycle_translation_language"
    case translationQuickTarget1 = "translation_quick_target_1"
    case translationQuickTarget2 = "translation_quick_target_2"
    case translationQuickTarget3 = "translation_quick_target_3"
    case translationQuickTarget4 = "translation_quick_target_4"
    case cycleStyle = "cycle_style"
    case styleNeutral = "style_neutral"
    case styleProfessional = "style_professional"
    case styleConcise = "style_concise"
    case styleExpanded = "style_expanded"
    case styleRaw = "style_raw"
    case cycleASRProvider = "cycle_asr_provider"
    case openDashboard = "open_dashboard"

    public var displayName: String {
        switch self {
        case .none:
            "No Action"
        case .openConversation:
            "Conversation"
        case .transcriptionMode:
            "Transcription"
        case .askAI:
            "Ask AI"
        case .selectionRewrite:
            "Unavailable"
        case .dictation:
            "Dictation"
        case .toggleTranslation:
            "Translation State"
        case .translationOff:
            "Translation Off"
        case .translationOn:
            "Translation On"
        case .cycleTranslationLanguage:
            "Translation Language"
        case .translationQuickTarget1:
            "Hot Language 1"
        case .translationQuickTarget2:
            "Hot Language 2"
        case .translationQuickTarget3:
            "Hot Language 3"
        case .translationQuickTarget4:
            "Hot Language 4"
        case .cycleStyle:
            "Dictation Style"
        case .styleNeutral:
            StyleProfile.neutral.displayName
        case .styleProfessional:
            StyleProfile.professional.displayName
        case .styleConcise:
            StyleProfile.concise.displayName
        case .styleExpanded:
            StyleProfile.expanded.displayName
        case .styleRaw:
            StyleProfile.raw.displayName
        case .cycleASRProvider:
            "Cycle ASR"
        case .openDashboard:
            "Dashboard"
        }
    }

    public static func defaultActions(for direction: HotMenuDirection) -> [HotMenuAction] {
        switch direction {
        case .up:
            [.openConversation, .transcriptionMode, .askAI]
        case .left:
            [.cycleTranslationLanguage]
        case .right:
            [.toggleTranslation]
        case .down:
            [.cycleStyle]
        }
    }

    public static func defaultAction(for direction: HotMenuDirection) -> HotMenuAction {
        defaultActions(for: direction).first ?? .none
    }

    public static var configurationCases: [HotMenuAction] {
        allCases.filter { $0.isConfigurable }
    }

    public static func quickTranslationTargetAction(forSlot slot: Int) -> HotMenuAction? {
        switch slot {
        case 0:
            .translationQuickTarget1
        case 1:
            .translationQuickTarget2
        case 2:
            .translationQuickTarget3
        case 3:
            .translationQuickTarget4
        default:
            nil
        }
    }

    public var quickTranslationTargetSlot: Int? {
        switch self {
        case .translationQuickTarget1:
            0
        case .translationQuickTarget2:
            1
        case .translationQuickTarget3:
            2
        case .translationQuickTarget4:
            3
        default:
            nil
        }
    }

    public var isGeneratedTranslationTarget: Bool {
        quickTranslationTargetSlot != nil
    }

    public var isGeneratedTranslationState: Bool {
        self == .translationOff || self == .translationOn
    }

    public static func styleAction(for profile: StyleProfile) -> HotMenuAction {
        switch profile {
        case .neutral:
            .styleNeutral
        case .professional:
            .styleProfessional
        case .concise:
            .styleConcise
        case .expanded:
            .styleExpanded
        case .raw:
            .styleRaw
        }
    }

    public var styleProfile: StyleProfile? {
        switch self {
        case .styleNeutral:
            .neutral
        case .styleProfessional:
            .professional
        case .styleConcise:
            .concise
        case .styleExpanded:
            .expanded
        case .styleRaw:
            .raw
        default:
            nil
        }
    }

    public var isConfigurable: Bool {
        !isGeneratedTranslationTarget
            && !isGeneratedTranslationState
            && styleProfile == nil
            && self != .selectionRewrite
    }

    public var isRuntimeSelectable: Bool {
        self != .none && self != .selectionRewrite
    }

    public static func normalizedActions(
        _ actions: [HotMenuAction],
        for direction: HotMenuDirection
    ) -> [HotMenuAction] {
        let limited = Array(actions.prefix(visibleSlotCount))
        return limited.isEmpty ? defaultActions(for: direction) : limited
    }
}

public enum HotMenuSelection {
    public static func direction(
        deltaX: Double,
        deltaY: Double,
        deadZoneRadius: Double
    ) -> HotMenuDirection? {
        let distance = (deltaX * deltaX + deltaY * deltaY).squareRoot()
        guard distance >= deadZoneRadius else {
            return nil
        }

        if abs(deltaY) >= abs(deltaX) {
            return deltaY >= 0 ? .up : .down
        }

        return deltaX >= 0 ? .right : .left
    }
}

public struct HotMenuActionRingState: Equatable, Sendable {
    public private(set) var selectedDirection: HotMenuDirection?
    private var selectedIndexes: [HotMenuDirection: Int]

    public init(
        selectedDirection: HotMenuDirection? = nil,
        selectedIndexes: [HotMenuDirection: Int] = [:]
    ) {
        self.selectedDirection = selectedDirection
        self.selectedIndexes = selectedIndexes
    }

    public func selectedIndex(
        for direction: HotMenuDirection,
        actions: [HotMenuDirection: [HotMenuAction]]
    ) -> Int {
        let actionCount = actionsForDirection(direction, actions: actions).count
        return min(max(selectedIndexes[direction] ?? 0, 0), max(actionCount - 1, 0))
    }

    public mutating func select(
        _ direction: HotMenuDirection?,
        cycleIfSameDirection: Bool,
        actions: [HotMenuDirection: [HotMenuAction]]
    ) {
        guard let direction else {
            selectedDirection = nil
            return
        }

        let actionCount = actionsForDirection(direction, actions: actions).count
        if selectedDirection == direction, cycleIfSameDirection, actionCount > 1 {
            selectedIndexes[direction] = (selectedIndex(for: direction, actions: actions) + 1) % actionCount
        } else {
            selectedIndexes[direction] = selectedIndex(for: direction, actions: actions)
        }
        selectedDirection = direction
    }

    public func selectedAction(in actions: [HotMenuDirection: [HotMenuAction]]) -> HotMenuAction? {
        guard let selectedDirection else {
            return nil
        }

        let directionActions = actionsForDirection(selectedDirection, actions: actions)
        guard !directionActions.isEmpty else {
            return nil
        }
        return directionActions[selectedIndex(for: selectedDirection, actions: actions)]
    }

    public func actionsForDirection(
        _ direction: HotMenuDirection,
        actions: [HotMenuDirection: [HotMenuAction]]
    ) -> [HotMenuAction] {
        HotMenuAction.normalizedActions(actions[direction] ?? [], for: direction)
            .filter(\.isRuntimeSelectable)
    }
}

public enum HotMenuPresentationMode: Equatable, Sendable {
    case momentary
    case latched
}

public struct HotMenuTriggerState: Equatable, Sendable {
    public static let doubleTapInterval: TimeInterval = 0.35

    public private(set) var mode: HotMenuPresentationMode?
    private var lastMomentaryReleaseTime: TimeInterval?

    public init(mode: HotMenuPresentationMode? = nil) {
        self.mode = mode
    }

    public func canLatch(onPressAt time: TimeInterval) -> Bool {
        guard let lastMomentaryReleaseTime else {
            return false
        }
        return time - lastMomentaryReleaseTime <= Self.doubleTapInterval
    }

    @discardableResult
    public mutating func press(at time: TimeInterval) -> HotMenuPresentationMode {
        if canLatch(onPressAt: time) {
            mode = .latched
            lastMomentaryReleaseTime = nil
            return .latched
        }

        mode = .momentary
        return .momentary
    }

    @discardableResult
    public mutating func release(at time: TimeInterval) -> Bool {
        switch mode {
        case .momentary:
            mode = nil
            lastMomentaryReleaseTime = time
            return true
        case .latched:
            return false
        case nil:
            return false
        }
    }

    public mutating func finish() {
        mode = nil
        lastMomentaryReleaseTime = nil
    }
}

public struct TranscriptUpdate: Codable, Equatable, Sendable {
    public let text: String
    public let isFinal: Bool

    public init(text: String, isFinal: Bool) {
        self.text = text
        self.isFinal = isFinal
    }
}

public struct CleanupRequest: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public let canonical: String
        public let aliases: [String]
        public let enabled: Bool
        public init(canonical: String, aliases: [String], enabled: Bool) {
            self.canonical = canonical
            self.aliases = aliases
            self.enabled = enabled
        }
    }

    public let rawTranscript: String
    public let style: StyleProfile
    public let dictionaryTerms: [String]
    public let dictionaryEntries: [Entry]

    public init(
        rawTranscript: String,
        style: StyleProfile,
        dictionaryTerms: [String] = [],
        dictionaryEntries: [Entry] = []
    ) {
        self.rawTranscript = rawTranscript
        self.style = style
        self.dictionaryTerms = dictionaryTerms
        self.dictionaryEntries = dictionaryEntries
    }

    /// Maps personal-dictionary entries to the engine's wire form.
    public static func entries(from dictionaryEntries: [DictionaryEntry]) -> [Entry] {
        dictionaryEntries.map { Entry(canonical: $0.canonical, aliases: $0.aliases, enabled: $0.enabled) }
    }
}

public struct CleanupResult: Codable, Equatable, Sendable {
    public let text: String
    public let cleanupApplied: Bool

    public init(text: String, cleanupApplied: Bool) {
        self.text = text
        self.cleanupApplied = cleanupApplied
    }
}

public struct TranslationRequest: Codable, Equatable, Sendable {
    public let text: String
    public let provider: TranslationProviderKind
    public let sourceLanguage: String
    public let targetLanguage: String
    public let context: [String]
    public let modelPath: String
    public let isFinal: Bool

    public init(
        text: String,
        provider: TranslationProviderKind,
        sourceLanguage: String,
        targetLanguage: String,
        context: [String] = [],
        modelPath: String = "",
        isFinal: Bool = true
    ) {
        self.text = text
        self.provider = provider
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.context = context
        self.modelPath = modelPath
        self.isFinal = isFinal
    }
}

public struct TranslationResult: Codable, Equatable, Sendable {
    public let text: String
    public let provider: TranslationProviderKind
    public let sourceLanguage: String
    public let detectedLanguage: String
    public let targetLanguage: String
    public let confidence: Double
    public let isFinal: Bool

    public init(
        text: String,
        provider: TranslationProviderKind,
        sourceLanguage: String,
        detectedLanguage: String,
        targetLanguage: String,
        confidence: Double,
        isFinal: Bool
    ) {
        self.text = text
        self.provider = provider
        self.sourceLanguage = sourceLanguage
        self.detectedLanguage = detectedLanguage
        self.targetLanguage = targetLanguage
        self.confidence = confidence
        self.isFinal = isFinal
    }
}

public struct TranslationProviderInfo: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let available: Bool
    public let reason: String?

    public var kind: TranslationProviderKind { TranslationProviderKind(providerID: id) }

    public init(id: String, label: String, available: Bool, reason: String? = nil) {
        self.id = id
        self.label = label
        self.available = available
        self.reason = reason
    }
}

public struct AIHandoffRequest: Codable, Equatable, Sendable {
    public let prompt: String
    public let provider: String
    public let baseURL: String
    public let model: String
    public let apiKey: String
    public let transport: TextLLMTransport
    public let oauthAccessToken: String
    public let headers: [String: String]
    public let context: String

    public init(
        prompt: String,
        provider: String,
        baseURL: String,
        model: String,
        apiKey: String = "",
        transport: TextLLMTransport = .openAICompatible,
        oauthAccessToken: String = "",
        headers: [String: String] = [:],
        context: String = ""
    ) {
        self.prompt = prompt
        self.provider = provider
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.transport = transport
        self.oauthAccessToken = oauthAccessToken
        self.headers = headers
        self.context = context
    }
}

public struct AIHandoffResult: Codable, Equatable, Sendable {
    public let text: String
    public let provider: String
    public let model: String

    public init(text: String, provider: String, model: String) {
        self.text = text
        self.provider = provider
        self.model = model
    }
}

public struct AIChatMessage: Codable, Equatable, Sendable {
    public let role: AskAIMessageRole
    public let content: String

    public init(role: AskAIMessageRole, content: String) {
        self.role = role
        self.content = content
    }
}

public struct AIChatAttachment: Codable, Equatable, Sendable {
    public let kind: AskAIContextAttachmentKind
    public let title: String
    public let text: String
    public let mimeType: String
    public let dataURL: String

    public init(
        kind: AskAIContextAttachmentKind,
        title: String,
        text: String,
        mimeType: String = "",
        dataURL: String = ""
    ) {
        self.kind = kind
        self.title = title
        self.text = text
        self.mimeType = mimeType
        self.dataURL = dataURL
    }

    public init(_ attachment: AskAIContextAttachment) {
        self.init(
            kind: attachment.kind,
            title: attachment.title,
            text: attachment.text,
            mimeType: attachment.mimeType ?? "",
            dataURL: attachment.dataURL ?? ""
        )
    }
}

public struct AIChatRequest: Codable, Equatable, Sendable {
    public let provider: String
    public let baseURL: String
    public let model: String
    public let apiKey: String
    public let transport: TextLLMTransport
    public let oauthAccessToken: String
    public let headers: [String: String]
    public let messages: [AIChatMessage]
    public let attachments: [AIChatAttachment]
    public let webSearchEnabled: Bool
    public let webSearchQuery: String

    public init(
        provider: String,
        baseURL: String,
        model: String,
        apiKey: String = "",
        transport: TextLLMTransport = .openAICompatible,
        oauthAccessToken: String = "",
        headers: [String: String] = [:],
        messages: [AIChatMessage],
        attachments: [AIChatAttachment] = [],
        webSearchEnabled: Bool = false,
        webSearchQuery: String = ""
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.transport = transport
        self.oauthAccessToken = oauthAccessToken
        self.headers = headers
        self.messages = messages
        self.attachments = attachments
        self.webSearchEnabled = webSearchEnabled
        self.webSearchQuery = webSearchQuery
    }
}

public struct AIChatResult: Codable, Equatable, Sendable {
    public let text: String
    public let provider: String
    public let model: String

    public init(text: String, provider: String, model: String) {
        self.text = text
        self.provider = provider
        self.model = model
    }
}
