import XCTest
@testable import OmniVoiceCore

final class EntitlementGateTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 0)
    private func days(_ n: Double) -> Date { Date(timeIntervalSince1970: n * 86_400) }

    func testActiveWithinGraceStaysEntitled() {
        let cached = EntitlementSnapshot(status: .active, fetchedAt: t0)
        XCTAssertEqual(EntitlementGate.effectiveStatus(cached: cached, now: days(3)), .active)
    }

    func testActiveBeyondGraceExpires() {
        let cached = EntitlementSnapshot(status: .active, fetchedAt: t0)
        XCTAssertEqual(EntitlementGate.effectiveStatus(cached: cached, now: days(8)), .expired)
    }

    func testTrialingExpiresWhenTrialEnds() {
        let cached = EntitlementSnapshot(status: .trialing(endsAt: days(5)), fetchedAt: days(4))
        XCTAssertEqual(EntitlementGate.effectiveStatus(cached: cached, now: days(6)), .expired)
    }

    func testTrialingWithinWindowAndGrace() {
        let cached = EntitlementSnapshot(status: .trialing(endsAt: days(10)), fetchedAt: days(4))
        XCTAssertEqual(EntitlementGate.effectiveStatus(cached: cached, now: days(6)),
                       .trialing(endsAt: days(10)))
    }

    func testTrialingBeyondGraceExpiresEvenBeforeTrialEnd() {
        // Fetched at t0, trial nominally runs to day 20, but we've been offline > 7 days.
        let cached = EntitlementSnapshot(status: .trialing(endsAt: days(20)), fetchedAt: t0)
        XCTAssertEqual(EntitlementGate.effectiveStatus(cached: cached, now: days(9)), .expired)
    }

    func testNoCacheIsNone() {
        XCTAssertEqual(EntitlementGate.effectiveStatus(cached: nil, now: t0), .none)
    }

    func testExpiredCacheStaysExpired() {
        let cached = EntitlementSnapshot(status: .expired, fetchedAt: t0)
        XCTAssertEqual(EntitlementGate.effectiveStatus(cached: cached, now: days(1)), .expired)
    }
}
