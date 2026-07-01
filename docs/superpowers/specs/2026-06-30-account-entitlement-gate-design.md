# Account + Entitlement Gate — Design

**Date:** 2026-06-30
**Status:** Approved (design); pending implementation plan
**Scope:** Feature B of the three-part initiative. This spec covers login + entitlement gating.
Feature C (cloud sync) is a separate spec but reuses this feature's identity + Worker backend.

## Goal

Let users sign in and unlock the premium tier (Ask AI, Cloud sync, Live translation,
Conversation mode) with a **subscription**, offered via a **no-card free trial**. Free tier —
local dictation + local dictionary-learning — always works, signed in or not.

## Stack (decided)

- **WorkOS AuthKit** — identity (hosted login; upgradeable to SSO later for enterprise).
- **Stripe** — billing (subscription + trial; Stripe Tax for VAT).
- **Cloudflare Worker + D1** — the backend glue (verify WorkOS token, track trial/entitlement,
  handle Stripe webhooks, answer "is this user entitled?").
- **Desktop app** — `EntitlementService` gates the four premium features and caches the answer.

## Architecture

```
Desktop app ──login──►  WorkOS AuthKit (hosted)  ──loopback redirect──►  app
   app ──POST /auth/callback (code)──►  Worker ──exchange──►  WorkOS ──►  session ──►  app (Keychain)
Desktop app ──"Upgrade"──►  Worker /billing/checkout ──►  Stripe Checkout (browser)
Stripe  ──POST /webhooks/stripe──►  Worker  ──►  D1 (entitlement keyed by workos_user_id)
Desktop app ──GET /entitlement (WorkOS token)──►  Worker  ──►  { status, trialEndsAt }  (cached + 7d grace)
Premium feature invoked → EntitlementService.isEntitled(to:) → allow, or show paywall.
```

## 1. Entitlement model

```swift
enum EntitlementStatus: Equatable {
    case none                       // signed out / unknown
    case trialing(endsAt: Date)
    case active
    case expired
}
```
- **Entitled = `trialing` OR `active`.**
- **No-card trial:** on first successful login the Worker stamps `trial_started_at` in D1; the
  trial runs `TRIAL_DAYS` (14) with no card required. During it, all premium features unlock.
- **Subscribe:** Stripe Checkout → webhook flips D1 to `active` (with `current_period_end`).
- **Source of truth is the Worker.** The app never computes entitlement itself; it fetches and
  **caches** the last answer (see §3 grace).

## 2. Login flow (loopback)

1. App starts a throwaway `http://127.0.0.1:<ephemeral-port>/callback` listener and opens the
   system browser to the WorkOS AuthKit authorization URL with `redirect_uri` = that loopback
   (and a random `state`).
2. User signs in; WorkOS redirects to the loopback with `?code=…&state=…`; the listener captures
   it and serves a "You can close this tab" page, then shuts down.
3. App `POST /auth/callback { code }` → **Worker** exchanges the code with WorkOS (using the
   server-side API key) → returns the session (WorkOS access token + refresh token + user info).
4. App stores the session in the **Keychain** (`AuthSessionStore`, mirrors `LLMSecretStore`).
5. **Refresh:** when the access token nears expiry, `POST /auth/refresh { refreshToken }` → new
   session. **Sign out** clears the Keychain session and local entitlement cache.

The WorkOS API secret lives only in the Worker — the app only ever holds the user's own session
tokens.

## 3. The gate (client)

- **`EntitlementService`** (`@MainActor`, App) holds `status: EntitlementStatus`, refreshes from
  the Worker on launch, on app-foreground, and on a periodic timer. Injected with an
  `EntitlementProviding` protocol (real = Worker HTTP client; stub = tests), and an injectable
  clock so grace/trial math is deterministic in tests.
- **`PremiumFeature`** — `.askAI`, `.cloudSync`, `.liveTranslation`, `.conversationMode`.
  `isEntitled(to:) -> Bool` (all four gate on the same subscription for v1).
- **Gate points** (one check each, show paywall if not entitled):
  - `AskController.handle` — before routing an "ask …" command.
  - Enabling / using live translation.
  - Starting a conversation recording.
  - Cloud sync (feature C).
- **Paywall UX** — invoking a locked feature opens a paywall sheet: "Premium feature — start your
  free trial" (or "Subscribe"). Plus a Settings **"Account"** section: current status
  ("Trial — N days left" / "Subscribed" / "Expired"), and Sign in / Upgrade / Manage-billing
  buttons (Upgrade → `/billing/checkout` URL in browser; Manage → `/billing/portal`).
