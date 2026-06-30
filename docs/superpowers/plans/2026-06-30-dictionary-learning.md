# Dictionary Learning From Corrections — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-detect when a user corrects OmniVoice's dictated output, learn the correction into a sync-ready personal-dictionary model with a 5-second undo, and apply learned corrections in the engine cleanup.

**Architecture:** A new `DictionaryEntry` model (Core) replaces the flat `dictionaryTerms: [String]` (kept as a computed accessor for back-compat). A pure `CorrectionClassifier` (Core) decides what to learn; a `CorrectionWatcher` (App) drives it from Accessibility observation of the just-inserted field; a `LearnedWordToast` (App) shows the optimistic-learn + undo. The engine cleanup applies entries (canonical casing + alias replacement).

**Tech Stack:** Swift 6 SwiftPM (`OmniVoiceCore` library + `OmniVoiceApp` AppKit/SwiftUI executable), Python FastAPI engine (`engine/`), XCTest + pytest.

## Global Constraints

- Feature A is **100% local** — no network, no new permission (reuses existing Accessibility access).
- Data model is **sync-ready**: `DictionaryEntry` has a stable `id: String` (UUID) and `updatedAt: Date` for feature C's last-write-wins merge. Do NOT remove these.
- **Precision over recall:** only learn vocabulary-like corrections (proper-noun / non-common-word); never homophone/grammar edits (`there → their`).
- **Never** observe secure/password text fields.
- Follow the existing `OmniVoicePreferences` Codable pattern exactly: explicit `CodingKeys` + `ConvertedCodingKeys`, TWO `init(from:)` decode sites, `decodeIfPresent(...) ?? default` for back-compat.
- AppModel mutators follow the existing pattern: mutate `preferences`, then `guard persistPreferences() else { return }`.

---

### Task 1: `DictionaryEntry` model

**Files:**
- Create: `Sources/OmniVoiceCore/DictionaryEntry.swift`
- Test: `Tests/OmniVoiceCoreTests/DictionaryEntryTests.swift`

**Interfaces:**
- Produces: `DictionaryEntry` (Codable, Equatable, Identifiable, Sendable) with `id, canonical, aliases, source, enabled, createdAt, updatedAt`; `DictionarySource` enum `.manual | .learned`.

- [ ] **Step 1: Write the failing test**
```swift
import XCTest
@testable import OmniVoiceCore

final class DictionaryEntryTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let entry = DictionaryEntry(id: "abc", canonical: "Figma", aliases: ["figma"],
                                    source: .learned, enabled: true,
                                    createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 2))
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(DictionaryEntry.self, from: data)
        XCTAssertEqual(decoded, entry)
    }

    func testManualConvenienceInit() {
        let e = DictionaryEntry(manualTerm: "Figma", at: Date(timeIntervalSince1970: 5))
        XCTAssertEqual(e.canonical, "Figma")
        XCTAssertEqual(e.source, .manual)
        XCTAssertTrue(e.aliases.isEmpty)
        XCTAssertTrue(e.enabled)
    }
}
```

- [ ] **Step 2: Run it to verify it fails** — `swift test --filter DictionaryEntryTests` → FAIL (no such type).

- [ ] **Step 3: Implement**
```swift
import Foundation

public enum DictionarySource: String, Codable, Equatable, Sendable {
    case manual
    case learned
}

public struct DictionaryEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var canonical: String
    public var aliases: [String]
    public var source: DictionarySource
    public var enabled: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String, canonical: String, aliases: [String], source: DictionarySource,
                enabled: Bool, createdAt: Date, updatedAt: Date) {
        self.id = id; self.canonical = canonical; self.aliases = aliases; self.source = source
        self.enabled = enabled; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    /// Convenience for migrating a legacy manual term. `id` is derived deterministically
    /// from the canonical so repeated migrations don't create duplicates.
    public init(manualTerm: String, at now: Date) {
        self.init(id: "manual:" + manualTerm.lowercased(), canonical: manualTerm, aliases: [],
                  source: .manual, enabled: true, createdAt: now, updatedAt: now)
    }

    enum CodingKeys: String, CodingKey {
        case id, canonical, aliases, source, enabled
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
```

- [ ] **Step 4: Run tests** — `swift test --filter DictionaryEntryTests` → PASS.

