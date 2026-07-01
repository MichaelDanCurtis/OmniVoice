import Foundation

/// The user's premium entitlement state. `entitled = trialing OR active`.
///
/// The Cloudflare Worker is the source of truth; the app caches the last answer
/// (see ``EntitlementSnapshot`` and `EntitlementGate`) and honors it within an
/// offline grace window.
public enum EntitlementStatus: Codable, Equatable, Sendable {
    /// Signed out or unknown.
    case none
    /// Inside the no-card free trial; unlocks all premium features until `endsAt`.
    case trialing(endsAt: Date)
    /// Paid subscription active.
    case active
    /// Trial ended or subscription lapsed / offline-grace exhausted.
    case expired

    /// Whether premium features should be unlocked.
    public var isEntitled: Bool {
        switch self {
        case .active, .trialing:
            return true
        case .none, .expired:
            return false
        }
    }
}

/// The features gated behind the premium tier. All four gate on the same
/// subscription for v1 (all-or-nothing).
public enum PremiumFeature: String, CaseIterable, Sendable {
    case askAI
    case cloudSync
    case liveTranslation
    case conversationMode

    /// Human-facing name used in the paywall and Account UI.
    public var displayName: String {
        switch self {
        case .askAI: return "Ask AI"
        case .cloudSync: return "Cloud Sync"
        case .liveTranslation: return "Live Translation"
        case .conversationMode: return "Conversation Mode"
        }
    }
}

/// A cached entitlement answer plus the time it was fetched, persisted so the
/// gate can apply the offline grace window when the Worker is unreachable.
public struct EntitlementSnapshot: Codable, Equatable, Sendable {
    public var status: EntitlementStatus
    public var fetchedAt: Date

    public init(status: EntitlementStatus, fetchedAt: Date) {
        self.status = status
        self.fetchedAt = fetchedAt
    }
}
