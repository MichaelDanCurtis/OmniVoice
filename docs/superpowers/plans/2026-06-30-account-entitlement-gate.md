# Account + Entitlement Gate — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sign in with WorkOS AuthKit and gate the four premium features (Ask AI, cloud sync, live translation, conversation mode) behind a subscription with a no-card free trial; free tier (local dictation + dictionary learning) always works.

**Architecture:** A pure `EntitlementService` (App) gates features via an injected `EntitlementProviding` protocol; the real provider talks to a Cloudflare Worker (WorkOS token exchange, entitlement, Stripe billing) backed by D1. Client tasks build + unit-test now against a stub; the Worker is written with tests but deployed only after account provisioning.

**Tech Stack:** Swift 6 SwiftPM (`OmniVoiceCore` + `OmniVoiceApp`), Keychain (Security), XCTest; Cloudflare Workers (TypeScript, wrangler) + D1 + vitest/miniflare; WorkOS AuthKit; Stripe.

## Global Constraints

- **Free tier always works** — local dictation + dictionary learning are never gated. Only `.askAI`, `.cloudSync`, `.liveTranslation`, `.conversationMode` gate.
- **Entitled = `trialing` OR `active`.** Trial is **no-card**, `TRIAL_DAYS = 14`, stamped server-side on first login.
- **Worker is source of truth**; the app caches the last answer with a **7-day offline grace**.
- **WorkOS API secret + Stripe secret live ONLY in the Worker.** The app holds only the user's own session tokens (Keychain).
- All entitlement/grace/trial math takes an **injected clock** (`() -> Date`) so it's deterministic in tests.
- **Provisioning is blocked** (WorkOS/Stripe/Cloudflare accounts + connector auth not available this session): client tasks (1–6) execute now; Worker tasks (7–10) are written + unit-tested but not deployed; task 11 (real provider + runbook) is deploy-deferred.

---

### Task 1: Entitlement + premium-feature model (Core)

**Files:**
- Create: `Sources/OmniVoiceCore/Entitlement.swift`
- Test: `Tests/OmniVoiceCoreTests/EntitlementTests.swift`

**Interfaces:**
- Produces: `EntitlementStatus` (`.none`/`.trialing(endsAt:)`/`.active`/`.expired`), `var isEntitled: Bool`; `PremiumFeature` (`.askAI`/`.cloudSync`/`.liveTranslation`/`.conversationMode`); `EntitlementSnapshot { status: EntitlementStatus; fetchedAt: Date }` (Codable, for the cache).

- [ ] **Step 1: Write the failing test**
```swift
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
```
- [ ] **Step 2: Run to verify failure** — `swift test --filter EntitlementTests` → FAIL.
- [ ] **Step 3: Implement**
```swift
import Foundation

public enum EntitlementStatus: Codable, Equatable, Sendable {
    case none
    case trialing(endsAt: Date)
    case active
    case expired

    public var isEntitled: Bool {
        switch self {
        case .active, .trialing: return true
        case .none, .expired: return false
        }
    }
}

public enum PremiumFeature: String, CaseIterable, Sendable {
    case askAI
    case cloudSync
    case liveTranslation
    case conversationMode

    public var displayName: String {
        switch self {
        case .askAI: return "Ask AI"
        case .cloudSync: return "Cloud Sync"
        case .liveTranslation: return "Live Translation"
        case .conversationMode: return "Conversation Mode"
        }
    }
}

public struct EntitlementSnapshot: Codable, Equatable, Sendable {
    public var status: EntitlementStatus
    public var fetchedAt: Date
    public init(status: EntitlementStatus, fetchedAt: Date) {
        self.status = status
        self.fetchedAt = fetchedAt
    }
}
```
- [ ] **Step 4: Run** — `swift test --filter EntitlementTests` → PASS.
- [ ] **Step 5: Commit** — `git commit -am "feat(entitlement): status + premium-feature model"`

---

### Task 2: Entitlement gate logic (Core, pure)

**Files:**
- Create: `Sources/OmniVoiceCore/EntitlementGate.swift`
- Test: `Tests/OmniVoiceCoreTests/EntitlementGateTests.swift`

