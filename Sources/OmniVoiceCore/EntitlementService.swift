import Combine
import Foundation

/// Supplies the authoritative entitlement answer. The real implementation talks to
/// the Cloudflare Worker (`WorkerEntitlementProvider`); ``StubEntitlementProvider``
/// stands in for tests and for local dev before the Worker is provisioned.
public protocol EntitlementProviding: Sendable {
    func fetchEntitlement() async throws -> EntitlementStatus
}

/// A fixed-answer provider. In dev it keeps the app fully usable (default: a fresh
/// 14-day trial) before the backend exists; in tests it returns a scripted status.
public struct StubEntitlementProvider: EntitlementProviding {
    public var result: EntitlementStatus

    public init(result: EntitlementStatus) {
        self.result = result
    }

    /// A stub that reports an in-progress no-card trial ending `days` from `now`.
    public static func trialing(days: Int = 14, from now: Date = Date()) -> StubEntitlementProvider {
        StubEntitlementProvider(result: .trialing(endsAt: now.addingTimeInterval(Double(days) * 86_400)))
    }

    public func fetchEntitlement() async throws -> EntitlementStatus {
        result
    }
}

/// Owns the app's live entitlement state and gates premium features.
///
/// The Worker is the source of truth; this service refreshes from it (on launch,
/// foreground, timer) and caches the last answer via `persist`. Between refreshes,
/// gate checks recompute against the injected clock so an expiring trial re-locks
/// even with no network, and a still-valid cache survives an offline Worker within
/// the grace window (see `EntitlementGate`).
@MainActor
public final class EntitlementService: ObservableObject {
    /// The last known status, for display. Gate checks use ``effectiveStatus``.
    @Published public private(set) var status: EntitlementStatus

    private let provider: EntitlementProviding
    private let now: () -> Date
    private let graceDays: Int
    private let persist: (EntitlementSnapshot) -> Void
    private var lastSnapshot: EntitlementSnapshot?

    public init(
        provider: EntitlementProviding,
        cached: EntitlementSnapshot?,
        now: @escaping () -> Date = { Date() },
        graceDays: Int = 7,
        persist: @escaping (EntitlementSnapshot) -> Void = { _ in }
    ) {
        self.provider = provider
        self.now = now
        self.graceDays = graceDays
        self.persist = persist
        self.lastSnapshot = cached
        self.status = EntitlementGate.effectiveStatus(cached: cached, now: now(), graceDays: graceDays)
    }

    /// Live-evaluated status against the current clock and the last cached snapshot.
    public var effectiveStatus: EntitlementStatus {
        EntitlementGate.effectiveStatus(cached: lastSnapshot, now: now(), graceDays: graceDays)
    }

    /// Whether `feature` is unlocked. All four premium features gate on the same
    /// subscription for v1; the parameter keeps the call site future-proof.
    public func isEntitled(to feature: PremiumFeature) -> Bool {
        effectiveStatus.isEntitled
    }

    /// Fetch the authoritative answer. On success, cache + persist it and publish it.
    /// On failure, fall back to the offline-grace evaluation of the last snapshot.
    public func refresh() async {
        do {
            let fetched = try await provider.fetchEntitlement()
            let snapshot = EntitlementSnapshot(status: fetched, fetchedAt: now())
            lastSnapshot = snapshot
            persist(snapshot)
            status = fetched
        } catch {
            status = EntitlementGate.effectiveStatus(cached: lastSnapshot, now: now(), graceDays: graceDays)
        }
    }
}
