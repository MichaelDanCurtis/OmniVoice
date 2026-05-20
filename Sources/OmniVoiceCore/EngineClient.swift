import Foundation

public enum EngineCoding {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

public struct TranscribeResult: Codable, Equatable, Sendable {
    public let text: String
    public let provider: ASRProviderKind

    public init(text: String, provider: ASRProviderKind) {
        self.text = text
        self.provider = provider
    }
}

public struct EngineHealth: Codable, Equatable, Sendable {
    public let status: String

    public init(status: String) {
        self.status = status
    }
}

public struct EngineProviderInfo: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let available: Bool
    public let reason: String?

    public init(id: String, label: String, available: Bool, reason: String? = nil) {
        self.id = id
        self.label = label
        self.available = available
        self.reason = reason
    }
}

public struct EngineModelStatus: Codable, Equatable, Identifiable, Sendable {
    public let providerId: String
    public let label: String
    public let repoId: String
    public let localPath: String
    public let installed: Bool
    public let category: String
    public let recommendation: String?
    public let detail: String?
    public let size: String?
    public let precision: String?
    public let requiresHfAuth: Bool
    public let agreementUrl: String?
    public let license: String?
    public let installedRevision: String?
    public let remoteRevision: String?
    public let updateAvailable: Bool?
    public let missingFiles: [String]
    public let downloadState: String
    public let downloadMessage: String?

    public var id: String { providerId }
    public var providerID: String { providerId }
    public var repoID: String { repoId }
    public var requiresHFAuth: Bool { requiresHfAuth }
    public var agreementURL: String? { agreementUrl }

    public init(
        providerID: String,
        label: String,
        repoID: String,
        localPath: String,
        installed: Bool,
        category: String = "asr",
        recommendation: String? = nil,
        detail: String? = nil,
        size: String? = nil,
        precision: String? = nil,
        requiresHFAuth: Bool = false,
        agreementURL: String? = nil,
        license: String? = nil,
        installedRevision: String? = nil,
        remoteRevision: String? = nil,
        updateAvailable: Bool? = nil,
        missingFiles: [String] = [],
        downloadState: String = "idle",
        downloadMessage: String? = nil
    ) {
        self.providerId = providerID
        self.label = label
        self.repoId = repoID
        self.localPath = localPath
        self.installed = installed
        self.category = category
        self.recommendation = recommendation
        self.detail = detail
        self.size = size
        self.precision = precision
        self.requiresHfAuth = requiresHFAuth
        self.agreementUrl = agreementURL
        self.license = license
        self.installedRevision = installedRevision
        self.remoteRevision = remoteRevision
        self.updateAvailable = updateAvailable
        self.missingFiles = missingFiles
        self.downloadState = downloadState
        self.downloadMessage = downloadMessage
    }
}

public struct EngineModelUpdateInfo: Codable, Equatable, Sendable {
    public let providerId: String
    public let repoId: String
    public let installedRevision: String?
    public let remoteRevision: String
    public let updateAvailable: Bool
    public var providerID: String { providerId }
    public var repoID: String { repoId }

    public init(
        providerID: String,
        repoID: String,
        installedRevision: String? = nil,
        remoteRevision: String,
        updateAvailable: Bool
    ) {
        self.providerId = providerID
        self.repoId = repoID
        self.installedRevision = installedRevision
        self.remoteRevision = remoteRevision
        self.updateAvailable = updateAvailable
    }
}

public struct EngineModelDownloadStatus: Codable, Equatable, Sendable {
    public let providerId: String
    public let state: String
    public let message: String?
    public let localPath: String
    public let revision: String?
    public var providerID: String { providerId }

    public init(
        providerID: String,
        state: String,
        message: String? = nil,
        localPath: String,
        revision: String? = nil
    ) {
        self.providerId = providerID
        self.state = state
        self.message = message
        self.localPath = localPath
        self.revision = revision
    }
}

public struct HuggingFaceTokenValidationRequest: Codable, Equatable, Sendable {
    public let token: String
    public let providerId: String
    public var providerID: String { providerId }

