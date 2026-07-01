# Dictionary Learning From Corrections — Design

**Date:** 2026-06-30
**Status:** Approved (design); pending implementation plan
**Scope:** Feature A of a three-part initiative. This spec covers ONLY the local
dictionary-learning feature. Features B (account + entitlement gate via WorkOS AuthKit +
Stripe) and C (cloud sync via a Cloudflare Worker) are separate specs and are out of scope
here — but A's data model is deliberately built sync-ready so C needs no rework.

## Goal

When OmniVoice dictates a word wrong and the user fixes it in their app (e.g. it inserts
`figma`, the user changes it to `Figma`), OmniVoice notices the correction, learns it
immediately into the user's personal dictionary, and shows a small toast with a 5-second
Undo. Future dictations auto-apply the learned correction.

## Architecture overview

```
Dictation → insert text into target field  ──► InsertionReceipt (element, text, range, time)
                                                     │
                              AXObserver / poll on that one element (bounded window)
                                                     ▼
                              value changed → diff vs. expected → CorrectionCandidate
                                                     ▼
                              classify (overlap + small + vocabulary precision filter)
                                                     ▼
                              learn → upsert DictionaryEntry (source: .learned) → Undo toast
                                                     ▼
                              engine cleanup applies entries (canonical casing + alias replace)
```

Everything in feature A is **100% local** — no network, nothing stored beyond the user's
preferences on disk.

## 1. Data model

Replace the flat `OmniVoicePreferences.dictionaryTerms: [String]` with a structured,
sync-ready entry model in `OmniVoiceCore`.

```swift
public struct DictionaryEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String          // UUID — stable identity for future sync/merge (feature C)
    public var canonical: String   // the correct form, e.g. "Figma"
    public var aliases: [String]   // misheard forms to replace, e.g. ["figma", "fig ma"] (may be empty)
    public var source: DictionarySource   // .manual | .learned
    public var enabled: Bool
    public var createdAt: Date     // sync-ready timestamps (last-write-wins in feature C)
    public var updatedAt: Date
}

public enum DictionarySource: String, Codable, Equatable, Sendable {
    case manual
    case learned
}
```

**Migration (back-compat).** On decode, if the old `dictionary_terms: [String]` key is
present and `dictionaryEntries` is absent, map each term → a `DictionaryEntry(canonical:
term, aliases: [], source: .manual, enabled: true)`. Keep `dictionaryTerms` as a **computed
property** over the entries' manual canonicals so existing read sites (and the engine
request payload) keep working during the transition. Persisted under a new key
`dictionary_entries`; decode tolerates either key. Covered by `PreferencesStoreTests`
round-trip + an explicit old→new migration test.

**No secrets here** — entries are non-sensitive and persist via the normal
`PreferencesStore` (UserDefaults) path, not the Keychain.

## 2. Correction detection (Accessibility)

New `CorrectionWatcher` (`OmniVoiceApp`, `@MainActor`), driven by the existing insertion path
(`TextInsertionService` / `AppDelegate.finishDictation`).

1. **Receipt.** On a successful insertion, record an in-memory `InsertionReceipt`:
   the target `AXUIElement`, the inserted text, the insertion location/range (caret/selection
   at insert time), the field value immediately after insert, and a timestamp. Only one active
   receipt at a time (a new insertion supersedes the prior watch).
2. **Watch.** Start an `AXObserver` on the receipt's element for
   `kAXValueChangedNotification` (event-driven), plus a low-frequency poll (~2 Hz) fallback for
   apps that don't post it. Watch ends on the **first** of: a detected correction, focus leaving
   the element, a new insertion, or a timeout (~15–20 s).
3. **Diff.** On a value change, diff the new field value against the receipt's
   post-insert value, localized to the inserted span; isolate the changed token(s):
   `from` = what OmniVoice wrote, `to` = the user's replacement.
