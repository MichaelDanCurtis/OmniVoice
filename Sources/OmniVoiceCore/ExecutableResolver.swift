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
    public static func resolve(_ descriptor: AgentDescriptor) -> String? {
        // 1. Explicit path wins if the file is executable.
        if let p = descriptor.binaryPath, FileManager.default.isExecutableFile(atPath: p) {
            return p
        }

        // 2. Return cached login-shell lookup.
        if let hit = cache.get(descriptor.binaryName) { return hit }

        // 3. Ask the login shell for the binary location.
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = ["-lc", "command -v \(descriptor.binaryName)"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()

        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !out.isEmpty, FileManager.default.isExecutableFile(atPath: out) else { return nil }

        cache.set(descriptor.binaryName, value: out)
        return out
    }
}