    public init(token: String, providerID: String) {
        self.token = token
        self.providerId = providerID
    }
}

public struct HuggingFaceAuthStatus: Codable, Equatable, Sendable {
    public let connected: Bool
    public let source: String
    public let username: String?
    public let providerId: String?
    public let repoId: String?
    public let accessGranted: Bool?
    public let message: String

    public var providerID: String? { providerId }
    public var repoID: String? { repoId }

    public init(
        connected: Bool,
        source: String,
        username: String? = nil,
        providerID: String? = nil,
        repoID: String? = nil,
        accessGranted: Bool? = nil,
        message: String
    ) {
        self.connected = connected
        self.source = source
        self.username = username
        self.providerId = providerID
        self.repoId = repoID
        self.accessGranted = accessGranted
        self.message = message
    }
}

public struct TranslationLanguageOption: Codable, Equatable, Identifiable, Sendable {
    public let code: String
    public let name: String
    public let isDefault: Bool

    public var id: String { code }

    public init(code: String, name: String, isDefault: Bool = false) {
        self.code = code
        self.name = name
        self.isDefault = isDefault
    }
}

public struct TranslationCapabilities: Codable, Equatable, Sendable {
    public let providerId: String
    public let modelProviderId: String?
    public let sourceLanguageLocked: Bool
    public let sourceLanguageReason: String?
    public let sourceLanguages: [TranslationLanguageOption]
    public let targetLanguages: [TranslationLanguageOption]
    public let capabilitySource: String
    public let message: String?

    public var providerID: String { providerId }
    public var modelProviderID: String? { modelProviderId }

    public init(
        providerID: String,
        modelProviderID: String? = nil,
        sourceLanguageLocked: Bool,
        sourceLanguageReason: String? = nil,
        sourceLanguages: [TranslationLanguageOption],
        targetLanguages: [TranslationLanguageOption],
        capabilitySource: String,
        message: String? = nil
    ) {
        self.providerId = providerID
        self.modelProviderId = modelProviderID
        self.sourceLanguageLocked = sourceLanguageLocked
        self.sourceLanguageReason = sourceLanguageReason
        self.sourceLanguages = sourceLanguages
        self.targetLanguages = targetLanguages
        self.capabilitySource = capabilitySource
        self.message = message
    }
}

public struct TranslationValidationRequest: Codable, Equatable, Sendable {
    public let text: String
    public let provider: TranslationProviderKind
    public let sourceLanguage: String
    public let modelPath: String
    public let targetLanguages: [String]
    public let maxLanguages: Int?

    public init(
        text: String = "Hello, thank you for coming.",
        provider: TranslationProviderKind,
        sourceLanguage: String = "en",
        modelPath: String = "",
        targetLanguages: [String] = [],
        maxLanguages: Int? = nil
    ) {
        self.text = text
        self.provider = provider
        self.sourceLanguage = sourceLanguage
        self.modelPath = modelPath
        self.targetLanguages = targetLanguages
        self.maxLanguages = maxLanguages
    }
}

public struct TranslationValidationItem: Codable, Equatable, Sendable, Identifiable {
    public let code: String
    public let name: String
    public let text: String
    public let status: String
    public let expectedScripts: [String]
    public let dominantScript: String?
    public let scripts: [String: Int]
    public let letterCount: Int?
    public let expectedScriptCharacters: Int?
    public let expectedScriptRatio: Double?
    public let replacementCharacters: Int
    public let outputPreview: String?
    public let failureCategory: String?
    public let notes: [String]

    public var id: String { code }

    public init(
        code: String,
        name: String,
        text: String,
        status: String,
        expectedScripts: [String] = [],
        dominantScript: String? = nil,
        scripts: [String: Int] = [:],
        letterCount: Int? = nil,
        expectedScriptCharacters: Int? = nil,
        expectedScriptRatio: Double? = nil,
        replacementCharacters: Int = 0,
        outputPreview: String? = nil,
        failureCategory: String? = nil,
        notes: [String] = []
    ) {
        self.code = code
        self.name = name
        self.text = text
        self.status = status
        self.expectedScripts = expectedScripts
        self.dominantScript = dominantScript
        self.scripts = scripts
        self.letterCount = letterCount
        self.expectedScriptCharacters = expectedScriptCharacters
        self.expectedScriptRatio = expectedScriptRatio
        self.replacementCharacters = replacementCharacters
        self.outputPreview = outputPreview
        self.failureCategory = failureCategory
        self.notes = notes
    }
}

