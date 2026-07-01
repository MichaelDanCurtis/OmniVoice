/// <reference types="@cloudflare/workers-types" />

/// Worker bindings + secrets. `DB` is the D1 binding; the rest are secrets set via
/// `wrangler secret put` (except TRIAL_DAYS, a plain var).
export interface Env {
  DB: D1Database
  TRIAL_DAYS: string
  WORKOS_API_KEY: string
  WORKOS_CLIENT_ID: string
  STRIPE_SECRET_KEY: string
  STRIPE_WEBHOOK_SECRET: string
  STRIPE_PRICE_ID: string
}

export function trialDays(env: Env): number {
  const parsed = Number.parseInt(env.TRIAL_DAYS ?? '', 10)
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 14
}
