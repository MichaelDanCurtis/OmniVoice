import XCTest
@testable import OmniVoiceCore

final class DictionaryStoreTests: XCTestCase {
    func testUpsertCreatesLearnedEntry() {
        let (entries, id) = DictionaryStore.upsert(
            LearnedCorrection(from: "figma", to: "Figma"),
            into: [], now: Date(timeIntervalSince1970: 1), makeID: { "id-1" }
        )
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].canonical, "Figma")
        XCTAssertEqual(entries[0].aliases, ["figma"])
        XCTAssertEqual(entries[0].source, .learned)
        XCTAssertEqual(id, "id-1")
    }

    func testUpsertMergesAliasIntoExisting() {
        let first = DictionaryStore.upsert(
            LearnedCorrection(from: "figma", to: "Figma"),
            into: [], now: Date(timeIntervalSince1970: 1), makeID: { "id-1" }
        ).entries
        let (entries, id) = DictionaryStore.upsert(
            LearnedCorrection(from: "fig ma", to: "Figma"),
            into: first, now: Date(timeIntervalSince1970: 5), makeID: { "id-2" }
        )
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(Set(entries[0].aliases), Set(["figma", "fig ma"]))
        XCTAssertEqual(entries[0].updatedAt, Date(timeIntervalSince1970: 5))
        XCTAssertEqual(id, "id-1") // same entry updated, not a new one
    }

    func testUpsertDoesNotDuplicateAlias() {
        let first = DictionaryStore.upsert(
            LearnedCorrection(from: "figma", to: "Figma"),
            into: [], now: Date(timeIntervalSince1970: 1), makeID: { "id-1" }
        ).entries
        let (entries, _) = DictionaryStore.upsert(
            LearnedCorrection(from: "FIGMA", to: "Figma"),
            into: first, now: Date(timeIntervalSince1970: 2), makeID: { "id-2" }
        )
        XCTAssertEqual(entries[0].aliases, ["figma"]) // case-insensitive dedupe
    }
}
