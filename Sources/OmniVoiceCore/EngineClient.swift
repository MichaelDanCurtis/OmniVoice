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
    public let installedRevision: String?
    public let remoteRevision: String?
    public let updateAvailable: Bool?
    public let missingFiles: [String]
    public let downloadState: String
    public let downloadMessage: String?

    public var id: String { providerId }
    public var providerID: String { providerId }
    public var repoID: String { repoId }

    public init(
        providerID: String,
        label: String,
        repoID: String,
        localPath: String,
        installed: Bool,
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

    public func models() async throws -> [EngineModelStatus] {
        let endpoint = baseURL.appending(path: "models")
        let (data, response) = try await urlSession.data(from: endpoint)
        try validate(response, data: data)
        return try EngineCoding.decoder.decode([EngineModelStatus].self, from: data)
    }

    public func checkModelUpdate(provider: ASRProviderKind) async throws -> EngineModelUpdateInfo {
        let endpoint = baseURL
            .appending(path: "models")
            .appending(path: provider.rawValue)
            .appending(path: "update")
        let (data, response) = try await urlSession.data(from: endpoint)
        try validate(response, data: data)
        return try EngineCoding.decoder.decode(EngineModelUpdateInfo.self, from: data)
    }

    public func downloadModel(provider: ASRProviderKind) async throws -> EngineModelDownloadStatus {
        let endpoint = baseURL
            .appending(path: "models")
            .appending(path: provider.rawValue)
            .appending(path: "download")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"

        let (data, response) = try await urlSession.data(for: urlRequest)
        try validate(response, data: data)
        return try EngineCoding.decoder.decode(EngineModelDownloadStatus.self, from: data)
    }

    public func modelDownloadStatus(provider: ASRProviderKind) async throws -> EngineModelDownloadStatus {
        let endpoint = baseURL
            .appending(path: "models")
            .appending(path: provider.rawValue)
            .appending(path: "download")
        let (data, response) = try await urlSession.data(from: endpoint)
        try validate(response, data: data)
        return try EngineCoding.decoder.decode(EngineModelDownloadStatus.self, from: data)
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
