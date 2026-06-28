import Foundation

/// Resolves a CLI binary path for an `AgentDescriptor`.
///
/// Resolution order:
/// 1. If `descriptor.binaryPath` is set and the file is executable, return it directly.
/// 2. Otherwise, run `$SHELL -lc "command -v <binaryName>"` to locate the binary on the
///    login-shell PATH (picks up user profiles, Homebrew, nvm, pyenv, etc.).
/// 3. Cache successful lookups keyed by `binaryName` so repeated calls are fast.
public enum ExecutableResolver {

    // MARK: - Concurrency-safe cache

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String: String] = [:]

        func get(_ key: String) -> String? {
            lock.lock(); defer { lock.unlock() }
            return storage[key]
        }

        func set(_ key: String, value: String) {
            lock.lock(); defer { lock.unlock() }
            storage[key] = value
        }
    }

    private static let cache = Cache()

    // MARK: - Public API

    /// Returns the resolved executable path, or `nil` if the binary cannot be found.
    ///
    /// - Note: This method is synchronous and spawns a login shell subprocess on cache miss.
    ///   Do not call it on the main actor or inside a `Task` body without dispatching to a
    ///   background thread first.
    public static func resolve(_ descriptor: AgentDescriptor) -> String? {
        // 1. Explicit path wins if the file is executable.
        if let p = descriptor.binaryPath, FileManager.default.isExecutableFile(atPath: p) {
            return p
        }

        // 2. Return cached login-shell lookup.
        if let hit = cache.get(descriptor.binaryName) { return hit }

        // 3. Reject binary names that contain shell metacharacters to prevent injection.
        //    Valid names are restricted to alphanumeric chars, hyphens, underscores, and dots.
        guard descriptor.binaryName.range(of: #"^[a-zA-Z0-9._-]+$"#, options: .regularExpression) != nil else {
            return nil
        }

        // 4. Ask the login shell for the binary location.
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = ["-lc", "command -v \(descriptor.binaryName)"]
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        p.standardOutput = stdoutPipe
        p.standardError = stderrPipe
        do { try p.run() } catch { return nil }
        // Drain stderr concurrently to prevent pipe-buffer deadlock before waiting.
        let stderrHandle = stderrPipe.fileHandleForReading
        let stderrQueue = DispatchQueue(label: "ExecutableResolver.stderr")
        stderrQueue.async { _ = stderrHandle.readDataToEndOfFile() }
        p.waitUntilExit()

        let out = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !out.isEmpty, FileManager.default.isExecutableFile(atPath: out) else { return nil }

        cache.set(descriptor.binaryName, value: out)
        return out
    }
}
