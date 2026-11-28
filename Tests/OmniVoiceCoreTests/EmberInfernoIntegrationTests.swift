import Foundation
import XCTest
@testable import OmniVoiceCore

final class EmberInfernoIntegrationTests: XCTestCase {
    func testEmberEndpointsBuildAndPreferencesRoundTrip() throws {
        var prefs = OmniVoicePreferences.defaults
        XCTAssertFalse(prefs.emberDelegation.enabled)
        XCTAssertFalse(prefs.emberDelegation.isConfigured)

        prefs.emberDelegation = EmberDelegationConfiguration(
            enabled: true,
            serverURL: "https://fuego.curtishome.org/",
            companyID: "comp-123",
            agentID: "ember-1",
            infernoAgentID: "antigravity"
        )
        XCTAssertTrue(prefs.emberDelegation.isConfigured)
        XCTAssertEqual(
            prefs.emberDelegation.conversationEndpointURL?.absoluteString,
            "https://fuego.curtishome.org/api/companies/comp-123/ember/ember-1"
        )
        XCTAssertEqual(
            prefs.emberDelegation.messagesEndpointURL?.absoluteString,
            "https://fuego.curtishome.org/api/companies/comp-123/ember/ember-1/messages"
        )

        let encoded = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(OmniVoicePreferences.self, from: encoded)
        XCTAssertEqual(decoded.emberDelegation, prefs.emberDelegation)

        let convertedDecoded = try EngineCoding.decoder.decode(OmniVoicePreferences.self, from: encoded)
        XCTAssertEqual(convertedDecoded.emberDelegation, prefs.emberDelegation)
    }

    func testEmberClampsBodyTo4096UTF8Bytes() {
        let longText = String(repeating: "a", count: 5_000)
        let clamped = EmberDelegationConfiguration.clampedMessageBody(longText)
        XCTAssertLessThanOrEqual(clamped.utf8.count, 4_096)
        XCTAssertTrue(clamped.hasSuffix("…"))
    }

    func testEmberResponseParserExtractsNewAssistantReplyAndImmediateReply() {
        let snapshotJSON = """
        {
          "messages": [
            { "id": "m1", "role": "assistant", "body": "Earlier answer" },
            { "id": "m2", "role": "user", "body": "Check my deployments" },
            { "id": "m3", "role": "assistant", "body": "All 3 services are healthy." }
          ],
          "activeTurn": null
        }
        """.data(using: .utf8)!

        let snapshot = EmberResponseParser.parseSnapshot(from: snapshotJSON)
        XCTAssertEqual(snapshot?.messages.count, 3)
        XCTAssertEqual(
            snapshot?.newestAssistantReply(excludingIDs: ["m1"])?.body,
            "All 3 services are healthy."
        )

        let immediateJSON = #"{"reply":"Done — restarted the staging worker."}"#.data(using: .utf8)!
        XCTAssertEqual(
            EmberResponseParser.parseImmediateReply(from: immediateJSON),
            "Done — restarted the staging worker."
        )
    }

    func testInfernoCLIParserParsesInstalledAgentsAndLaunchReceipt() {
        let installedJSON = """
        {
          "ok": true,
          "result": {
            "agents": [
              { "id": "claude", "name": "Claude", "default": false },
              { "id": "antigravity", "name": "Antigravity", "default": true }
            ]
          }
        }
        """.data(using: .utf8)!

        let agents = InfernoCLIParser.parseInstalledAgents(from: installedJSON)
        XCTAssertEqual(agents.count, 2)
        XCTAssertEqual(agents[1].id, "antigravity")
        XCTAssertTrue(agents[1].isDefault)

        let launchJSON = """
        {
          "ok": true,
          "result": {
            "sessionId": "sess-99",
            "outcome": { "kind": "chat" },
            "receipt": { "detail": "Launched in chat" }
          }
        }
        """.data(using: .utf8)!
        let receipt = InfernoCLIParser.parseLaunchReceipt(from: launchJSON)
        XCTAssertEqual(receipt?.sessionID, "sess-99")
        XCTAssertEqual(receipt?.outcomeKind, "chat")

        XCTAssertTrue(AgentRegistry.defaultBuiltIns.contains(where: { $0.id == "inferno" }))
    }

    func testEmberVoiceCommandParserMatchesSummonAndGuardsProse() {
        // Exact summons (including polite lead-ins and punctuation)
        XCTAssertEqual(EmberVoiceCommandParser.parse("Ember"), EmberSummonCommand(initialMessage: nil))
        XCTAssertEqual(EmberVoiceCommandParser.parse("Ember."), EmberSummonCommand(initialMessage: nil))
        XCTAssertEqual(EmberVoiceCommandParser.parse("Hey Ember!"), EmberSummonCommand(initialMessage: nil))
        XCTAssertEqual(EmberVoiceCommandParser.parse("Call Ember."), EmberSummonCommand(initialMessage: nil))
        XCTAssertEqual(EmberVoiceCommandParser.parse("Talk to Ember"), EmberSummonCommand(initialMessage: nil))
        XCTAssertEqual(EmberVoiceCommandParser.parse("Please, can you talk to Ember?"), EmberSummonCommand(initialMessage: nil))
        XCTAssertEqual(EmberVoiceCommandParser.parse("Bring up the Ember agent."), EmberSummonCommand(initialMessage: nil))
        XCTAssertEqual(EmberVoiceCommandParser.parse("Open Ember"), EmberSummonCommand(initialMessage: nil))

        // Summon with immediate prompt
        XCTAssertEqual(
            EmberVoiceCommandParser.parse("Call Ember, check my servers"),
            EmberSummonCommand(initialMessage: "check my servers")
        )
        XCTAssertEqual(
            EmberVoiceCommandParser.parse("Talk to Ember about my morning briefing"),
            EmberSummonCommand(initialMessage: "about my morning briefing")
        )
        XCTAssertEqual(
            EmberVoiceCommandParser.parse("Hey Ember what's on my calendar"),
            EmberSummonCommand(initialMessage: "what's on my calendar")
        )
        XCTAssertEqual(
            EmberVoiceCommandParser.parse("Ember, summarize my latest deployments"),
            EmberSummonCommand(initialMessage: "summarize my latest deployments")
        )
        XCTAssertEqual(
            EmberVoiceCommandParser.parse("Open Ember and check CPU usage"),
            EmberSummonCommand(initialMessage: "check CPU usage")
        )

        // Must NOT hijack inline Ask AI ("ask ember …") or normal prose mentioning Ember
        XCTAssertNil(EmberVoiceCommandParser.parse("Ask Ember what time it is"))
        XCTAssertNil(EmberVoiceCommandParser.parse("Ember is looking great today"))
        XCTAssertNil(EmberVoiceCommandParser.parse("An ember fell out of the fireplace"))
        XCTAssertNil(EmberVoiceCommandParser.parse("Ember temperature was very high"))
    }

    func testEmberResponseParserHandlesLocalEmberEnginePayloads() {
        let localOK = """
        {
          "ok": true,
          "message": {
            "role": "assistant",
            "text": "All 4 nodes are healthy and ready."
          }
        }
        """.data(using: .utf8)!
        XCTAssertEqual(
            EmberResponseParser.parseImmediateReply(from: localOK),
            "All 4 nodes are healthy and ready."
        )
        XCTAssertNil(EmberResponseParser.parseError(from: localOK))

        let localErr = #"{"ok":false,"error":"Cloud Ember HTTP 502"}"#.data(using: .utf8)!
        XCTAssertEqual(EmberResponseParser.parseError(from: localErr), "Cloud Ember HTTP 502")
    }
}