**Interfaces:**
- Consumes: Task 1 types.
- Produces: `EntitlementGate.effectiveStatus(cached: EntitlementSnapshot?, now: Date, graceDays: Int = 7) -> EntitlementStatus` — pure: returns the cached status while entitled & within trial window & within grace; downgrades a stale/expired cache to `.expired`. This is the offline-grace + trial-expiry heart.

- [ ] **Step 1: Write the failing tests**
```swift
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
        XCTAssertEqual(EntitlementGate.effectiveStatus(cached: cached, now: days(6)), .expired) // trial ended
    }
    func testTrialingWithinWindowAndGrace() {
        let cached = EntitlementSnapshot(status: .trialing(endsAt: days(10)), fetchedAt: days(4))
        XCTAssertEqual(EntitlementGate.effectiveStatus(cached: cached, now: days(6)),
                       .trialing(endsAt: days(10)))
    }
    func testNoCacheIsNone() {
        XCTAssertEqual(EntitlementGate.effectiveStatus(cached: nil, now: t0), .none)
    }
}
```
- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement**
```swift
import Foundation

public enum EntitlementGate {
    public static func effectiveStatus(cached: EntitlementSnapshot?, now: Date, graceDays: Int = 7) -> EntitlementStatus {
        guard let cached else { return .none }
        // Trial expiry is authoritative regardless of grace.
        if case .trialing(let endsAt) = cached.status, now >= endsAt {
            return .expired
        }
        guard cached.status.isEntitled else { return cached.status }
        // Entitled cache is honored only within the offline grace window.
        let graceSeconds = Double(graceDays) * 86_400
        if now.timeIntervalSince(cached.fetchedAt) > graceSeconds {
            return .expired
        }
        return cached.status
    }
}
```
- [ ] **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** — `git commit -am "feat(entitlement): pure offline-grace + trial-expiry gate"`

---

### Task 3: EntitlementService + provider protocol (App)

**Files:**
- Create: `Sources/OmniVoiceApp/EntitlementService.swift`
- Test: `Tests/OmniVoiceCoreTests/` — N/A (App layer, untested target); the pure logic is covered by Tasks 1–2. Verify by build.

**Interfaces:**
- Consumes: Tasks 1–2, `EntitlementSnapshot` cache persisted via a new `preferences.entitlementSnapshotData: Data?` (add to `OmniVoicePreferences` following the Task-2-style Codable pattern from the dictionary feature — one stored optional, `decodeIfPresent`).
- Produces:
  ```swift
  protocol EntitlementProviding: Sendable {
      func fetchEntitlement() async throws -> EntitlementStatus   // real = Worker; stub = tests/dev
  }
  @MainActor final class EntitlementService: ObservableObject {
      @Published private(set) var status: EntitlementStatus
      init(provider: EntitlementProviding, cached: EntitlementSnapshot?, now: @escaping () -> Date = { Date() },
           persist: @escaping (EntitlementSnapshot) -> Void)
      func isEntitled(to feature: PremiumFeature) -> Bool   // status.isEntitled (all features, v1)
      func refresh() async                                   // fetch → update status + persist snapshot; on failure keep effectiveStatus(cached)
      var effectiveStatus: EntitlementStatus { get }
  }
  ```

- [ ] **Step 1: Implement** `EntitlementService`: on init, set `status = EntitlementGate.effectiveStatus(cached:, now:)`. `refresh()` calls `provider.fetchEntitlement()`; on success, `status = fetched`, build a new `EntitlementSnapshot(status: fetched, fetchedAt: now())`, call `persist`. On throw, recompute `status = EntitlementGate.effectiveStatus(cached: lastSnapshot, now:)` (offline grace). `isEntitled(to:)` returns `status.isEntitled`.
- [ ] **Step 2: Add** a `StubEntitlementProvider: EntitlementProviding` (in the same file, `#if DEBUG` or plain) returning `.trialing(endsAt: now + 14d)` so the app is fully usable in dev before the Worker exists.
- [ ] **Step 3: Add** `preferences.entitlementSnapshotData: Data?` to `OmniVoicePreferences` (stored optional; CodingKeys `entitlement_snapshot`; `decodeIfPresent`; NOT a secret → normal persistence). Build.
- [ ] **Step 4: Build** — `swift build` clean.
- [ ] **Step 5: Commit** — `git commit -am "feat(entitlement): EntitlementService + provider protocol + stub"`

