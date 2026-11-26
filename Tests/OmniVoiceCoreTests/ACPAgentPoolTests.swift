import Foundation
import XCTest
@testable import OmniVoiceCore

final class ACPAgentPoolTests: XCTestCase {
    private func makeMockACPDescriptor(startupDelaySeconds: Double = 0.05) throws -> (AgentDescriptor, URL) {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mock-acp-\(UUID().uuidString).py")
        let script = """
        #!/usr/bin/env python3
        import json, sys, time

        startup_delay = \(startupDelaySeconds)
        session_counter = 0
        current_model = "heavy-default"

        for raw in sys.stdin:
            raw = raw.strip()
            if not raw:
                continue
            msg = json.loads(raw)
            method = msg.get("method")
            req_id = msg.get("id")
            params = msg.get("params") or {}

            if method == "initialize":
                if startup_delay > 0:
                    time.sleep(startup_delay)
                out = {"jsonrpc": "2.0", "id": req_id, "result": {"protocolVersion": 1}}
                print(json.dumps(out), flush=True)
            elif method == "session/new":
                session_counter += 1
                out = {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {
                        "sessionId": f"sess-{session_counter}",
                        "models": {
                            "currentModelId": current_model,
                            "availableModels": [
                                {"modelId": "heavy-default", "name": "Heavy"},
                                {"modelId": "gemini-3.8-flash-low", "name": "Flash Low"},
                            ],
                        },
                    },
                }
                print(json.dumps(out), flush=True)
            elif method == "session/set_model":
                current_model = params.get("modelId", current_model)
                print(json.dumps({"jsonrpc": "2.0", "id": req_id, "result": {}}), flush=True)
            elif method == "session/prompt":
                sid = params.get("sessionId", "sess-1")
                prompt_items = params.get("prompt") or []
                text = prompt_items[0].get("text", "") if prompt_items else ""
                reply = "OK" if "Reply OK now" in text else f"[{current_model}] {text.upper()}"
                mid = max(1, len(reply) // 2)
                for piece in (reply[:mid], reply[mid:]):
                    if not piece:
                        continue
                    notif = {
                        "jsonrpc": "2.0",
                        "method": "session/update",
                        "params": {
                            "sessionId": sid,
                            "update": {
                                "sessionUpdate": "agent_message_chunk",
                                "content": {"type": "text", "text": piece},
                            },
                        },
                    }
                    print(json.dumps(notif), flush=True)
                print(json.dumps({"jsonrpc": "2.0", "id": req_id, "result": {"stopReason": "end_turn"}}), flush=True)
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        let descriptor = AgentDescriptor(
            id: "mock-acp",
            displayName: "Mock ACP",
            keywords: ["mock"],
            binaryName: "python3",
            binaryPath: "/usr/bin/python3",
            invocation: .args([scriptURL.path]),
            streamFormat: .plainText,
            acpArgs: ["-u", scriptURL.path],
            acpFastModelPreference: ["gemini-3.8-flash-low", "flash"]
        )
        return (descriptor, scriptURL)
    }

    func testZeroWaitColdStartSkipsEditingWhileWarmingThenRunsHot() async throws {
        let (descriptor, scriptURL) = try makeMockACPDescriptor(startupDelaySeconds: 0.45)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let pool = ACPAgentPool()
        defer { Task { await pool.shutdownAll() } }

        // 1. First call on a cold ACP worker must return nil immediately (<0.2s)
        //    instead of blocking on the 0.45s cold start.
        let t0 = Date()
        let coldResult = await pool.promptIfReady(descriptor, prompt: "hello world", purpose: .cleanup)
        let elapsed = Date().timeIntervalSince(t0)
        XCTAssertNil(coldResult)
        XCTAssertLessThan(elapsed, 0.25)

        // State should now be warming in background.
        let warmingState = await pool.state(for: descriptor.id, purpose: .cleanup)
        XCTAssertTrue(warmingState.isWarming || warmingState.isReady)

        // 2. Wait briefly for background warm-up to finish.
        for _ in 0..<40 {
            let st = await pool.state(for: descriptor.id, purpose: .cleanup)
            if st.isReady { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let readyState = await pool.state(for: descriptor.id, purpose: .cleanup)
        XCTAssertEqual(readyState, .ready(modelID: "gemini-3.8-flash-low"))

        // 3. Subsequent dictation runs hot immediately on the fast model!
        let hotResult = await pool.promptIfReady(descriptor, prompt: "hello neon", purpose: .cleanup)
        XCTAssertEqual(hotResult, "[gemini-3.8-flash-low] HELLO NEON")

        // 4. Shutdown drops worker cleanly back to idle.
        await pool.shutdownExcept(agentIDs: [])
        let afterShutdown = await pool.state(for: descriptor.id, purpose: .cleanup)
        XCTAssertEqual(afterShutdown, .idle)
    }

    func testInteractivePromptAwaitsWarmupAndStreamsChunks() async throws {
        let (descriptor, scriptURL) = try makeMockACPDescriptor(startupDelaySeconds: 0.1)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let pool = ACPAgentPool()
        defer { Task { await pool.shutdownAll() } }

        let collector = ChunkBox()
        let reply = try await pool.promptWaitingForWarmup(
            descriptor,
            prompt: "ask neon",
            purpose: .interactive,
            timeoutSeconds: 5.0
        ) { chunk in
            collector.append(chunk)
        }
        XCTAssertEqual(reply, "[heavy-default] ASK NEON")
        XCTAssertEqual(collector.value, "[heavy-default] ASK NEON")
    }

    func testFastModelSelectionMatchesInPreferenceOrder() {
        let available = ["gemini-4-neon-high", "gemini-3.8-flash-high", "gemini-3.8-flash-low"]
        XCTAssertEqual(
            ACPAgentPool.pickFastModel(available: available, preferences: ["gemini-3.8-flash-low", "flash"]),
            "gemini-3.8-flash-low"
        )
        XCTAssertEqual(
            ACPAgentPool.pickFastModel(available: available, preferences: ["nonexistent", "flash"]),
            "gemini-3.8-flash-high"
        )
        XCTAssertNil(ACPAgentPool.pickFastModel(available: available, preferences: ["claude"]))
    }

    func testBuiltInRegistryMarksACPCapableAgents() {
        let registry = AgentRegistry(custom: [])
        let agy = registry.all.first(where: { $0.id == "antigravity" })
        XCTAssertEqual(agy?.supportsACP, true)
        XCTAssertEqual(agy?.acpArgs?.first, "acp")

        let copilot = registry.all.first(where: { $0.id == "copilot" })
        XCTAssertEqual(copilot?.supportsACP, true)

        let claude = registry.all.first(where: { $0.id == "claude" })
        XCTAssertEqual(claude?.supportsACP, false)
    }
}

private final class ChunkBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""
    func append(_ s: String) { lock.lock(); storage += s; lock.unlock() }
    var value: String { lock.lock(); defer { lock.unlock() }; return storage }
}
