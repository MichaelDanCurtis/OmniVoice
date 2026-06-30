import Foundation

public enum DictionarySource: String, Codable, Equatable, Sendable {
    case manual
    case learned
}

/// One personal-dictionary entry. `canonical` is the correct form; `aliases` are misheard
/// forms that should be replaced with it. `id`/`updatedAt` make the model sync-ready for the
/// future cloud-sync feature (last-write-wins merge).
public struct DictionaryEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var canonical: String
    public var aliases: [String]
    public var source: DictionarySource
    public var enabled: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        canonical: String,
        aliases: [String],
        source: DictionarySource,
        enabled: Bool,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.canonical = canonical
        self.aliases = aliases
        self.source = source
        self.enabled = enabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Convenience for migrating a legacy manual term. `id` is derived deterministically from
    /// the canonical so repeated migrations don't create duplicates.
    public init(manualTerm: String, at now: Date) {
        self.init(
            id: "manual:" + manualTerm.lowercased(),
            canonical: manualTerm,
            aliases: [],
            source: .manual,
            enabled: true,
            createdAt: now,
            updatedAt: now
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case canonical
        case aliases
        case source
        case enabled
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
