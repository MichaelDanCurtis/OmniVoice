import XCTest
@testable import OmniVoiceCore

final class ConversationAssistCardTests: XCTestCase {
    func testPinnedStatusRoundTrips() throws {
        let card = ConversationAssistCard(
            id: "card-1",
            sessionID: "session-1",
            kind: .timeZone,
            title: "Time Zone Assist",
            body: "3:00 PM Pacific = 6:00 PM Eastern.",
            status: .pinned,
            createdAt: "2026-05-17T08:00:00Z"
        )

        let data = try EngineCoding.encoder.encode(card)
        let decoded = try EngineCoding.decoder.decode(ConversationAssistCard.self, from: data)

        XCTAssertEqual(decoded.status, .pinned)
        XCTAssertEqual(decoded.copyText, "3:00 PM Pacific = 6:00 PM Eastern.")
    }
}
