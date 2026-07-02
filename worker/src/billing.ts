import type { Context } from 'hono'
import type { Env } from './env'
import { authenticatedUserId } from './workos'
import { verifyStripeSignature } from './stripe-signature'

type EntitlementStatus = 'active' | 'canceled' | 'none'

export interface StripeEvent {
  type: string
  data: { object: Record<string, unknown> }
}

/// What a webhook event means for our `entitlements`/`users` tables.
export interface WebhookOutcome {
  kind: 'subscription' | 'checkout'
  customerId: string
  userId?: string // checkout: client_reference_id → links customer to user
  status?: EntitlementStatus
  currentPeriodEnd?: number | null
}

/// Collapses Stripe subscription statuses into our two entitlement states.
export function mapStripeStatus(status: string): EntitlementStatus {
  switch (status) {
    case 'active':
    case 'trialing':
      return 'active'
    case 'canceled':
    case 'unpaid':
    case 'past_due':
    case 'incomplete_expired':
      return 'canceled'
    default:
      return 'none'
  }
}

/// Pure: maps a Stripe event to the entitlement change to persist (or null to ignore).
export function reduceWebhookEvent(event: StripeEvent): WebhookOutcome | null {
  const object = event.data?.object ?? {}
  const customer = object['customer']
  switch (event.type) {
    case 'checkout.session.completed': {
      if (typeof customer !== 'string') return null
      const reference = object['client_reference_id']
      return { kind: 'checkout', customerId: customer, userId: typeof reference === 'string' ? reference : undefined }
    }
    case 'customer.subscription.updated': {
      if (typeof customer !== 'string') return null
      const periodEnd = object['current_period_end']
      return {
        kind: 'subscription',
        customerId: customer,
        status: mapStripeStatus(String(object['status'] ?? '')),
        currentPeriodEnd: typeof periodEnd === 'number' ? periodEnd : null,
      }
    }
    case 'customer.subscription.deleted': {
      if (typeof customer !== 'string') return null
      const periodEnd = object['current_period_end']
      return {
        kind: 'subscription',
        customerId: customer,
        status: 'canceled',
        currentPeriodEnd: typeof periodEnd === 'number' ? periodEnd : null,
      }
    }
    default:
      return null
  }
}

/// Applies a reduced outcome to D1: checkout links the customer to the user; a
/// subscription event upserts the user's entitlement row.
export async function applyWebhookOutcome(db: D1Database, outcome: WebhookOutcome, nowSeconds: number): Promise<void> {
  if (outcome.kind === 'checkout') {
    if (outcome.userId) {
      await db
        .prepare('UPDATE users SET stripe_customer_id = ? WHERE workos_user_id = ?')
        .bind(outcome.customerId, outcome.userId)
        .run()
    }
    return
  }

  const user = await db
    .prepare('SELECT workos_user_id AS userId FROM users WHERE stripe_customer_id = ?')
    .bind(outcome.customerId)
    .first<{ userId: string }>()
  if (!user) return

  await db
    .prepare(
      `INSERT INTO entitlements (workos_user_id, status, current_period_end, updated_at)
       VALUES (?, ?, ?, ?)
       ON CONFLICT(workos_user_id) DO UPDATE SET
         status = excluded.status,
         current_period_end = excluded.current_period_end,
         updated_at = excluded.updated_at`,
    )
    .bind(user.userId, outcome.status ?? 'none', outcome.currentPeriodEnd ?? null, nowSeconds)
    .run()
}

async function stripePost(env: Env, path: string, params: Record<string, string>): Promise<Record<string, unknown>> {
  const response = await fetch(`https://api.stripe.com/v1/${path}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.STRIPE_SECRET_KEY}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams(params).toString(),
  })
  if (!response.ok) {
    throw new Error(`stripe_${path}_failed_${response.status}`)
  }
  return (await response.json()) as Record<string, unknown>
}

async function ensureStripeCustomer(env: Env, userId: string): Promise<string> {
  const existing = await env.DB.prepare('SELECT stripe_customer_id AS id FROM users WHERE workos_user_id = ?')
    .bind(userId)
    .first<{ id: string | null }>()
  if (existing?.id) return existing.id

  const customer = await stripePost(env, 'customers', { 'metadata[workos_user_id]': userId })
  const customerId = String(customer['id'])
  await env.DB.prepare('UPDATE users SET stripe_customer_id = ? WHERE workos_user_id = ?').bind(customerId, userId).run()
  return customerId
}

/// POST /billing/checkout — returns a Stripe Checkout URL for the signed-in user.
export async function handleCheckout(c: Context<{ Bindings: Env }>): Promise<Response> {
  const userId = await authenticatedUserId(c)
  if (!userId) return c.json({ error: 'unauthorized' }, 401)

  const customerId = await ensureStripeCustomer(c.env, userId)
  const session = await stripePost(c.env, 'checkout/sessions', {
    mode: 'subscription',
    customer: customerId,
    'line_items[0][price]': c.env.STRIPE_PRICE_ID,
    'line_items[0][quantity]': '1',
    client_reference_id: userId,
    success_url: 'https://omnispeak.app/billing/success',
    cancel_url: 'https://omnispeak.app/billing/cancel',
  })
  return c.json({ url: session['url'] })
}

/// POST /billing/portal — returns a Stripe billing-portal URL for the signed-in user.
export async function handlePortal(c: Context<{ Bindings: Env }>): Promise<Response> {
  const userId = await authenticatedUserId(c)
  if (!userId) return c.json({ error: 'unauthorized' }, 401)

  const customerId = await ensureStripeCustomer(c.env, userId)
  const session = await stripePost(c.env, 'billing_portal/sessions', {
    customer: customerId,
    return_url: 'https://omnispeak.app/account',
  })
  return c.json({ url: session['url'] })
}

/// POST /webhooks/stripe — signature-verified; applies subscription/checkout changes.
export async function handleStripeWebhook(c: Context<{ Bindings: Env }>): Promise<Response> {
  const payload = await c.req.text()
  const signature = c.req.header('Stripe-Signature') ?? ''
  const nowSeconds = Math.floor(Date.now() / 1000)

  const valid = await verifyStripeSignature(payload, signature, c.env.STRIPE_WEBHOOK_SECRET, nowSeconds)
  if (!valid) return c.json({ error: 'invalid_signature' }, 400)

  let event: StripeEvent
  try {
    event = JSON.parse(payload) as StripeEvent
  } catch {
    return c.json({ error: 'invalid_payload' }, 400)
  }

  const outcome = reduceWebhookEvent(event)
  if (outcome) await applyWebhookOutcome(c.env.DB, outcome, nowSeconds)
  return c.json({ received: true })
}
