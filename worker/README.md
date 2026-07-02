# OmniSpeak Account + Entitlement Worker

Cloudflare Worker backing feature B: verifies WorkOS sessions, tracks the no-card
trial + Stripe subscription in D1, and answers "is this user entitled?".

**Status: written, not deployed.** Deploy is blocked on provisioning (below). The macOS
app runs on a stub entitlement provider until `WorkerConfig.baseURL` is set in the app.

## Layout

- `src/index.ts` — Hono router.
- `src/entitlement.ts` — `computeStatus` (pure) + `GET /entitlement`.
- `src/workos.ts` — WorkOS code exchange, refresh, JWKS JWT verification.
- `src/auth.ts` — `POST /auth/callback`, `POST /auth/refresh`.
- `src/billing.ts` — Stripe checkout/portal + webhook reducer.
- `src/stripe-signature.ts` — Web Crypto HMAC verification of Stripe webhooks.
- `schema.sql` — D1 tables (`users`, `entitlements`).
- `test/` — vitest unit tests (pure logic; run under plain Node).

## Develop / test

```sh
npm install
npm run typecheck
npm test
```

## Provisioning (account holder — required before deploy)

1. **WorkOS**: create an application, enable AuthKit, note the **client id**, and allow the
   loopback redirect (`http://127.0.0.1:*/callback`). Create an API key.
2. **Stripe**: create a product + recurring price (note the **price id**). Add a webhook
   endpoint pointing at `<worker-url>/webhooks/stripe` for `checkout.session.completed`,
   `customer.subscription.updated`, `customer.subscription.deleted`; note the **signing secret**.
3. **Cloudflare D1**: `wrangler d1 create omnispeak`, paste the `database_id` into
   `wrangler.toml`, then `wrangler d1 execute omnispeak --file schema.sql`.
4. **Secrets**:
   ```sh
   wrangler secret put WORKOS_API_KEY
   wrangler secret put WORKOS_CLIENT_ID
   wrangler secret put STRIPE_SECRET_KEY
   wrangler secret put STRIPE_WEBHOOK_SECRET
   wrangler secret put STRIPE_PRICE_ID
   ```
5. **Deploy**: `npm run deploy` (`wrangler deploy`).
6. **Point the app at it**: set `WorkerConfig.baseURL` and `WorkerConfig.workosClientID`
   in `Sources/OmniSpeakApp/AuthLoginController.swift`.
