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

public struct EngineClient: Sendable {
    public enum EngineError: Error, Equatable {
        case badStatus(Int)
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
        try validate(response)
        return try EngineCoding.decoder.decode(EngineHealth.self, from: data)
    }

    public func providers() async throws -> [EngineProviderInfo] {
        let endpoint = baseURL.appending(path: "providers")
        let (data, response) = try await urlSession.data(from: endpoint)
        try validate(response)
        return try EngineCoding.decoder.decode([EngineProviderInfo].self, from: data)
    }

    public func cleanup(_ request: CleanupRequest) async throws -> CleanupResult {
        let endpoint = baseURL.appending(path: "cleanup")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try EngineCoding.encoder.encode(request)

        let (data, response) = try await urlSession.data(for: urlRequest)
        try validate(response)
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
        try validate(response)
        return try EngineCoding.decoder.decode(TranscribeResult.self, from: data)
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw EngineError.badStatus(http.statusCode)
        }
    }
}