---

### Task 4: AuthSessionStore (Keychain, App)

**Files:**
- Create: `Sources/OmniVoiceApp/AuthSessionStore.swift`

**Interfaces:**
- Produces: `AuthSession: Codable { accessToken, refreshToken, userId, email, expiresAt }`; `AuthSessionStore { func load() -> AuthSession?; func save(_:) throws; func delete() throws }` — Keychain, service `com.omnivoice.auth`, account `session`, JSON-encoded value. Mirror `HuggingFaceTokenStore` (SecItemUpdate → SecItemAdd fallback, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).

- [ ] **Step 1: Implement** `AuthSessionStore` by copying `HuggingFaceTokenStore`'s structure, storing `try JSONEncoder().encode(session)` as the `kSecValueData`, service `com.omnivoice.auth`, account `session`.
- [ ] **Step 2: Build** — clean.
- [ ] **Step 3: Commit** — `git commit -am "feat(auth): Keychain AuthSessionStore"`

---

### Task 5: Loopback login flow (App)

**Files:**
- Create: `Sources/OmniVoiceApp/AuthLoginController.swift`

**Interfaces:**
- Consumes: `AuthSessionStore` (T4), the Worker base URL (config; use a `WorkerConfig.baseURL` constant, default a placeholder until provisioned).
- Produces: `@MainActor final class AuthLoginController { func signIn() async throws -> AuthSession; func signOut() }`. `signIn()`: start an `NWListener`/tiny HTTP listener on `127.0.0.1:<ephemeral>`, open `NSWorkspace.shared.open(authKitURL(redirect: loopback, state: random))`, await the `?code&state` callback (validate `state`), serve a "you can close this tab" response, then `POST {workerBase}/auth/callback {code}` → decode `AuthSession` → `store.save`. `signOut()`: `store.delete()` + clear entitlement snapshot.

- [ ] **Step 1: Implement** the loopback listener (bind 127.0.0.1, ephemeral port, single request, 120s timeout, validate `state`), the AuthKit URL builder, and the code→session POST. Keep the WorkOS/Worker URLs behind `WorkerConfig` so the placeholder is swapped in Task 11.
- [ ] **Step 2: Build** — clean.
- [ ] **Step 3: Manual note** — full round-trip needs the Worker (Task 9) + WorkOS provisioning; buildable + structurally verifiable now.
- [ ] **Step 4: Commit** — `git commit -am "feat(auth): loopback WorkOS login flow"`

---

### Task 6: Gate points + paywall + Account settings (App)

**Files:**
- Modify: `Sources/OmniVoiceApp/AppDelegate.swift` (own the `EntitlementService`, `AuthLoginController`; refresh on launch/foreground), `Sources/OmniVoiceApp/AskController.swift:48` (gate `.askAI`), `Sources/OmniVoiceApp/AppModel.swift:1525` (gate `.liveTranslation` in `setLiveTranslationEnabled`) and `:2967` (gate `.conversationMode` in `startConversationRecording`), `Sources/OmniVoiceApp/SettingsView.swift` (Account section)
- Create: `Sources/OmniVoiceApp/PaywallWindow.swift`

**Interfaces:**
- Consumes: `EntitlementService.isEntitled(to:)`, `AuthLoginController`.
- Produces: a paywall presenter `func presentPaywall(for feature: PremiumFeature)`; a Settings "Account" section.

