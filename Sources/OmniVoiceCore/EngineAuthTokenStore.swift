import Foundation
import Security

/// Holds the active per-launch shared secret used to authenticate requests to the local
/// OmniSpeak FastAPI engine on `127.0.0.1`.
///
/// When `EngineSupervisor` spawns the engine, it generates a fresh 256-bit random token,
/// stores it here, and passes it to the child process via `OMNIVOICE_ENGINE_TOKEN`.
/// When talking to an already-running external dev engine started without a token,
/// `token` remains `nil` unless `OMNIVOICE_ENGINE_TOKEN` is inherited from the environment.
public final class EngineAuthTokenStore: @unchecked Sendable {
    public static let shared = EngineAuthTokenStore()
    public static let headerName = "X-OmniSpeak-Engine-Token"
    public static let environmentKey = "OMNIVOICE_ENGINE_TOKEN"

    private let lock = NSLock()
    private var storage: String?

    public init(initialToken: String? = ProcessInfo.processInfo.environment[EngineAuthTokenStore.environmentKey]) {
        self.storage = Self.normalized(initialToken)
    }

    public var token: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = Self.normalized(newValue)
            lock.unlock()
        }
    }

    /// Appends `?token=...` when an active token is present so browser-opened dashboard links
    /// can establish an authenticated same-site cookie session.
    public func authenticatedURL(_ url: URL) -> URL {
        guard let token else { return url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "token" }
        items.append(URLQueryItem(name: "token", value: token))
        components.queryItems = items
        return components.url ?? url
    }

    /// Generates a cryptographically random 32-byte (64 hex character) token.
    public static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess {
            return bytes.map { String(format: "%02x", $0) }.joined()
        }
        return UUID().uuidString.replacingOccurrences(of: "-", with: "")
            + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
