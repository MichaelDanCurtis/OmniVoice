import XCTest
@testable import OmniVoiceCore

@MainActor
final class EntitlementServiceTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 0)
    private func days(_ n: Double) -> Date { Date(timeIntervalSince1970: n * 86_400) }

    /// Mutable clock so tests can advance time between calls.
    private final class Clock { var now: Date; init(_ d: Date) { now = d } }
    /// Captures the last persisted snapshot.
    private final class PersistSink { var last: EntitlementSnapshot?; func persist(_ s: EntitlementSnapshot) { last = s } }

    private struct FailingProvider: EntitlementProviding {
        func fetchEntitlement() async throws -> EntitlementStatus { throw URLError(.notConnectedToInternet) }
    }

    func testInitUsesGateOnCachedSnapshot() {
        let cached = EntitlementSnapshot(status: .active, fetchedAt: t0)
        let service = EntitlementService(
            provider: StubEntitlementProvider(result: .active),
            cached: cached,
            now: { self.days(3) }
        )
        XCTAssertEqual(service.status, .active)
        XCTAssertTrue(service.isEntitled(to: .askAI))
    }

    func testInitNoCacheIsNone() {
        let service = EntitlementService(
            provider: StubEntitlementProvider(result: .active),
            cached: nil,
            now: { self.t0 }
        )
        XCTAssertEqual(service.status, .none)
        XCTAssertFalse(service.isEntitled(to: .cloudSync))
    }

    func testRefreshSuccessUpdatesStatusAndPersists() async {
        let sink = PersistSink()
        let service = EntitlementService(
            provider: StubEntitlementProvider(result: .trialing(endsAt: days(14))),
            cached: nil,
            now: { self.days(1) },
            persist: sink.persist
        )
        await service.refresh()
        XCTAssertEqual(service.status, .trialing(endsAt: days(14)))
        XCTAssertEqual(sink.last, EntitlementSnapshot(status: .trialing(endsAt: days(14)), fetchedAt: days(1)))
    }

    func testRefreshFailureFallsBackToGrace() async {
        // Cached active at t0; now day 3 (within 7-day grace) → stays active despite network failure.
        let cached = EntitlementSnapshot(status: .active, fetchedAt: t0)
        let service = EntitlementService(
            provider: FailingProvider(),
            cached: cached,
            now: { self.days(3) }
        )
        await service.refresh()
        XCTAssertEqual(service.status, .active)
    }

    func testRefreshFailureBeyondGraceExpires() async {
        let cached = EntitlementSnapshot(status: .active, fetchedAt: t0)
        let service = EntitlementService(
            provider: FailingProvider(),
            cached: cached,
            now: { self.days(8) }
        )
        await service.refresh()
        XCTAssertEqual(service.status, .expired)
        XCTAssertFalse(service.isEntitled(to: .liveTranslation))
    }

    func testIsEntitledRecomputesLiveWhenTrialLapses() async {
        let clock = Clock(days(1))
        let sink = PersistSink()
        let service = EntitlementService(
            provider: StubEntitlementProvider(result: .trialing(endsAt: days(5))),
            cached: nil,
            now: { clock.now },
            persist: sink.persist
        )
        await service.refresh()
        XCTAssertTrue(service.isEntitled(to: .conversationMode))
        // Trial lapses while the app stays open — gate re-locks without a new fetch.
        clock.now = days(6)
        XCTAssertFalse(service.isEntitled(to: .conversationMode))
        XCTAssertEqual(service.effectiveStatus, .expired)
    }

    func testStubTrialingConvenience() {
        let provider = StubEntitlementProvider.trialing(days: 14, from: t0)
        XCTAssertEqual(provider.result, .trialing(endsAt: days(14)))
    }
}