- **Offline grace:** cache the last entitlement answer + fetch timestamp (in preferences; the
  session token is in Keychain). If the Worker is unreachable, keep honoring the cached
  entitled status for a **7-day grace window**, then re-lock. Prevents offline lockout and
  indefinite post-cancel access.

## 4. Backend (Cloudflare Worker + D1)

**Endpoints** (all JSON; auth'd ones require the WorkOS access token as a Bearer, verified
offline against WorkOS JWKS):
- `POST /auth/callback { code }` → exchange with WorkOS; upsert `users` row; stamp
  `trial_started_at` if new; return session + user.
- `POST /auth/refresh { refreshToken }` → new session.
- `GET /entitlement` → verify token; compute `active` (Stripe sub active) else `trialing`
  (now < trial_started_at + TRIAL_DAYS) else `expired`/`none`; return `{ status, trialEndsAt,
  currentPeriodEnd }`.
- `POST /billing/checkout` → create a Stripe Checkout session for the user's
  `stripe_customer_id` (create the customer if absent); return the URL.
- `POST /billing/portal` → Stripe billing-portal URL.
- `POST /webhooks/stripe` → **Stripe-signature-verified**; on
  `checkout.session.completed` / `customer.subscription.updated` / `.deleted`, update the
  `entitlements` row (status + current_period_end).

**D1 schema:**
```sql
CREATE TABLE users (
  workos_user_id   TEXT PRIMARY KEY,
  email            TEXT,
  stripe_customer_id TEXT,
  trial_started_at INTEGER,   -- epoch seconds
  created_at       INTEGER
);
CREATE TABLE entitlements (
  workos_user_id     TEXT PRIMARY KEY,
  status             TEXT,     -- 'active' | 'canceled' | 'none'
  current_period_end INTEGER,
  updated_at         INTEGER
);
```

**Worker secrets:** `WORKOS_API_KEY`, `WORKOS_CLIENT_ID`, `STRIPE_SECRET_KEY`,
`STRIPE_WEBHOOK_SECRET`, `TRIAL_DAYS` (config).

## 5. Buildable now vs. blocked on provisioning

- **Buildable this session (no live backend):** the entire **client** — `EntitlementService`,
  `PremiumFeature`, the four gate points, the paywall sheet, the Settings Account section, the
  `AuthSessionStore` (Keychain), and the loopback-callback listener — against a stub
  `EntitlementProviding`. Compiles and the gate/cache/grace/trial logic is unit-tested with an
  injected clock. The Worker's TypeScript can be written with miniflare/vitest tests.
- **Blocked on the account holder (provisioning, cannot be scripted here — the WorkOS/Stripe/
  Cloudflare connectors are not authorized in this session):**
  1. Create a **WorkOS** application + AuthKit; note client id; allow the loopback redirect.
  2. Create a **Stripe** product + recurring price; add the webhook endpoint + signing secret.
  3. Create a **Cloudflare** Worker + D1; apply the schema; set the Worker secrets; deploy.
  4. Point the app's `EntitlementProviding` real impl at the deployed Worker URL.

## 6. Error handling & edge cases
- Worker unreachable at launch → use cached status within the 7-day grace; past grace → re-lock
  (features off) but never crash; local dictation unaffected.
- Token expired → auto-refresh once; if refresh fails → signed-out state (premium locked).
- Trial already used (returning user) → `trial_started_at` persists in D1; a re-login doesn't
  restart it.
- User cancels in Stripe → webhook sets status canceled; `current_period_end` honored until it
  passes (they keep access through the paid period), then `expired`.
- Loopback listener: bind to `127.0.0.1` only, random port, single-use, short timeout; validate
  `state` to prevent CSRF.

## 7. Testing
- **Unit (Core/App, with stub + injected clock):** `EntitlementService` status transitions,
  `isEntitled(to:)` per feature, cache read/write, 7-day grace expiry, trial-window math.
- **Worker (miniflare/vitest):** entitlement computation, Stripe webhook → D1 updates, JWKS
  verification, checkout/portal URL creation.
- **Manual/integration:** the loopback login round-trip, Stripe Checkout, the paywall + Account
  UI.

## Out of scope (future)
- **Feature C** — cloud sync of dictionary/prefs (uses this feature's identity + Worker; adds
  `/sync`).
- Per-feature SKUs / multiple tiers (v1 is one premium tier, all-or-nothing).
- Team licenses / WorkOS SSO / Directory Sync (the upgrade path AuthKit preserves).
- Receipt/paywall localization, promo codes.
