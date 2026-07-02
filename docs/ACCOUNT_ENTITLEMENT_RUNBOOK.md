# Account + Entitlement — Provisioning Runbook

Feature B (account + entitlement gate) ships in two halves:

- **Client** (`Sources/OmniVoiceApp`, `Sources/OmniVoiceCore`) — built and tested. Until the
  backend is provisioned it runs on `StubEntitlementProvider` (a perpetual local trial), so
  premium features work in dev and sign-in throws `AuthError.notConfigured`.
- **Worker** (`worker/`) — written and unit-tested (`npm test`), **not deployed**.

This runbook is the account holder's checklist to go live. None of it can be scripted from the
agent session (the WorkOS / Stripe / Cloudflare connectors aren't authorized there).

## 1. WorkOS (identity)

1. Create a WorkOS application; enable **AuthKit**.
2. Note the **Client ID**.
3. Under redirect URIs, allow the loopback callback: `http://127.0.0.1` (any port) `/callback`.
   (WorkOS allows `http://127.0.0.1` redirects for native loopback flows.)
4. Create an **API key** (server-side secret).

## 2. Stripe (billing)

1. Create a **product** and a **recurring price**; note the **Price ID** (`price_…`).
2. Enable a **14-day free trial** on the price (or rely on the Worker's `trial_started_at`
   stamping — the app treats either as "trialing").
3. Add a **webhook endpoint** → `https://<worker-url>/webhooks/stripe`, subscribed to
   `checkout.session.completed`, `customer.subscription.updated`, `customer.subscription.deleted`.
   Note the **signing secret** (`whsec_…`).

## 3. Cloudflare Worker + D1

```sh
cd worker
npm install
npm test                       # 23 unit tests should pass

wrangler d1 create omnivoice   # paste the returned database_id into wrangler.toml
wrangler d1 execute omnivoice --file schema.sql

wrangler secret put WORKOS_API_KEY
wrangler secret put WORKOS_CLIENT_ID
wrangler secret put STRIPE_SECRET_KEY
wrangler secret put STRIPE_WEBHOOK_SECRET
wrangler secret put STRIPE_PRICE_ID

npm run deploy                 # wrangler deploy → note the deployed URL
```

## 4. Point the app at the Worker

In `Sources/OmniVoiceApp/AuthLoginController.swift`, set `WorkerConfig`:

```swift
enum WorkerConfig {
    static let baseURL: URL? = URL(string: "https://<worker-url>")   // was nil
    static let workosClientID: String? = "<your WorkOS client id>"   // was nil
    static let workosAuthorizationURL = URL(string: "https://api.workos.com/user_management/authorize")!
}
```

Setting `baseURL` flips `AppModel` from `StubEntitlementProvider` to `WorkerEntitlementProvider`
automatically (see `AppModel.makeEntitlementService()`), and enables real sign-in.

## 5. Verify end-to-end

1. Launch the app → Settings → Overview → **Account** → **Sign In**. The browser opens WorkOS
   hosted login; after signing in the tab shows "You can close this tab".
2. Account should show **Trial — N days left**; premium features (Ask AI, Live Translation,
   Conversation Mode) unlock.
3. Click **Upgrade** → complete Stripe Checkout → the webhook flips D1 to `active`; Account
   shows **Subscribed** after the next refresh (relaunch / app-foreground).
4. Cancel in **Manage Billing** → access continues until `current_period_end`, then re-locks.

## Notes

- The WorkOS API secret and Stripe secret live **only** in the Worker; the app holds just the
  user's own session tokens (Keychain, `com.omnispeak.auth`).
- Offline: the app honors the last entitlement answer for a 7-day grace window, then re-locks.
- Local dictation + dictionary learning are always free, signed in or not.