public struct TranslationValidationResponse: Codable, Equatable, Sendable {
    public let provider: TranslationProviderKind
    public let sourceLanguage: String
    public let text: String
    public let capabilitySource: String
    public let tested: Int
    public let passed: Int
    public let review: Int
    public let failed: Int
    public let items: [TranslationValidationItem]

    public init(
        provider: TranslationProviderKind,
        sourceLanguage: String,
        text: String,
        capabilitySource: String,
        tested: Int,
        passed: Int,
        review: Int,
        failed: Int,
        items: [TranslationValidationItem]
    ) {
        self.provider = provider
        self.sourceLanguage = sourceLanguage
        self.text = text
        self.capabilitySource = capabilitySource
        self.tested = tested
        self.passed = passed
        self.review = review
        self.failed = failed
        self.items = items
    }
}

public struct EngineTranscriptRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let createdAt: String
    public let source: String
    public let rawText: String
    public let cleanedText: String?
    public let provider: String?
    public let style: String?
    public let audioBytes: Int?
    public let sampleRate: Int?
    public let durationMs: Int?

    public var displayText: String {
        let cleaned = cleanedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cleaned.isEmpty ? rawText : cleaned
    }

    public init(
        id: String,
        createdAt: String,
        source: String,
        rawText: String,
        cleanedText: String? = nil,
        provider: String? = nil,
        style: String? = nil,
        audioBytes: Int? = nil,
        sampleRate: Int? = nil,
        durationMs: Int? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.source = source
        self.rawText = rawText
        self.cleanedText = cleanedText
        self.provider = provider
        self.style = style
        self.audioBytes = audioBytes
        self.sampleRate = sampleRate
        self.durationMs = durationMs
    }
}

public struct EngineClient: Sendable {
    public enum EngineError: Error, Equatable {
        case badStatus(Int, String?)
        case invalidURL
    }

    public let baseURL: URL
    private let urlSession: URLSession

    public init(baseURL: URL = URL(string: "http://127.0.0.1:8765")!, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.urlSession = urlSession
    }

    public func health() async throws -> EngineHealth {
        let endpoint = baseURL.appending(path: "health")
        let (data, response) = try await urlSession.data(from: endpoint)
        try validate(response, data: data)
        return try EngineCoding.decoder.decode(EngineHealth.self, from: data)
    }

    public func providers() async throws -> [EngineProviderInfo] {
        let endpoint = baseURL.appending(path: "providers")
        let (data, response) = try await urlSession.data(from: endpoint)
        try validate(response, data: data)
        return try EngineCoding.decoder.decode([EngineProviderInfo].self, from: data)
    }

    public func diarizationProviders() async throws -> [EngineProviderInfo] {
        let endpoint = baseURL.appending(path: "diarization").appending(path: "providers")
        let (data, response) = try await urlSession.data(from: endpoint)
        try validate(response, data: data)
        return try EngineCoding.decoder.decode([EngineProviderInfo].self, from: data)
    }

    public func models() async throws -> [EngineModelStatus] {
        let endpoint = baseURL.appending(path: "models")
        let (data, response) = try await urlSession.data(from: endpoint)
        try validate(response, data: data)
        return try EngineCoding.decoder.decode([EngineModelStatus].self, from: data)
    }

