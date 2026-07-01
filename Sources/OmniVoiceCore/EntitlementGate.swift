import Foundation

/// Pure entitlement resolution: given a cached ``EntitlementSnapshot`` and the
/// current time, decide what status to honor.
///
/// Two rules combine:
/// - **Trial expiry is authoritative:** once a trial's `endsAt` has passed, the
///   status is `.expired` regardless of grace.
/// - **Offline grace:** an entitled cache is honored only while the machine has
///   been able to reach the Worker within `graceDays`; past that the cache goes
///   stale and re-locks to `.expired`. This prevents both offline lockout and
///   indefinite post-cancel access.
public enum EntitlementGate {
    public static func effectiveStatus(
        cached: EntitlementSnapshot?,
        now: Date,
        graceDays: Int = 7
    ) -> EntitlementStatus {
        guard let cached else { return .none }

        // Trial expiry is authoritative regardless of grace.
        if case .trialing(let endsAt) = cached.status, now >= endsAt {
            return .expired
        }

        // Non-entitled cached statuses pass through unchanged.
        guard cached.status.isEntitled else { return cached.status }

        // Entitled cache is honored only within the offline grace window.
        let graceSeconds = Double(graceDays) * 86_400
        if now.timeIntervalSince(cached.fetchedAt) > graceSeconds {
            return .expired
        }

        return cached.status
    }
}
