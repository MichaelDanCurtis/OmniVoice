import Foundation
import OmniVoiceCore

/// The production ``EntitlementProviding``: `GET {base}/entitlement` with the Keychain
/// access token as Bearer. On a 401 it refreshes the session once (via `/auth/refresh`)
/// and retries. Used only when `WorkerConfig.baseURL` is set; otherwise the app runs on
/// `StubEntitlementProvider`.
struct WorkerEntitlementProvider: EntitlementProviding {
    let baseURL: URL
    var store = AuthSessionStore()
    var session: URLSession = .shared

    func fetchEntitlement() async throws -> EntitlementStatus {
        guard let auth = store.load() else { return .none }

        do {
            return try await requestEntitlement(accessToken: auth.accessToken)
        } catch WorkerProviderError.unauthorized {
            let refreshed = try await refresh(refreshToken: auth.refreshToken)
            try store.save(refreshed)
            return try await requestEntitlement(accessToken: refreshed.accessToken)
        }
    }

    private func requestEntitlement(accessToken: String) async throws -> EntitlementStatus {
        var request = URLRequest(url: baseURL.appendingPathComponent("entitlement"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WorkerProviderError.badPayload
        }
        if http.statusCode == 401 {
            throw WorkerProviderError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw WorkerProviderError.badStatus(http.statusCode)
        }
        return Self.map(try JSONDecoder().decode(EntitlementDTO.self, from: data))
    }

    private func refresh(refreshToken: String) async throws -> AuthSession {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/refresh"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["refreshToken": refreshToken])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WorkerProviderError.unauthorized
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(AuthSession.self, from: data)
    }

    static func map(_ dto: EntitlementDTO) -> EntitlementStatus {
        switch dto.status {
        case "active":
            return .active
        case "trialing":
            if let trialEndsAt = dto.trialEndsAt {
                return .trialing(endsAt: Date(timeIntervalSince1970: trialEndsAt))
            }
            return .active
        case "expired":
            return .expired
        default:
            return .none
        }
    }
}

/// Wire shape returned by the Worker's `/entitlement`.
struct EntitlementDTO: Decodable {
    let status: String
    let trialEndsAt: Double?
}

enum WorkerProviderError: Error, Equatable {
    case unauthorized
    case badStatus(Int)
    case badPayload
}
