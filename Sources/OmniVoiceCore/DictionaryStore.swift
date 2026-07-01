import Foundation

/// Pure operations over a set of `DictionaryEntry`. Kept side-effect-free so the merge logic
/// is unit-tested; the AppModel mutators are thin wrappers that persist the result.
public enum DictionaryStore {
    /// Records a learned correction: if an entry already exists with the same canonical
    /// (case-insensitive), the misheard `from` is merged into its aliases and `updatedAt` is
    /// bumped; otherwise a new `.learned` entry is created. Returns the updated entries and the
    /// affected entry's id (so the caller can offer undo).
    public static func upsert(
        _ correction: LearnedCorrection,
        into entries: [DictionaryEntry],
        now: Date,
        makeID: () -> String
    ) -> (entries: [DictionaryEntry], id: String) {
        if let index = entries.firstIndex(where: { $0.canonical.lowercased() == correction.to.lowercased() }) {
            var updated = entries
            var entry = updated[index]
            if !entry.aliases.contains(where: { $0.lowercased() == correction.from.lowercased() }) {
                entry.aliases.append(correction.from)
            }
            entry.updatedAt = now
            updated[index] = entry
            return (updated, entry.id)
        }
        let id = makeID()
        let entry = DictionaryEntry(
            id: id,
            canonical: correction.to,
            aliases: [correction.from],
            source: .learned,
            enabled: true,
            createdAt: now,
            updatedAt: now
        )
        return (entries + [entry], id)
    }
}