- [ ] **Step 5: Commit** — `git add Sources/OmniVoiceCore/DictionaryEntry.swift Tests/OmniVoiceCoreTests/DictionaryEntryTests.swift && git commit -m "feat(dictionary): DictionaryEntry sync-ready model"`

---

### Task 2: Migrate preferences to `dictionaryEntries`

**Files:**
- Modify: `Sources/OmniVoiceCore/PreferencesStore.swift` (property @ line 10; defaults @ 123; init sig @ 177; init body @ 233; decode sites @ 337 and 422; encode; CodingKeys @ 699; ConvertedCodingKeys @ 753)
- Test: `Tests/OmniVoiceCoreTests/PreferencesStoreTests.swift`

**Interfaces:**
- Consumes: `DictionaryEntry` (Task 1).
- Produces: `OmniVoicePreferences.dictionaryEntries: [DictionaryEntry]` (stored); `dictionaryTerms: [String]` becomes a **computed** read-only accessor returning enabled manual canonicals; `autoLearnCorrectionsEnabled: Bool` (default `true`). New persisted keys `dictionary_entries`, `auto_learn_corrections_enabled`.

- [ ] **Step 1: Write the failing tests**
```swift
func testOldDictionaryTermsMigrateToEntries() throws {
    // JSON with the legacy key only.
    let json = #"{"dictionary_terms":["Figma","Slack"]}"#  // plus whatever else decode requires; build via a fixture helper
    let prefs = try decodePreferences(fromPartial: json)   // helper that fills required keys with defaults
    XCTAssertEqual(prefs.dictionaryEntries.map(\.canonical), ["Figma", "Slack"])
    XCTAssertTrue(prefs.dictionaryEntries.allSatisfy { $0.source == .manual })
    XCTAssertEqual(prefs.dictionaryTerms, ["Figma", "Slack"])   // computed accessor still works
}

func testDictionaryEntriesRoundTrip() throws {
    var prefs = OmniVoicePreferences.defaults
    prefs.dictionaryEntries = [DictionaryEntry(id: "1", canonical: "Figma", aliases: ["figma"],
        source: .learned, enabled: true, createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 1))]
    let data = try JSONEncoder().encode(prefs)
    let decoded = try JSONDecoder().decode(OmniVoicePreferences.self, from: data)
    XCTAssertEqual(decoded.dictionaryEntries, prefs.dictionaryEntries)
}

func testAutoLearnDefaultsTrue() {
    XCTAssertTrue(OmniVoicePreferences.defaults.autoLearnCorrectionsEnabled)
}
```
> If no `decodePreferences(fromPartial:)` helper exists, add one in the test file that starts from `OmniVoicePreferences.defaults`, encodes it, merges the partial JSON object over it, and decodes — OR construct the full legacy JSON. Match whatever fixture style `PreferencesStoreTests` already uses.

- [ ] **Step 2: Run to verify failure** — `swift test --filter PreferencesStoreTests` → FAIL.