- [ ] **Step 1** — In `AppDelegate.attach`, create `EntitlementService(provider: <stub for now>, cached: decoded snapshot, persist: { model.setEntitlementSnapshot($0) })`; call `Task { await entitlementService.refresh() }` on launch + on `NSApplication.didBecomeActiveNotification`.
- [ ] **Step 2** — Gate each feature: at the entry of `AskController.handle` (only for the `.ask` case), `AppModel.setLiveTranslationEnabled(true)`, and `AppModel.startConversationRecording`, check `entitlementService.isEntitled(to:)`; if false, call `presentPaywall(for:)` and return without running the feature. (Cloud-sync gate lands in feature C.)
- [ ] **Step 3** — `PaywallWindow`: a small panel — "\(feature.displayName) is a premium feature" + "Start free trial / Subscribe" (opens `{workerBase}/billing/checkout` via login-then-checkout) + "Not now". Reuse the `FirstMouseHostingView`/non-activating-panel pattern where appropriate; the paywall may be titled (it's an explicit modal).
- [ ] **Step 4** — Settings "Account" section: show `entitlementService.status` ("Trial — N days left" / "Subscribed" / "Not subscribed"), Sign in/out, Upgrade (checkout URL), Manage billing (portal URL).
- [ ] **Step 5: Build** — `swift build` clean; `swift test` green (261 + Tasks 1–2 tests).
- [ ] **Step 6: Commit** — `git commit -am "feat(entitlement): gate premium features + paywall + Account settings"`

---

### Task 7: Worker scaffold + D1 schema (deploy-deferred)

**Files:**
- Create: `worker/wrangler.toml`, `worker/package.json`, `worker/tsconfig.json`, `worker/src/index.ts` (router), `worker/schema.sql`, `worker/vitest.config.ts`

**Interfaces:**
- Produces: a Hono (or itty-router) Worker with routes stubbed returning 501, a `D1` binding `DB`, and `schema.sql` exactly per spec §4 (`users`, `entitlements` tables). `TRIAL_DAYS` var.

- [ ] **Step 1** — Scaffold the TS project (wrangler.toml with `d1_databases` binding `DB`, `vars.TRIAL_DAYS = "14"`, secrets referenced but not committed). Router with the 6 routes returning 501.
- [ ] **Step 2** — `schema.sql` per spec §4.
- [ ] **Step 3** — `worker/README.md`: provisioning steps (create D1, `wrangler d1 execute --file schema.sql`, `wrangler secret put WORKOS_API_KEY` etc., `wrangler deploy`).
- [ ] **Step 4: Commit** — `git commit -am "feat(worker): scaffold + D1 schema (deploy-deferred)"`

---

### Task 8: Worker /entitlement + WorkOS JWT verify (deploy-deferred)

**Files:**
- Create: `worker/src/entitlement.ts`, `worker/src/workos.ts`, `worker/test/entitlement.test.ts`

**Interfaces:**
- Produces: `computeStatus(row, now, trialDays)` (pure: active-sub → `active`; within trial → `trialing(endsAt)`; else `expired`); `verifyWorkosToken(token, jwks)`; `GET /entitlement` handler.

- [ ] **Step 1: Write failing vitest** for `computeStatus` (active sub → active; `trial_started_at` + 14d in future → trialing with endsAt; past → expired) and JWT verify (valid signature passes, tampered fails).
- [ ] **Step 2: Implement** `computeStatus` (pure) + `verifyWorkosToken` (verify JWT against WorkOS JWKS via `jose`) + the handler (bearer token → verify → read D1 row → `computeStatus` → JSON `{ status, trialEndsAt, currentPeriodEnd }`).
- [ ] **Step 3: Run** `cd worker && npx vitest run` → PASS.
- [ ] **Step 4: Commit** — `git commit -am "feat(worker): /entitlement + WorkOS JWKS verify"`

---

### Task 9: Worker /auth/callback + /auth/refresh (deploy-deferred)

**Files:**
- Create: `worker/src/auth.ts`, `worker/test/auth.test.ts`

**Interfaces:**
- Produces: `POST /auth/callback { code }` → exchange code with WorkOS (`WORKOS_API_KEY`), upsert `users` (stamp `trial_started_at` if new), return `{ accessToken, refreshToken, userId, email, expiresAt }`; `POST /auth/refresh { refreshToken }` → new session.

- [ ] **Step 1: Write failing vitest** with a mocked WorkOS fetch: callback for a NEW user stamps `trial_started_at` once; a returning user's `trial_started_at` is unchanged.
- [ ] **Step 2: Implement** the handlers (WorkOS `authenticateWithCode` / refresh; D1 upsert with `INSERT ... ON CONFLICT DO NOTHING` for `trial_started_at`).
- [ ] **Step 3: Run vitest** → PASS.
- [ ] **Step 4: Commit** — `git commit -am "feat(worker): auth callback + refresh"`

---

### Task 10: Worker billing + Stripe webhook (deploy-deferred)

**Files:**
- Create: `worker/src/billing.ts`, `worker/test/billing.test.ts`

**Interfaces:**
- Produces: `POST /billing/checkout` (create/reuse Stripe customer, Checkout session, return URL); `POST /billing/portal`; `POST /webhooks/stripe` (verify signature; `checkout.session.completed`/`customer.subscription.updated`/`.deleted` → upsert `entitlements` status + `current_period_end`).

- [ ] **Step 1: Write failing vitest** with a mocked Stripe: a `customer.subscription.updated` (status active) event writes `entitlements.status='active'` + `current_period_end`; a `.deleted` writes `canceled`. Signature verification rejects a bad signature.
- [ ] **Step 2: Implement** the three handlers (Stripe SDK or REST; verify webhook via `STRIPE_WEBHOOK_SECRET`).
- [ ] **Step 3: Run vitest** → PASS.
- [ ] **Step 4: Commit** — `git commit -am "feat(worker): Stripe checkout/portal/webhook"`

---

### Task 11: Real provider + provisioning runbook (deploy-deferred wire-up)

**Files:**
- Create: `Sources/OmniVoiceApp/WorkerEntitlementProvider.swift`, `docs/ACCOUNT_ENTITLEMENT_RUNBOOK.md`
- Modify: `Sources/OmniVoiceApp/AppDelegate.swift` (swap the stub for `WorkerEntitlementProvider` behind a config flag once `WorkerConfig.baseURL` is set)

**Interfaces:**
- Produces: `WorkerEntitlementProvider: EntitlementProviding` — `GET {base}/entitlement` with the Keychain access token as Bearer, decode `{ status, trialEndsAt }` → `EntitlementStatus`.

- [ ] **Step 1: Implement** `WorkerEntitlementProvider` (URLSession GET, bearer, map JSON → `EntitlementStatus`; on 401 trigger a token refresh once).
- [ ] **Step 2** — In `AppDelegate`, select provider: `WorkerConfig.baseURL != nil ? WorkerEntitlementProvider(...) : StubEntitlementProvider()`.
- [ ] **Step 3** — Write `docs/ACCOUNT_ENTITLEMENT_RUNBOOK.md`: the exact provisioning steps (WorkOS app + AuthKit + loopback redirect allowed; Stripe product/price + webhook; `wrangler d1 create` + apply `schema.sql` + `wrangler secret put …` + `wrangler deploy`; set `WorkerConfig.baseURL`).
- [ ] **Step 4: Build** — clean.
- [ ] **Step 5: Commit** — `git commit -am "feat(entitlement): real Worker provider + provisioning runbook"`

---

## Self-review

- **Spec coverage:** model (T1), grace/trial gate (T2), service+cache+stub (T3), Keychain session (T4), loopback login (T5), gate points+paywall+Account (T6), Worker scaffold+D1 (T7), /entitlement+JWKS (T8), auth callback/refresh (T9), billing+webhook (T10), real provider+runbook (T11). All spec sections covered.
- **Type consistency:** `EntitlementStatus`/`PremiumFeature`/`EntitlementSnapshot` (T1) → `EntitlementGate.effectiveStatus` (T2) → `EntitlementProviding`/`EntitlementService.isEntitled(to:)` (T3) → gate points (T6) → `WorkerEntitlementProvider` (T11) consistent. Worker `computeStatus` (T8) mirrors the client trial/active semantics.
- **Note for executor:** Tasks 1–6 are the client and **execute now** (against `StubEntitlementProvider`; app fully usable in dev). Tasks 7–10 are the Worker — **write + unit-test with vitest, do NOT attempt to deploy** (no Cloudflare/WorkOS/Stripe provisioning this session). Task 11 wires the real provider + runbook, deploy-deferred. Add `entitlementSnapshotData` to `OmniVoicePreferences` the same careful way the dictionary migration was done (stored optional, decodeIfPresent, NOT a secret).
