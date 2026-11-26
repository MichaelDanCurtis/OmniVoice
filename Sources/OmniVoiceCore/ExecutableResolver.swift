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
        p.standardOutput = stdoutPipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let out = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        p.waitUntilExit()

        guard !out.isEmpty, FileManager.default.isExecutableFile(atPath: out) else { return nil }

        cache.set(descriptor.binaryName, value: out)
        return out
    }

    /// Scans the user's login-shell `PATH` in a single shell invocation for all installed
    /// AI agent CLIs from `catalog`, populating the resolver cache for every hit.
    ///
    /// - Note: Synchronous subprocess call — invoke off the main actor.
    public static func discoverInstalledAgents(
        from catalog: [AgentDescriptor] = AgentRegistry.defaultBuiltIns
    ) -> [DiscoveredAgent] {
        let safeDescriptors = catalog.filter {
            $0.binaryName.range(of: #"^[a-zA-Z0-9._-]+$"#, options: .regularExpression) != nil
        }
        guard !safeDescriptors.isEmpty else { return [] }

        var resolvedByBinary: [String: String] = [:]
        var binariesToProbe: [String] = []

        for descriptor in safeDescriptors {
            if let explicit = descriptor.binaryPath, FileManager.default.isExecutableFile(atPath: explicit) {
                resolvedByBinary[descriptor.binaryName] = explicit
            } else if let cached = cache.get(descriptor.binaryName), FileManager.default.isExecutableFile(atPath: cached) {
                resolvedByBinary[descriptor.binaryName] = cached
            } else if !binariesToProbe.contains(descriptor.binaryName) {
                binariesToProbe.append(descriptor.binaryName)
            }
        }

        if !binariesToProbe.isEmpty {
            let binaryList = binariesToProbe.joined(separator: " ")
            let script = """
            for b in \(binaryList); do
              p=$(command -v "$b" 2>/dev/null || true)
              if [ -n "$p" ] && [ -x "$p" ]; then
                printf '%s\\t%s\\n' "$b" "$p"
              fi
            done
            """
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: shell)
            process.arguments = ["-lc", script]
            let stdoutPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = FileHandle.nullDevice
            if (try? process.run()) != nil {
                let output = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                process.waitUntilExit()
                for line in output.split(whereSeparator: \.isNewline) {
                    let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
                    guard parts.count == 2 else { continue }
                    let binary = parts[0]
                    let path = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                        resolvedByBinary[binary] = path
                        cache.set(binary, value: path)
                    }
                }
            }
        }

        return safeDescriptors.compactMap { descriptor in
            guard let path = resolvedByBinary[descriptor.binaryName] else { return nil }
            return DiscoveredAgent(descriptor: descriptor, resolvedPath: path)
        }
    }
}
