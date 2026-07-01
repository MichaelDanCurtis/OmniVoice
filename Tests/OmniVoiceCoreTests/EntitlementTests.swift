import XCTest
@testable import OmniVoiceCore

final class EntitlementTests: XCTestCase {
    func testIsEntitled() {
        XCTAssertTrue(EntitlementStatus.active.isEntitled)
        XCTAssertTrue(EntitlementStatus.trialing(endsAt: Date(timeIntervalSince1970: 100)).isEntitled)
        XCTAssertFalse(EntitlementStatus.expired.isEntitled)
        XCTAssertFalse(EntitlementStatus.none.isEntitled)
    }

    func testSnapshotRoundTrip() throws {
        let snap = EntitlementSnapshot(status: .trialing(endsAt: Date(timeIntervalSince1970: 5)),
                                       fetchedAt: Date(timeIntervalSince1970: 1))
        let data = try JSONEncoder().encode(snap)
        XCTAssertEqual(try JSONDecoder().decode(EntitlementSnapshot.self, from: data), snap)
    }
}
