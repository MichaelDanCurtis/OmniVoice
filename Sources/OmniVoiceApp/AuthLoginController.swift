import AppKit
import Foundation
import Network

/// Backend endpoints. Populated once the WorkOS app + Cloudflare Worker are
/// provisioned (see `docs/ACCOUNT_ENTITLEMENT_RUNBOOK.md`). While `nil`, sign-in
/// throws `AuthError.notConfigured` and the app runs on the stub entitlement provider.
enum WorkerConfig {
    /// Base URL of the deployed Cloudflare Worker (e.g. `https://api.omnivoice.app`).
    static let baseURL: URL? = nil
    /// WorkOS client id for the AuthKit application.
    static let workosClientID: String? = nil
    /// WorkOS hosted-login authorization endpoint.
    static let workosAuthorizationURL = URL(string: "https://api.workos.com/user_management/authorize")!
}

enum AuthError: LocalizedError, Equatable {
    case notConfigured
    case stateMismatch
    case missingCode
    case callbackFailed(Int)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Sign-in isn’t configured yet. The account backend has not been set up."
        case .stateMismatch:
            return "Sign-in was interrupted (state mismatch). Please try again."
        case .missingCode:
            return "The sign-in response was missing an authorization code."
        case .callbackFailed(let status):
            return "The sign-in server returned an error (status \(status))."
        case .timedOut:
            return "Sign-in timed out. Please try again."
        }
    }
}

/// Drives the loopback sign-in flow: open the WorkOS hosted login in the browser,
/// catch the redirect on a throwaway `127.0.0.1` listener, then exchange the code
/// for a session via the Worker and store it in the Keychain.
@MainActor
final class AuthLoginController {
    private let store: AuthSessionStore
    private let session: URLSession
    /// Invoked after a successful sign-out so the app can clear its entitlement cache.
    var onSignOut: (() -> Void)?

    init(store: AuthSessionStore = AuthSessionStore(), session: URLSession = .shared) {
        self.store = store
        self.session = session
    }

    var currentSession: AuthSession? { store.load() }

    func signIn(timeout: TimeInterval = 120) async throws -> AuthSession {
        guard let clientID = WorkerConfig.workosClientID, let workerBase = WorkerConfig.baseURL else {
            throw AuthError.notConfigured
        }

        let listener = try LoopbackAuthListener()
        defer { listener.stop() }

        let port = try await listener.start()
        let redirectURI = "http://127.0.0.1:\(port)/callback"
        let state = UUID().uuidString

        guard let authURL = Self.authorizationURL(clientID: clientID, redirectURI: redirectURI, state: state) else {
            throw AuthError.notConfigured
        }
        NSWorkspace.shared.open(authURL)

        let query = try await listener.waitForCallback(timeout: timeout)
        guard query["state"] == state else { throw AuthError.stateMismatch }
        guard let code = query["code"], !code.isEmpty else { throw AuthError.missingCode }

        let authSession = try await exchangeCode(code, redirectURI: redirectURI, workerBase: workerBase)
        try store.save(authSession)
        return authSession
    }

    func signOut() {
        try? store.delete()
        onSignOut?()
    }

    /// Builds the WorkOS AuthKit authorization URL for the hosted login.
    static func authorizationURL(clientID: String, redirectURI: String, state: String) -> URL? {
        var components = URLComponents(url: WorkerConfig.workosAuthorizationURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "provider", value: "authkit"),
            URLQueryItem(name: "state", value: state),
        ]
        return components?.url
    }

    private func exchangeCode(_ code: String, redirectURI: String, workerBase: URL) async throws -> AuthSession {
        var request = URLRequest(url: workerBase.appendingPathComponent("auth/callback"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["code": code, "redirectUri": redirectURI])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AuthError.callbackFailed((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(AuthSession.self, from: data)
    }
}

/// A single-use HTTP listener bound to `127.0.0.1` on an ephemeral port. It serves
/// exactly one GET (the OAuth redirect), returns its query items, and shuts down.
///
/// `@unchecked Sendable`: all Network.framework callbacks are delivered on the
/// private serial `queue`, and the resume-once flags below are only touched from
/// those callbacks, so the mutable state is effectively serialized.
private final class LoopbackAuthListener: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.omnivoice.auth.loopback")
    private var connection: NWConnection?
    private var startResumed = false
    private var callbackResumed = false

    init() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: params)
    }

    /// Starts listening and resolves with the bound loopback port.
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [self] state in
                switch state {
                case .ready:
                    guard !startResumed, let port = listener.port else { return }
                    startResumed = true
                    continuation.resume(returning: port.rawValue)
                case .failed(let error):
                    guard !startResumed else { return }
                    startResumed = true
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    /// Awaits the browser redirect and returns its query items, timing out if the
    /// user never completes sign-in.
    func waitForCallback(timeout: TimeInterval) async throws -> [String: String] {
        try await withThrowingTaskGroup(of: [String: String].self) { group in
            group.addTask { try await self.receiveOneRequest() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw AuthError.timedOut
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func receiveOneRequest() async throws -> [String: String] {
        try await withCheckedThrowingContinuation { continuation in
            listener.newConnectionHandler = { [self] connection in
                self.connection = connection
                connection.start(queue: queue)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [self] data, _, _, error in
                    if let error {
                        finishCallback(continuation, .failure(error))
                        return
                    }
                    guard let data, let request = String(data: data, encoding: .utf8) else {
                        finishCallback(continuation, .failure(AuthError.missingCode))
                        return
                    }
                    Self.sendClosePage(on: connection)
                    finishCallback(continuation, .success(Self.parseQuery(fromRequest: request)))
                }
            }
        }
    }

    private func finishCallback(
        _ continuation: CheckedContinuation<[String: String], Error>,
        _ result: Result<[String: String], Error>
    ) {
        guard !callbackResumed else { return }
        callbackResumed = true
        continuation.resume(with: result)
    }

    /// Parses the query items out of the request line ("GET /callback?… HTTP/1.1").
    static func parseQuery(fromRequest request: String) -> [String: String] {
        let firstLine = request.components(separatedBy: "\r\n").first ?? request
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2, let components = URLComponents(string: "http://127.0.0.1" + parts[1]) else {
            return [:]
        }
        var items: [String: String] = [:]
        for item in components.queryItems ?? [] {
            items[item.name] = item.value
        }
        return items
    }

    private static func sendClosePage(on connection: NWConnection) {
        let body = """
        <html><body style="font-family: -apple-system, sans-serif; text-align: center; padding-top: 80px;">\
        <h2>OmniVoice</h2><p>You’re signed in. You can close this tab and return to the app.</p></body></html>
        """
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
            + body
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    func stop() {
        connection?.cancel()
        listener.cancel()
    }
}
