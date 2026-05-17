import Foundation
import OmniVoiceCore

enum EngineStartResult {
    case alreadyOnline
    case started
    case stillStarting(logPath: String)
    case unavailable(String)
    case failed(String)

    var detail: String {
        switch self {
        case .alreadyOnline:
            "Engine online"
        case .started:
            "Engine started"
        case .stillStarting(let logPath):
            "Engine is starting. Log: \(logPath)"
        case .unavailable(let message), .failed(let message):
            message
        }
    }
}

@MainActor
final class EngineSupervisor {
    static let shared = EngineSupervisor()

    private let engineClient = EngineClient()
    private var process: Process?
    private var didAttemptStart = false

    func startIfNeeded() async -> EngineStartResult {
        if await isHealthy() {
            return .alreadyOnline
        }

        if process?.isRunning == true {
            return await waitForHealth()
        }

        guard !didAttemptStart else {
            return .unavailable("Engine is offline. Use the dashboard or relaunch OmniVoice after checking the engine log.")
        }
        didAttemptStart = true

        guard let launcherURL = engineLauncherURL() else {
            return .unavailable("Bundled engine launcher was not found.")
        }

        do {
            try launchEngine(using: launcherURL)
        } catch {
            return .failed("Engine launch failed: \(error.localizedDescription)")
        }

        return await waitForHealth()
    }

    func stopStartedProcess() {
        guard let process, process.isRunning else { return }
        process.terminate()
    }

    func restart() async -> EngineStartResult {
        didAttemptStart = false

        if let process, process.isRunning {
            process.terminate()
            for _ in 0..<20 where process.isRunning {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        process = nil

        return await startIfNeeded()
    }

    private func launchEngine(using launcherURL: URL) throws {
        let supportURL = try applicationSupportURL()
        let modelRoot = supportURL.appending(path: "models", directoryHint: .isDirectory)
        let dataURL = supportURL.appending(path: "engine-data", directoryHint: .isDirectory)
        let logURL = supportURL.appending(path: "engine.log")

        try FileManager.default.createDirectory(at: modelRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }

        let logHandle = try FileHandle(forWritingTo: logURL)
        try logHandle.seekToEnd()
        logHandle.write(Data("\n--- OmniVoice engine launch \(Date()) ---\n".utf8))

        var environment = ProcessInfo.processInfo.environment
        environment["OMNIVOICE_APP_SUPPORT_DIR"] = supportURL.path
        environment["OMNIVOICE_MODEL_ROOT"] = modelRoot.path
        environment["OMNIVOICE_PARAKEET_MODEL_DIR"] = modelRoot.appending(path: "parakeet-tdt").path
        environment["OMNIVOICE_CANARY_MODEL_DIR"] = modelRoot.appending(path: "canary-qwen-2.5b").path
        environment["OMNIVOICE_ENGINE_DATA_DIR"] = dataURL.path
        environment["OMNIVOICE_DESKTOP_APP_PATH"] = Bundle.main.bundleURL.path
        environment["OMNIVOICE_INSTALL_ASR"] = environment["OMNIVOICE_INSTALL_ASR"] ?? "1"

        let launched = Process()
        launched.executableURL = launcherURL
        launched.environment = environment
        launched.currentDirectoryURL = launcherURL.deletingLastPathComponent()
        launched.standardOutput = logHandle
        launched.standardError = logHandle
        try launched.run()

        process = launched
    }

    private func waitForHealth() async -> EngineStartResult {
        for _ in 0..<120 {
            if await isHealthy() {
                return .started
            }
            try? await Task.sleep(for: .milliseconds(500))
        }

        return .stillStarting(logPath: (try? applicationSupportURL().appending(path: "engine.log").path) ?? "engine.log")
    }

    private func isHealthy() async -> Bool {
        do {
            _ = try await engineClient.health()
            return true
        } catch {
            return false
        }
    }

    private func engineLauncherURL() -> URL? {
        if let bundled = Bundle.main.resourceURL?.appending(path: "Engine/run-engine-bundled.sh"),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        let repoLauncher = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "scripts/run-engine.sh")
        if FileManager.default.isExecutableFile(atPath: repoLauncher.path) {
            return repoLauncher
        }

        return nil
    }

    private func applicationSupportURL() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let url = baseURL.appending(path: "OmniVoice", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
