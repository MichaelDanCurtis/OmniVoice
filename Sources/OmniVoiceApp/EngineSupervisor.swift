import Darwin
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

    func startIfNeeded(healthAttempts: Int = 120) async -> EngineStartResult {
        if await isHealthy() {
            return .alreadyOnline
        }

        if process?.isRunning == true {
            return await waitForHealth(attempts: healthAttempts)
        }

        guard !didAttemptStart else {
            return .unavailable("Engine is offline. Use the dashboard or relaunch OmniSpeak after checking the engine log.")
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

        return await waitForHealth(attempts: healthAttempts)
    }

    func stopStartedProcess() {
        guard let process, process.isRunning else { return }
        process.terminate()
    }

    func restart(forceExternal: Bool = false, healthAttempts: Int = 120) async -> EngineStartResult {
        didAttemptStart = false

        if let process, process.isRunning {
            process.terminate()
            for _ in 0..<20 where process.isRunning {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        if forceExternal {
            await terminateExternalEngineListeners()
        }
        process = nil

        return await startIfNeeded(healthAttempts: healthAttempts)
    }

    func installCanaryRuntime() async -> EngineStartResult {
        do {
            let supportURL = try applicationSupportURL()
            let runtimeURL = supportURL.appending(path: "engine-runtimes", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: runtimeURL, withIntermediateDirectories: true)
            FileManager.default.createFile(
                atPath: runtimeURL.appending(path: "canary-asr.enabled").path,
                contents: Data("1\n".utf8)
            )
        } catch {
            return .failed("Could not enable Canary runtime install: \(error.localizedDescription)")
        }

        return await restart(forceExternal: true, healthAttempts: 900)
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
        logHandle.write(Data("\n--- OmniSpeak engine launch \(Date()) ---\n".utf8))

        var environment = ProcessInfo.processInfo.environment
        environment["OMNIVOICE_APP_SUPPORT_DIR"] = supportURL.path
        environment["OMNIVOICE_MODEL_ROOT"] = modelRoot.path
        environment["OMNIVOICE_PARAKEET_MODEL_DIR"] = modelRoot.appending(path: "parakeet-tdt").path
        environment["OMNIVOICE_PARAKEET_MLX_MODEL_DIR"] = modelRoot.appending(path: "parakeet-tdt-mlx").path
        environment["OMNIVOICE_WHISPER_MLX_MODEL_DIR"] = modelRoot.appending(path: "whisper-large-v3-turbo-mlx-6bit").path
        environment["OMNIVOICE_CANARY_MODEL_DIR"] = modelRoot.appending(path: "canary-qwen-2.5b").path
        environment["OMNIVOICE_MLX_SORTFORMER_FP16_DIR"] = modelRoot.appending(path: "mlx-sortformer-streaming-fp16").path
        environment["OMNIVOICE_MLX_SORTFORMER_FP32_DIR"] = modelRoot.appending(path: "mlx-sortformer-streaming-fp32").path
        environment["OMNIVOICE_ENGINE_DATA_DIR"] = dataURL.path
        environment["OMNIVOICE_DESKTOP_APP_PATH"] = Bundle.main.bundleURL.path
        environment["OMNIVOICE_INSTALL_ASR"] = environment["OMNIVOICE_INSTALL_ASR"] ?? "1"
        environment["OMNIVOICE_INSTALL_MLX_DIARIZATION"] = environment["OMNIVOICE_INSTALL_MLX_DIARIZATION"] ?? "1"
        environment["OMNIVOICE_INSTALL_MLX_ASR"] = environment["OMNIVOICE_INSTALL_MLX_ASR"] ?? "1"
        environment["OMNIVOICE_INSTALL_CANARY_ASR"] = environment["OMNIVOICE_INSTALL_CANARY_ASR"] ?? (canaryRuntimeInstallIsEnabled(supportURL: supportURL) ? "1" : "0")

        let launched = Process()
        launched.executableURL = launcherURL
        launched.environment = environment
        launched.currentDirectoryURL = launcherURL.deletingLastPathComponent()
        launched.standardOutput = logHandle
        launched.standardError = logHandle
        try launched.run()

        process = launched
    }

    private func waitForHealth(attempts: Int = 120) async -> EngineStartResult {
        for _ in 0..<attempts {
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

    private func canaryRuntimeInstallIsEnabled(supportURL: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: supportURL
                .appending(path: "engine-runtimes", directoryHint: .isDirectory)
                .appending(path: "canary-asr.enabled")
                .path
        )
    }

    private func terminateExternalEngineListeners() async {
        let pids = listeningEnginePIDs()
        for pid in pids where pid != getpid() {
            let command = processCommand(pid: pid)
            guard isOmniVoiceEngineCommand(command) else {
                continue
            }
            kill(pid, SIGTERM)
        }

        for _ in 0..<20 {
            let remaining = listeningEnginePIDs().filter { pids.contains($0) }
            if remaining.isEmpty {
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func listeningEnginePIDs() -> [pid_t] {
        let output = runAndCapture("/usr/sbin/lsof", ["-tiTCP:8765", "-sTCP:LISTEN"])
        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private func processCommand(pid: pid_t) -> String {
        runAndCapture("/bin/ps", ["-p", "\(pid)", "-o", "command="])
    }

    private func isOmniVoiceEngineCommand(_ command: String) -> Bool {
        command.contains("omnivoice_engine.main:app")
            || command.contains("Application Support/OmniSpeak/engine-venv")
            || command.contains("/OmniSpeak/engine/.venv/bin/uvicorn")
            || command.contains("scripts/run-engine.sh")
    }

    private func runAndCapture(_ executable: String, _ arguments: [String]) -> String {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(decoding: data, as: UTF8.self)
        } catch {
            return ""
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
        let url = baseURL.appending(path: "OmniSpeak", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
