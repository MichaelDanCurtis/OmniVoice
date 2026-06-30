import XCTest
@testable import OmniVoiceCore

final class DictionaryEntryTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let entry = DictionaryEntry(
            id: "abc",
            canonical: "Figma",
            aliases: ["figma"],
            source: .learned,
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(DictionaryEntry.self, from: data)
        XCTAssertEqual(decoded, entry)
    }

    func testManualConvenienceInit() {
        let entry = DictionaryEntry(manualTerm: "Figma", at: Date(timeIntervalSince1970: 5))
        XCTAssertEqual(entry.canonical, "Figma")
        XCTAssertEqual(entry.source, .manual)
        XCTAssertTrue(entry.aliases.isEmpty)
        XCTAssertTrue(entry.enabled)
        XCTAssertEqual(entry.createdAt, entry.updatedAt)
    }
}