4. **Classify** (`CorrectionClassifier`, pure, in `OmniVoiceCore` so it's unit-testable). Learn
   only when ALL hold:
   - the edit **overlaps the inserted span** (ignore unrelated edits and pure appends);
   - the change is **small** (≤ 2 tokens changed);
   - the corrected word passes the **vocabulary precision filter**: it is a plausible
     proper-noun / domain term (e.g. internal capitalization, or not present in a bundled
     common-English wordlist) — never homophone/grammar edits like `there → their`.
5. **Learn.** Upsert a `DictionaryEntry`: if a `.learned`/`.manual` entry already has this
   `canonical`, add the `from` token to its `aliases` (dedup) and bump `updatedAt`; else create
   a new `.learned` entry (`canonical = to`, `aliases = [from]`). Then fire the Undo toast.

### Privacy & safety guardrails
- Reuses the **existing Accessibility permission** (insertion already needs it). No new prompt.
- **Only the single target element** is read, **only** during the bounded window; only the
  changed tokens are extracted — the full field text is never stored or transmitted.
- **Never** observe secure/password fields (`AXSecureTextField` / secure role); skip and drop
  the receipt.
- Master setting **"Automatically learn my corrections"** (default on) disables the watcher
  entirely.

### Coverage & fallback
Fields that don't expose their value over Accessibility (some web/Electron inputs) simply
won't auto-detect. The **teach-chip fallback** — a small affordance shown briefly after a
dictation (and/or a hotkey) — lets the user open "what should it have said?", supply the
corrected text, and learn it manually (same upsert path, `source: .learned`). This guarantees
the feature is usable everywhere even where AX observation isn't.

## 3. Trust model — optimistic learn + 5-second Undo toast

`LearnedWordToast` — a small **non-activating** floating panel in OmniVoice's overlay zone
(top-center, same family as the caption/Ask bubble; never steals focus). Reuses the existing
overlay-panel pattern.

- Content: `Learned "figma" → "Figma"` with an **Undo** button wrapped in a 5-second countdown
  ring.
- **Undo within 5 s** → remove the just-created entry (or the just-added alias) and dismiss.
- **Ignore** → fades after 5 s; the learning stands.
- Rapid successive learns: the newest toast **replaces** the current one (the previous
  auto-commits), so toasts never stack.

## 4. Engine apply

Extend the existing post-transcription cleanup (`engine/omnivoice_engine/cleanup.py`,
`_apply_dictionary_terms`) to consume structured entries instead of a flat term list:

- **Canonical casing** — case-insensitive whole-word match of each `canonical` → normalize to
  the canonical casing.
- **Alias replacement** — whole-word, case-insensitive match of each `alias` → replace with its
  `canonical`.
- Order: alias replacement first, then canonical casing (so an alias that maps to a known
  canonical also gets correct casing). Disabled entries are skipped.

The engine request gains a structured `dictionary_entries` field; keep sending the legacy
`dictionary_terms` for one release for safety. Covered by `pytest` in `engine/tests`.

## 5. Settings UI

The existing **Personal Dictionary** section (`SettingsView`) gains:
- The current **manual terms** text box stays as-is (one canonical per line → `source: .manual`).
- A new **"Learned Words"** list: each `.learned` entry shows `canonical`, its `aliases`, and
  when it was learned, with per-row **edit / disable / remove** (so a bad rule is one click to
  kill, and aliases are hand-tunable).
- A master toggle: **"Automatically learn my corrections."**

AppModel gains mutators mirroring the existing pattern: `addDictionaryEntry`,
`updateDictionaryEntry`, `removeDictionaryEntry`, `setAutoLearnEnabled` (each persists via
`persistPreferences()`).

## Components & responsibilities

| Unit | Target | Responsibility |
|------|--------|----------------|
| `DictionaryEntry` / `DictionarySource` | Core | Data model (sync-ready) |
| Preferences migration | Core | `dictionary_terms` → `dictionary_entries`, back-compat |
| `CorrectionClassifier` | Core | Pure diff→classify→precision filter (unit-tested) |
| Common-word list | Core | Bundled resource for the precision filter |
| `CorrectionWatcher` | App | AXObserver lifecycle + receipts (manual/integration test) |
| `LearnedWordToast` | App | Non-activating undo-toast panel (manual test) |
| Teach-chip fallback | App | Manual-correction affordance |
| Settings additions | App | Learned-words list + master toggle |
| Engine cleanup | engine | Apply entries (canonical casing + alias replace) (pytest) |

## Error handling & edge cases
- Focus leaves the field mid-window → end the watch cleanly, no learn.
- Re-correcting an already-learned word → update (merge alias, bump `updatedAt`).
- Learned `canonical` equals an existing manual term → just add the alias to that entry.
- App exposes no AX value / secure field → no-op; teach-chip remains available.
- Undo after the toast is gone → remove via the Settings "Learned Words" list.
- AXObserver fails to install → fall back to polling; if polling also yields nothing, no-op.

## Testing strategy
- **Unit (Core):** `CorrectionClassifier` (from→to extraction, span overlap, ≤2-token rule,
  precision filter incl. `there→their` rejection), `DictionaryEntry` migration round-trip,
  AppModel mutators.
- **Unit (engine, pytest):** entry application — canonical casing, alias replacement, ordering,
  disabled-entry skip.
- **Manual / integration:** AX observation across a few real apps (TextEdit, Notes, a browser
  field), the undo toast and its countdown, the teach-chip fallback, secure-field skip.

## Out of scope (future specs)
- **Feature B** — account + entitlement gating (WorkOS AuthKit + Stripe + Cloudflare Worker).
- **Feature C** — cloud sync of dictionary entries + preferences (uses B's identity/backend;
  `DictionaryEntry`'s `id` + `updatedAt` enable last-write-wins merge).
- ASR-level biasing (feeding vocabulary into the recognizer) — current model is post-transcription
  cleanup only; biasing is a possible later enhancement.