- [ ] **Step 3: Implement the migration**

  3a. Replace the stored `public var dictionaryTerms: [String]` (line 10) with:
  ```swift
  public var dictionaryEntries: [DictionaryEntry]
  public var autoLearnCorrectionsEnabled: Bool

  /// Back-compat read accessor: enabled manual canonicals, in order.
  public var dictionaryTerms: [String] {
      dictionaryEntries.filter { $0.source == .manual && $0.enabled }.map(\.canonical)
  }
  ```
  3b. In `defaults` (line ~123) replace `dictionaryTerms: []` with `dictionaryEntries: []` and add `autoLearnCorrectionsEnabled: true`.
  3c. In the init signature (line ~177) replace `dictionaryTerms: [String],` with `dictionaryEntries: [DictionaryEntry],` and add `autoLearnCorrectionsEnabled: Bool,`. In the init body (line ~233) assign both.
  3d. In BOTH `init(from:)` decode sites (lines ~337 and ~422) replace the `dictionaryTerms` decode with a migration helper call:
  ```swift
  dictionaryEntries: try OmniVoicePreferences.decodeDictionaryEntries(from: container),
  autoLearnCorrectionsEnabled: try container.decodeIfPresent(Bool.self, forKey: .autoLearnCorrectionsEnabled) ?? true,
  ```
  and add this static helper to `OmniVoicePreferences`:
  ```swift
  static func decodeDictionaryEntries(from container: KeyedDecodingContainer<CodingKeys>) throws -> [DictionaryEntry] {
      if let entries = try container.decodeIfPresent([DictionaryEntry].self, forKey: .dictionaryEntries) {
          return entries
      }
      let legacy = try container.decodeIfPresent([String].self, forKey: .dictionaryTermsLegacy) ?? []
      let now = Date(timeIntervalSince1970: 0)   // deterministic for migrated terms; fine for last-write-wins seed
      return legacy.map { DictionaryEntry(manualTerm: $0, at: now) }
  }
  ```
  3e. In `encode(to:)` write `try container.encode(dictionaryEntries, forKey: .dictionaryEntries)` and `try container.encode(autoLearnCorrectionsEnabled, forKey: .autoLearnCorrectionsEnabled)`; REMOVE the `dictionaryTerms` encode (it's computed now).
  3f. In `CodingKeys` (line ~699): keep the legacy key but rename its case so the new key is canonical:
  ```swift
  case dictionaryEntries = "dictionary_entries"
  case dictionaryTermsLegacy = "dictionary_terms"
  case autoLearnCorrectionsEnabled = "auto_learn_corrections_enabled"
  ```
  3g. In `ConvertedCodingKeys` (line ~753) replace `case dictionaryTerms` with `case dictionaryEntries` and `case autoLearnCorrectionsEnabled`.
  3h. Fix any other construction sites of `OmniVoicePreferences(...)` (tests, previews) that passed `dictionaryTerms:` — pass `dictionaryEntries: []` instead (grep: `dictionaryTerms:` across `Sources` and `Tests`).

- [ ] **Step 4: Run tests** — `swift test` → all green (whole suite, since this touches the central model).

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat(dictionary): migrate preferences to dictionaryEntries + autoLearn flag"`

---

### Task 3: `CorrectionClassifier` (pure)

**Files:**
- Create: `Sources/OmniVoiceCore/CorrectionClassifier.swift`
- Create: `Sources/OmniVoiceCore/Resources/common-words.txt` (bundled; ~2–5k lowercase common English words, one per line) — add a `resources:` entry for the `OmniVoiceCore` target in `Package.swift` if not already present.
- Test: `Tests/OmniVoiceCoreTests/CorrectionClassifierTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct LearnedCorrection: Equatable, Sendable { public let from: String; public let to: String }
  public enum CorrectionClassifier {
      /// before = field value right after OmniVoice inserted; after = field value now;
      /// insertedRange = the character range OmniVoice wrote in `before`.
      public static func classify(before: String, after: String, insertedRange: Range<String.Index>) -> LearnedCorrection?
      public static func isLikelyVocabulary(_ word: String) -> Bool
  }
  ```

- [ ] **Step 1: Write the failing tests**
```swift
func testCasingCorrectionLearned() {
    let before = "I love figma today"
    let after  = "I love Figma today"
    let r = before.range(of: "figma")!
    XCTAssertEqual(CorrectionClassifier.classify(before: before, after: after, insertedRange: r),
                   LearnedCorrection(from: "figma", to: "Figma"))
}
func testMishearingLearned() {
    let before = "open fig ma now"; let after = "open Figma now"
    let r = before.range(of: "fig ma")!
    XCTAssertEqual(CorrectionClassifier.classify(before: before, after: after, insertedRange: r),
                   LearnedCorrection(from: "fig ma", to: "Figma"))
}
func testHomophoneRejected() {
    let before = "put it over there"; let after = "put it over their"
    let r = before.range(of: "there")!
    XCTAssertNil(CorrectionClassifier.classify(before: before, after: after, insertedRange: r))   // "their" is a common word
}
func testUnrelatedEditIgnored() {
    let before = "hello figma world"; let after = "HELLO figma world"   // edit outside inserted span
    let r = before.range(of: "figma")!
    XCTAssertNil(CorrectionClassifier.classify(before: before, after: after, insertedRange: r))
}
func testMultiWordChangeRejected() {
    let before = "the quick fox"; let after = "the very fast fox"
    let r = before.range(of: "quick")!
    XCTAssertNil(CorrectionClassifier.classify(before: before, after: after, insertedRange: r))
}
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter CorrectionClassifierTests` → FAIL.

- [ ] **Step 3: Implement** — compute the minimal changed region between `before` and `after` (common prefix/suffix trim); require the changed region in `before` to intersect `insertedRange`; require `from` (changed region in before) and `to` (changed region in after) to each be ≤ 2 whitespace-separated tokens; require `to` to be non-empty and `isLikelyVocabulary(to)`; return `LearnedCorrection(from:to:)` else nil. `isLikelyVocabulary(word)` = has internal/leading uppercase OR (single token AND not in the bundled common-words set, loaded once via `Bundle.module`). Keep it pure and deterministic.

- [ ] **Step 4: Run tests** — `swift test --filter CorrectionClassifierTests` → PASS.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat(dictionary): pure CorrectionClassifier + precision filter"`

---

### Task 4: Engine — apply entries

**Files:**
- Modify: `engine/omnivoice_engine/schemas.py:28` (add `dictionary_entries`)
- Modify: `engine/omnivoice_engine/cleanup.py:54,103` (apply entries)
- Test: `engine/tests/test_cleanup.py` (add cases)

**Interfaces:**
- Produces: `CleanupRequest.dictionary_entries: list[DictionaryEntryModel]` where `DictionaryEntryModel` = `{canonical: str, aliases: list[str] = [], enabled: bool = True}`. `dictionary_terms` stays for back-compat.

- [ ] **Step 1: Write the failing pytest**
```python
def test_alias_replacement_and_casing():
    from omnivoice_engine.cleanup import _apply_dictionary_entries
    entries = [{"canonical": "Figma", "aliases": ["fig ma"], "enabled": True}]
    assert _apply_dictionary_entries("open fig ma and figma", entries) == "open Figma and Figma"

def test_disabled_entry_skipped():
    from omnivoice_engine.cleanup import _apply_dictionary_entries
    assert _apply_dictionary_entries("figma", [{"canonical": "Figma", "aliases": [], "enabled": False}]) == "figma"
```

- [ ] **Step 2: Run to verify failure** — `engine/.venv/bin/python -m pytest engine/tests/test_cleanup.py -k dictionary -q` → FAIL.

- [ ] **Step 3: Implement** — add `_apply_dictionary_entries(text, entries)`: for each enabled entry, first replace each alias (`\b{re.escape(alias)}\b`, IGNORECASE → canonical), then canonicalize casing of the canonical itself (`\b{re.escape(canonical)}\b`, IGNORECASE → canonical). In `cleanup_text` (line ~54) call `_apply_dictionary_entries(text, request.dictionary_entries)` after the existing `_apply_dictionary_terms` (terms first, then entries; entries win). Add the Pydantic models to `schemas.py`.

- [ ] **Step 4: Run tests** — `engine/.venv/bin/python -m pytest engine/tests/test_cleanup.py -q` → PASS.

- [ ] **Step 5: Commit** — `git add engine && git commit -m "feat(engine): apply dictionary entries (alias replace + casing)"`

---

### Task 5: Send entries from the app

**Files:**
- Modify: `Sources/OmniVoiceCore/EngineClient.swift` (the `CleanupRequest` type + the call site that builds it from preferences)
- Test: `Tests/OmniVoiceCoreTests/EngineClientTests.swift` (or wherever `CleanupRequest` encoding is tested)

**Interfaces:**
- Consumes: `OmniVoicePreferences.dictionaryEntries` (Task 2), engine schema (Task 4).
- Produces: `CleanupRequest.dictionaryEntries: [CleanupRequest.Entry]` encoding to `dictionary_entries`; keep `dictionaryTerms`.

- [ ] **Step 1: Write the failing test** — encode a `CleanupRequest` with one entry; assert the JSON contains `"dictionary_entries"` with `canonical/aliases/enabled` and snake_case keys.
- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement** — add a nested `Entry: Codable { canonical, aliases, enabled }` to `CleanupRequest` with `CodingKeys` (snake_case), a `dictionaryEntries` field, and map `preferences.dictionaryEntries` → these at the build site (filter `enabled`, drop empty canonicals). Keep sending `dictionaryTerms`.
- [ ] **Step 4: Run tests** — green.
- [ ] **Step 5: Commit** — `git commit -am "feat(dictionary): send dictionary entries to the engine cleanup"`

---

### Task 6: AppModel dictionary mutators

**Files:**
- Modify: `Sources/OmniVoiceApp/AppModel.swift` (near the existing `setDictionaryTermsText`)

**Interfaces:**
- Produces (all `@MainActor`, persist via `persistPreferences()`):
  `func upsertLearnedCorrection(_ c: LearnedCorrection) -> DictionaryEntry` (creates/updates a `.learned` entry; returns it so the toast can offer undo by id),
  `func removeDictionaryEntry(id: String)`,
  `func updateDictionaryEntry(_ entry: DictionaryEntry)`,
  `func setAutoLearnEnabled(_ on: Bool)`.

- [ ] **Step 1: Write the failing test** (in `Tests/OmniVoiceCoreTests`? AppModel is in App and untested — instead unit-test the pure upsert logic by extracting it.) Add a pure helper in Core:
  ```swift
  // Sources/OmniVoiceCore/DictionaryStore.swift
  public enum DictionaryStore {
      /// Returns updated entries + the affected entry id. Merges alias into an existing
      /// entry with the same canonical (case-insensitive), else creates a new .learned entry.
      public static func upsert(_ correction: LearnedCorrection, into entries: [DictionaryEntry], now: Date, makeID: () -> String) -> (entries: [DictionaryEntry], id: String)
  }
  ```
  Test: upsert into empty → one `.learned` entry with `canonical == to`, `aliases == [from]`; upsert same `to` again with a new `from` → single entry, both aliases, `updatedAt` bumped.
- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement** `DictionaryStore.upsert` (pure, Core), then the thin AppModel mutators that call it (`makeID: { UUID().uuidString }`, `now: Date()`), each persisting and returning where noted.
- [ ] **Step 4: Run tests** — green.
- [ ] **Step 5: Commit** — `git commit -am "feat(dictionary): DictionaryStore.upsert + AppModel mutators"`

---

### Task 7: `CorrectionWatcher` (Accessibility)

**Files:**
- Create: `Sources/OmniVoiceApp/CorrectionWatcher.swift`
- Modify: `Sources/OmniVoiceApp/AppDelegate.swift` (start a watch after a successful insertion in `finishDictation`; wire `onLearn`), `Sources/OmniVoiceApp/TextInsertionService.swift` (expose the inserted range + post-insert value if not already available)

**Interfaces:**
- Consumes: `CorrectionClassifier.classify` (Task 3), `AppModel.upsertLearnedCorrection` (Task 6), the insertion target.
- Produces: `@MainActor final class CorrectionWatcher` with `func observe(element: AXUIElement, insertedText: String, insertedRange: Range<String.Index>, postInsertValue: String)` and `var onLearn: ((LearnedCorrection) -> Void)?`. No public test surface (the pure logic lives in Task 3).

- [ ] **Step 1: Implement** — record a single `InsertionReceipt`; install an `AXObserver` on `kAXValueChangedNotification` for the element + a ~2 Hz `Timer` poll fallback; on change read the element's `kAXValueAttribute` (skip if the role is a secure field), call `CorrectionClassifier.classify(before: receipt.postInsertValue, after: newValue, insertedRange: receipt.insertedRange)`; if non-nil and `model.preferences.autoLearnCorrectionsEnabled`, fire `onLearn`. End the watch on first learn, focus change, new insertion, or a 20 s timeout. Guard all AX work behind `AXIsProcessTrusted()`.
- [ ] **Step 2: Wire** — in `AppDelegate.finishDictation`, after a successful (non-Ask, non-command) insertion, call `correctionWatcher.observe(...)`; set `correctionWatcher.onLearn = { [weak self] c in let entry = self?.model?.upsertLearnedCorrection(c); self?.learnedWordToast.show(correction: c, entryID: entry?.id) }` (toast from Task 8).
- [ ] **Step 3: Build** — `swift build` clean.
- [ ] **Step 4: Manual verify** — dictate a proper noun into TextEdit, change its casing; confirm `onLearn` fires (log) and the entry appears. Confirm secure fields are skipped and the master toggle disables it.
- [ ] **Step 5: Commit** — `git commit -am "feat(dictionary): CorrectionWatcher (Accessibility) wiring"`

---

### Task 8: `LearnedWordToast` (undo)

**Files:**
- Create: `Sources/OmniVoiceApp/LearnedWordToast.swift`

**Interfaces:**
- Consumes: `AppModel.removeDictionaryEntry(id:)` (Task 6).
- Produces: `@MainActor final class LearnedWordToast` with `func show(correction: LearnedCorrection, entryID: String?)`; `var onUndo: ((String) -> Void)?`.

- [ ] **Step 1: Implement** — a non-activating borderless `NSPanel` in the overlay zone (mirror `AskBubbleWindow`'s panel setup: `[.borderless, .nonactivatingPanel]`, `.floating`, clear background, `FirstMouseHostingView`). SwiftUI content shows `Learned "<from>" → "<to>"` and an Undo button with a 5 s countdown ring (a `Timer`-driven progress). Undo within 5 s → `onUndo?(entryID)` + hide; else auto-hide at 5 s. A new `show(...)` replaces the current toast (the prior auto-commits).
- [ ] **Step 2: Wire** `onUndo = { [weak self] id in self?.model?.removeDictionaryEntry(id: id) }` in `AppDelegate`.
- [ ] **Step 3: Build** — clean.
- [ ] **Step 4: Manual verify** — trigger a learn; toast appears, countdown runs, click Undo within 5 s → entry removed; ignore → entry stays. Doesn't steal focus from the active app.
- [ ] **Step 5: Commit** — `git commit -am "feat(dictionary): LearnedWordToast with 5s undo"`

---

### Task 9: Teach-chip fallback

**Files:**
- Modify: `Sources/OmniVoiceApp/HotkeyController.swift` (+ `OmniVoicePreferences` for a `teachCorrectionHotkey` binding, default ⌃⌥T), `Sources/OmniVoiceApp/AppDelegate.swift`
- Create: `Sources/OmniVoiceApp/TeachCorrectionWindow.swift`

**Interfaces:**
- Consumes: the last `InsertionReceipt` (Task 7), `AppModel.upsertLearnedCorrection` (Task 6).
- Produces: a small panel pre-filled with the last inserted text; the user edits it; on submit, compute `LearnedCorrection(from: lastInserted, to: edited)` and upsert (same toast path). Works even when AX value reading didn't.

- [ ] **Step 1: Implement** the hotkey (mirror the existing bubble-action hotkey registration pattern) + the panel.
- [ ] **Step 2: Build** — clean.
- [ ] **Step 3: Manual verify** in an app where auto-detect doesn't fire (a web field): press the hotkey after a dictation, correct the word, confirm it's learned.
- [ ] **Step 4: Commit** — `git commit -am "feat(dictionary): teach-correction fallback hotkey + panel"`

---

### Task 10: Settings — Learned Words + master toggle

**Files:**
- Modify: `Sources/OmniVoiceApp/SettingsView.swift` (`dictionarySection` @ ~1728)

**Interfaces:**
- Consumes: `model.preferences.dictionaryEntries`, `autoLearnCorrectionsEnabled`, AppModel mutators (Task 6).

- [ ] **Step 1: Implement** — keep the existing manual-terms `TextEditor` (it now reads/writes manual canonicals via the computed `dictionaryTerms`; verify `setDictionaryTermsText` rebuilds `.manual` entries without clobbering `.learned` ones — update it to merge). Add a `Toggle("Automatically learn my corrections", isOn: bound to autoLearn)`. Add a "Learned Words" list: `ForEach(model.preferences.dictionaryEntries.filter { $0.source == .learned })` showing `canonical`, aliases, with per-row disable toggle + Remove (calling `updateDictionaryEntry` / `removeDictionaryEntry`).
- [ ] **Step 2: Build** — clean; `swift test` green.
- [ ] **Step 3: Manual verify** — learned words show up, removable; master toggle persists; manual terms still editable and don't wipe learned ones.
- [ ] **Step 4: Commit** — `git commit -am "feat(dictionary): Settings Learned Words list + auto-learn toggle"`

---

## Self-review

- **Spec coverage:** data model (T1), migration (T2), classifier+precision (T3), engine apply (T4), send-to-engine (T5), upsert+mutators (T6), AX watcher (T7), undo toast (T8), teach-chip (T9), Settings (T10). All spec sections covered.
- **Type consistency:** `DictionaryEntry`, `DictionarySource`, `LearnedCorrection`, `CorrectionClassifier.classify(before:after:insertedRange:)`, `DictionaryStore.upsert`, `AppModel.upsertLearnedCorrection`/`removeDictionaryEntry`/`updateDictionaryEntry`/`setAutoLearnEnabled` used consistently across tasks.
- **Note for executor:** Task 2 is the riskiest (central Codable surgery) — run the FULL `swift test` after it, and grep `dictionaryTerms:` to fix every construction site. `setDictionaryTermsText` (T10) must merge manual canonicals into `dictionaryEntries` without dropping `.learned` entries.