    public func transcripts(limit: Int = 200) async throws -> [EngineTranscriptRecord] {
        var components = URLComponents(url: baseURL.appending(path: "api").appending(path: "transcripts"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        guard let endpoint = components?.url else { throw EngineError.invalidURL }

        let (data, response) = try await urlSession.data(from: endpoint)
        try validate(response, data: data)
        return try EngineCoding.decoder.decode([EngineTranscriptRecord].self, from: data)
    }

    public func createConversation(_ request: ConversationSessionCreateRequest) async throws -> ConversationSession {
        let endpoint = baseURL.appending(path: "api").appending(path: "conversations")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try EngineCoding.encoder.encode(request)

        let (data, response) = try await urlSession.data(for: urlRequest)
        try validate(response, data: data)
        return try EngineCoding.decoder.decode(ConversationSession.self, from: data)
    }

    public func conversations(limit: Int = 100) async throws -> [ConversationSession] {
        var components = URLComponents(url: baseURL.appending(path: "api").appending(path: "conversations"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        guard let endpoint = components?.url else { throw EngineError.invalidURL }

        let (data, response) = try await urlSession.data(from: endpoint)
        try validate(response, data: data)
        return try EngineCoding.decoder.decode([ConversationSession].self, from: data)
    }

    public func conversationDetail(sessionID: String) async throws -> ConversationDetail {
        let endpoint = baseURL
            .appending(path: "api")
            .appending(path: "conversations")
            .appending(path: sessionID)
        let (data, response) = try await urlSession.data(from: endpoint)
        try validate(response, data: data)
        return try EngineCoding.decoder.decode(ConversationDetail.self, from: data)
    }

    public func updateConversation(sessionID: String, request: ConversationDetailUpdateRequest) async throws -> ConversationDetail {
        let endpoint = baseURL
            .appending(path: "api")
            .appending(path: "conversations")
            .appending(path: sessionID)
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "PATCH"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try EngineCoding.encoder.encode(request)

        let (data, response) = try await urlSession.data(for: urlRequest)
        try validate(response, data: data)
        return try EngineCoding.decoder.decode(ConversationDetail.self, from: data)
    }

    public func deleteConversation(sessionID: String) async throws {
        let endpoint = baseURL
            .appending(path: "api")
            .appending(path: "conversations")
            .appending(path: sessionID)
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "DELETE"

        let (data, response) = try await urlSession.data(for: urlRequest)
        try validate(response, data: data)
    }

    public func importConversation(_ detail: ConversationDetail) async throws -> ConversationImportResult {
        let endpoint = baseURL
            .appending(path: "api")
            .appending(path: "conversations")
            .appending(path: "import")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try EngineCoding.encoder.encode(detail)

        let (data, response) = try await urlSession.data(for: urlRequest)
        try validate(response, data: data)
        return try EngineCoding.decoder.decode(ConversationImportResult.self, from: data)
    }

    public func addConversationSegment(sessionID: String, request: ConversationSegmentCreateRequest) async throws -> ConversationSegment {
        let endpoint = baseURL
            .appending(path: "api")
            .appending(path: "conversations")
            .appending(path: sessionID)
            .appending(path: "segments")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try EngineCoding.encoder.encode(request)

        let (data, response) = try await urlSession.data(for: urlRequest)
        try validate(response, data: data)
        return try EngineCoding.decoder.decode(ConversationSegment.self, from: data)
    }

    public func previewConversationSegment(sessionID: String, request: ConversationSegmentCreateRequest) async throws -> ConversationSegment {
        let endpoint = baseURL
            .appending(path: "api")
            .appending(path: "conversations")
            .appending(path: sessionID)
            .appending(path: "segments")
            .appending(path: "preview")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try EngineCoding.encoder.encode(request)

        let (data, response) = try await urlSession.data(for: urlRequest)
        try validate(response, data: data)
        return try EngineCoding.decoder.decode(ConversationSegment.self, from: data)
    }

    public func addConversationAssistCard(sessionID: String, request: ConversationAssistCardCreateRequest) async throws -> ConversationAssistCard {
        let endpoint = baseURL
            .appending(path: "api")
            .appending(path: "conversations")
            .appending(path: sessionID)
            .appending(path: "assist-cards")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try EngineCoding.encoder.encode(request)

        let (data, response) = try await urlSession.data(for: urlRequest)
        try validate(response, data: data)
        return try EngineCoding.decoder.decode(ConversationAssistCard.self, from: data)
    }

    public func stopConversation(sessionID: String) async throws -> ConversationSession {
        let endpoint = baseURL
            .appending(path: "api")
            .appending(path: "conversations")
            .appending(path: sessionID)
            .appending(path: "stop")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"

        let (data, response) = try await urlSession.data(for: urlRequest)
        try validate(response, data: data)
        return try EngineCoding.decoder.decode(ConversationSession.self, from: data)
    }

    public func checkModelUpdate(provider: ASRProviderKind, huggingFaceToken: String = "") async throws -> EngineModelUpdateInfo {
        try await checkModelUpdate(providerID: provider.rawValue, huggingFaceToken: huggingFaceToken)
    }

    public func checkModelUpdate(providerID: String, huggingFaceToken: String = "") async throws -> EngineModelUpdateInfo {
        let endpoint = baseURL
            .appending(path: "models")
            .appending(path: providerID)
            .appending(path: "update")
        var urlRequest = URLRequest(url: endpoint)
        setHuggingFaceAuthorization(huggingFaceToken, on: &urlRequest)
        let (data, response) = try await urlSession.data(for: urlRequest)
        try validate(response, data: data)
        return try EngineCoding.decoder.decode(EngineModelUpdateInfo.self, from: data)
    }

    public func downloadModel(provider: ASRProviderKind, huggingFaceToken: String = "") async throws -> EngineModelDownloadStatus {
        try await downloadModel(providerID: provider.rawValue, huggingFaceToken: huggingFaceToken)
    }

    public func downloadModel(providerID: String, huggingFaceToken: String = "") async throws -> EngineModelDownloadStatus {
        let endpoint = baseURL
            .appending(path: "models")
            .appending(path: providerID)
            .appending(path: "download")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        setHuggingFaceAuthorization(huggingFaceToken, on: &urlRequest)

        let (data, response) = try await urlSession.data(for: urlRequest)
        try validate(response, data: data)
        return try EngineCoding.decoder.decode(EngineModelDownloadStatus.self, from: data)
    }

    public func modelDownloadStatus(provider: ASRProviderKind) async throws -> EngineModelDownloadStatus {
        try await modelDownloadStatus(providerID: provider.rawValue)
    }

    public func modelDownloadStatus(providerID: String) async throws -> EngineModelDownloadStatus {
        let endpoint = baseURL
            .appending(path: "models")
            .appending(path: providerID)
            .appending(path: "download")
        let (data, response) = try await urlSession.data(from: endpoint)
        try validate(response, data: data)
        return try EngineCoding.decoder.decode(EngineModelDownloadStatus.self, from: data)
    }

    public func deleteModel(provider: ASRProviderKind) async throws -> EngineModelStatus {
        try await deleteModel(providerID: provider.rawValue)
    }

    public func deleteModel(providerID: String) async throws -> EngineModelStatus {
        let endpoint = baseURL
            .appending(path: "models")
            .appending(path: providerID)
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "DELETE"

        let (data, response) = try await urlSession.data(for: urlRequest)
        try validate(response, data: data)
        return try EngineCoding.decoder.decode(EngineModelStatus.self, from: data)
    }

    public func validateHuggingFaceAccess(_ request: HuggingFaceTokenValidationRequest) async throws -> HuggingFaceAuthStatus {
        let endpoint = baseURL.appending(path: "huggingface").appending(path: "validate")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try EngineCoding.encoder.encode(request)

        let (data, response) = try await urlSession.data(for: urlRequest)
        try validate(response, data: data)
        return try EngineCoding.decoder.decode(HuggingFaceAuthStatus.self, from: data)
    }

    public func cleanup(_ request: CleanupRequest) async throws -> CleanupResult {
        let endpoint = baseURL.appending(path: "cleanup")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try EngineCoding.encoder.encode(request)

        let (data, response) = try await urlSession.data(for: urlRequest)
        try validate(response, data: data)
        return try EngineCoding.decoder.decode(CleanupResult.self, from: data)
    }

    public func translationProviders() async throws -> [TranslationProviderInfo] {
        let endpoint = baseURL
            .appending(path: "translation")
            .appending(path: "providers")
        let (data, response) = try await urlSession.data(from: endpoint)
        try validate(response, data: data)
        return try EngineCoding.decoder.decode([TranslationProviderInfo].self, from: data)
    }

    public func translationCapabilities(
        providerID: String,
        modelProviderID: String = "",
        modelPath: String = ""
    ) async throws -> TranslationCapabilities {
        let endpoint = baseURL
            .appending(path: "translation")
            .appending(path: "capabilities")
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "provider_id", value: providerID),
            URLQueryItem(name: "model_provider_id", value: modelProviderID),
            URLQueryItem(name: "model_path", value: modelPath),
        ]
        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await urlSession.data(from: url)
        try validate(response, data: data)
        return try EngineCoding.decoder.decode(TranslationCapabilities.self, from: data)
    }

    public func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        let endpoint = baseURL.appending(path: "translate")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try EngineCoding.encoder.encode(request)

        let (data, response) = try await urlSession.data(for: urlRequest)
        try validate(response, data: data)
        return try EngineCoding.decoder.decode(TranslationResult.self, from: data)
    }

    public func validateTranslations(_ request: TranslationValidationRequest) async throws -> TranslationValidationResponse {
        let endpoint = baseURL
            .appending(path: "translation")
            .appending(path: "validate")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 600
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try EngineCoding.encoder.encode(request)

        let (data, response) = try await urlSession.data(for: urlRequest)
        try validate(response, data: data)
        return try EngineCoding.decoder.decode(TranslationValidationResponse.self, from: data)
    }

    public func aiHandoff(_ request: AIHandoffRequest) async throws -> AIHandoffResult {
        let endpoint = baseURL
            .appending(path: "api")
            .appending(path: "ai")
            .appending(path: "handoff")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try EngineCoding.encoder.encode(request)

        let (data, response) = try await urlSession.data(for: urlRequest)
        try validate(response, data: data)
        return try EngineCoding.decoder.decode(AIHandoffResult.self, from: data)
    }

    public func aiChat(_ request: AIChatRequest) async throws -> AIChatResult {
        let endpoint = baseURL
            .appending(path: "api")
            .appending(path: "ai")
            .appending(path: "chat")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try EngineCoding.encoder.encode(request)

        let (data, response) = try await urlSession.data(for: urlRequest)
        try validate(response, data: data)
        return try EngineCoding.decoder.decode(AIChatResult.self, from: data)
    }

    public func textLLMModels(_ request: TextLLMModelListRequest) async throws -> TextLLMModelListResponse {
        let endpoint = baseURL
            .appending(path: "api")
            .appending(path: "ai")
            .appending(path: "models")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try EngineCoding.encoder.encode(request)

        let (data, response) = try await urlSession.data(for: urlRequest)
        try validate(response, data: data)
        return try EngineCoding.decoder.decode(TextLLMModelListResponse.self, from: data)
    }

    public func transcribe(audio: Data, provider: ASRProviderKind) async throws -> TranscribeResult {
        var components = URLComponents(url: baseURL.appending(path: "transcribe"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "provider", value: provider.rawValue)]
        guard let endpoint = components?.url else { throw EngineError.invalidURL }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = audio

        let (data, response) = try await urlSession.data(for: urlRequest)
        try validate(response, data: data)
        return try EngineCoding.decoder.decode(TranscribeResult.self, from: data)
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw EngineError.badStatus(http.statusCode, Self.errorDetail(from: data))
        }
    }

    private func setHuggingFaceAuthorization(_ token: String, on request: inout URLRequest) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
    }

    private static func errorDetail(from data: Data) -> String? {
        struct ErrorPayload: Decodable {
            let detail: String
        }

        if let payload = try? EngineCoding.decoder.decode(ErrorPayload.self, from: data) {
            return payload.detail
        }

        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

extension EngineClient.EngineError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .badStatus(let status, let detail):
            if let detail, !detail.isEmpty {
                return "Engine returned \(status): \(detail)"
            }
            return "Engine returned \(status)"
        case .invalidURL:
            return "Invalid engine URL"
        }
    }
}
