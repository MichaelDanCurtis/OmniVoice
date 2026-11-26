import Foundation

/// Lightweight native JSON-RPC 2.0 MCP-over-stdio client for `cua-driver`
/// (https://cua.ai/cua-driver) and compatible computer-use MCP servers.
actor CuaMCPClient {
    struct ToolDefinition: Equatable, Sendable {
        let name: String
        let description: String
        let inputSchemaJSON: String
    }

    enum ConnectionState: Equatable, Sendable {
        case disconnected
        case connecting
        case connected(toolCount: Int, toolNames: [String])
        case notInstalled(command: String)
        case failed(String)

        var label: String {
            switch self {
            case .disconnected: "MCP Disconnected"
            case .connecting: "Connecting to cua-driver…"
            case .connected(let count, _): "cua-driver MCP · \(count) tools"
            case .notInstalled(let cmd): "\(cmd) not installed"
            case .failed(let msg): "MCP Error: \(msg)"
            }
        }

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    enum MCPError: LocalizedError {
        case notConnected
        case binaryNotFound(String)
        case protocolError(String)
        case timeout

        var errorDescription: String? {
            switch self {
            case .notConnected: "cua-driver MCP is not connected."
            case .binaryNotFound(let cmd): "`\(cmd)` was not found on your PATH. Install cua-driver from https://cua.ai/cua-driver."
            case .protocolError(let msg): "MCP error: \(msg)"
            case .timeout: "cua-driver MCP timed out."
            }
        }
    }

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var nextRequestID = 1
    private var pendingContinuations: [Int: CheckedContinuation<Data, Error>] = [:]
    private var lineBuffer = Data()
    private(set) var tools: [ToolDefinition] = []
    private(set) var state: ConnectionState = .disconnected

    func connect(commandLine: String = "cua-driver") async -> ConnectionState {
        disconnect()
        state = .connecting

        let tokens = commandLine
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map(String.init)
        let binaryName = tokens.first ?? "cua-driver"
        let explicitArgs = Array(tokens.dropFirst())

        guard let resolvedPath = Self.resolveBinary(binaryName) else {
            state = .notInstalled(command: binaryName)
            return state
        }

        // cua-driver serves MCP over stdio via `cua-driver` or `cua-driver mcp`
        let candidateArgLists: [[String]] = explicitArgs.isEmpty
            ? [["mcp"], []]
            : [explicitArgs]

        var lastError = "Failed to initialize MCP handshake"
        for args in candidateArgLists {
            do {
                try startSubprocess(executablePath: resolvedPath, arguments: args)
                _ = try await sendRequest(
                    method: "initialize",
                    params: [
                        "protocolVersion": "2024-11-05",
                        "capabilities": [String: Any](),
                        "clientInfo": ["name": "OmniSpeak", "version": "2.0"],
                    ]
                )
                try sendNotification(method: "notifications/initialized", params: nil)
                let toolsData = try await sendRequest(method: "tools/list", params: [:])
                let toolsResult = (try? JSONSerialization.jsonObject(with: toolsData) as? [String: Any]) ?? [:]
                let parsedTools = Self.parseTools(from: toolsResult)
                self.tools = parsedTools
                self.state = .connected(toolCount: parsedTools.count, toolNames: parsedTools.map(\.name))
                return self.state
            } catch {
                lastError = error.localizedDescription
                disconnect()
            }
        }

        state = .failed(lastError)
        return state
    }

    func disconnect() {
        for (_, cont) in pendingContinuations {
            cont.resume(throwing: MCPError.notConnected)
        }
        pendingContinuations.removeAll()
        if let stdoutPipe {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
        }
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        lineBuffer.removeAll()
        tools = []
        state = .disconnected
    }

    func callTool(name: String, argumentsJSON: String = "{}") async throws -> String {
        guard state.isConnected, process?.isRunning == true else {
            throw MCPError.notConnected
        }
        let args: [String: Any]
        if let data = argumentsJSON.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            args = parsed
        } else {
            args = [:]
        }
        let resultData = try await sendRequest(
            method: "tools/call",
            params: [
                "name": name,
                "arguments": args,
            ]
        )
        let result = (try? JSONSerialization.jsonObject(with: resultData) as? [String: Any]) ?? [:]
        if let content = result["content"] as? [[String: Any]] {
            let texts = content.compactMap { item -> String? in
                if let text = item["text"] as? String { return text }
                if let type = item["type"] as? String, type == "image" { return "[screenshot captured]" }
                return nil
            }
            if !texts.isEmpty {
                return texts.joined(separator: "\n")
            }
        }
        if let str = String(data: resultData, encoding: .utf8), !str.isEmpty {
            return str
        }
        return "Done"
    }

    func toolsPromptSummary() -> String {
        tools.prefix(20).map { tool in
            "- \(tool.name): \(tool.description) | schema: \(tool.inputSchemaJSON)"
        }.joined(separator: "\n")
    }

    // MARK: - Subprocess & JSON-RPC Framing

    private func startSubprocess(executablePath: String, arguments: [String]) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executablePath)
        proc.arguments = arguments

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        // Drain stderr so the server never blocks
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { [weak self] in
                await self?.consumeStdoutData(data)
            }
        }

        try proc.run()
        self.process = proc
        self.stdinPipe = inPipe
        self.stdoutPipe = outPipe
    }

    private func consumeStdoutData(_ data: Data) {
        lineBuffer.append(data)
        while let newlineIdx = lineBuffer.firstIndex(of: 0x0A) {
            let lineData = lineBuffer.subdata(in: 0..<newlineIdx)
            lineBuffer.removeSubrange(0...newlineIdx)
            guard !lineData.isEmpty,
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let idNum = obj["id"] as? Int,
                  let cont = pendingContinuations.removeValue(forKey: idNum) else {
                continue
            }
            if let errorDict = obj["error"] as? [String: Any] {
                let message = (errorDict["message"] as? String) ?? "Unknown MCP error"
                cont.resume(throwing: MCPError.protocolError(message))
            } else if let result = obj["result"],
                      let resultData = try? JSONSerialization.data(withJSONObject: result) {
                cont.resume(returning: resultData)
            } else {
                cont.resume(returning: Data("{}".utf8))
            }
        }
    }

    private func sendRequest(method: String, params: [String: Any]) async throws -> Data {
        guard let stdinPipe, process?.isRunning == true else {
            throw MCPError.notConnected
        }
        let reqID = nextRequestID
        nextRequestID += 1

        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": reqID,
            "method": method,
            "params": params,
        ]
        var encoded = try JSONSerialization.data(withJSONObject: payload)
        encoded.append(0x0A)

        return try await withCheckedThrowingContinuation { continuation in
            pendingContinuations[reqID] = continuation
            do {
                try stdinPipe.fileHandleForWriting.write(contentsOf: encoded)
            } catch {
                pendingContinuations.removeValue(forKey: reqID)
                continuation.resume(throwing: error)
                return
            }

            Task { [weak self] in
                try? await Task.sleep(for: .seconds(12))
                await self?.timeoutRequestIfPending(reqID)
            }
        }
    }

    private func timeoutRequestIfPending(_ reqID: Int) {
        if let cont = pendingContinuations.removeValue(forKey: reqID) {
            cont.resume(throwing: MCPError.timeout)
        }
    }

    private func sendNotification(method: String, params: [String: Any]?) throws {
        guard let stdinPipe, process?.isRunning == true else {
            throw MCPError.notConnected
        }
        var payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
        ]
        if let params {
            payload["params"] = params
        }
        var encoded = try JSONSerialization.data(withJSONObject: payload)
        encoded.append(0x0A)
        try stdinPipe.fileHandleForWriting.write(contentsOf: encoded)
    }

    private static func parseTools(from result: [String: Any]) -> [ToolDefinition] {
        guard let rawTools = result["tools"] as? [[String: Any]] else { return [] }
        return rawTools.compactMap { dict in
            guard let name = dict["name"] as? String else { return nil }
            let description = (dict["description"] as? String) ?? ""
            let schemaJSON: String
            if let schema = dict["inputSchema"],
               let data = try? JSONSerialization.data(withJSONObject: schema),
               let str = String(data: data, encoding: .utf8) {
                schemaJSON = String(str.prefix(260))
            } else {
                schemaJSON = "{}"
            }
            return ToolDefinition(name: name, description: description, inputSchemaJSON: schemaJSON)
        }
    }

    private static func resolveBinary(_ nameOrPath: String) -> String? {
        if nameOrPath.contains("/"), FileManager.default.isExecutableFile(atPath: nameOrPath) {
            return nameOrPath
        }
        guard nameOrPath.range(of: #"^[a-zA-Z0-9._-]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = ["-lc", "command -v \(nameOrPath)"]
        let outPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        p.waitUntilExit()
        return (!out.isEmpty && FileManager.default.isExecutableFile(atPath: out)) ? out : nil
    }
}
