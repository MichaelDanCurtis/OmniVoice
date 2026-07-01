import { describe, it, expect } from 'vitest'
import { createHmac } from 'node:crypto'
import { verifyStripeSignature } from '../src/stripe-signature'
import { reduceWebhookEvent, applyWebhookOutcome, mapStripeStatus, type StripeEvent } from '../src/billing'
import { createTestDb } from './helpers/d1'

const SECRET = 'whsec_test'
const now = 1_700_000_000

function signedHeader(payload: string, timestamp: number, secret = SECRET): string {
  const signature = createHmac('sha256', secret).update(`${timestamp}.${payload}`).digest('hex')
  return `t=${timestamp},v1=${signature}`
}

describe('verifyStripeSignature', () => {
  it('accepts a correctly signed, in-tolerance payload', async () => {
    const payload = '{"hello":"world"}'
    const header = signedHeader(payload, now)
    expect(await verifyStripeSignature(payload, header, SECRET, now)).toBe(true)
  })

  it('rejects a wrong signature', async () => {
    const payload = '{"hello":"world"}'
    const header = `t=${now},v1=deadbeef`
    expect(await verifyStripeSignature(payload, header, SECRET, now)).toBe(false)
  })

  it('rejects a signature from a different secret', async () => {
    const payload = '{"hello":"world"}'
    const header = signedHeader(payload, now, 'whsec_other')
    expect(await verifyStripeSignature(payload, header, SECRET, now)).toBe(false)
  })

  it('rejects a stale timestamp beyond tolerance', async () => {
    const payload = '{"hello":"world"}'
    const header = signedHeader(payload, now - 10_000)
    expect(await verifyStripeSignature(payload, header, SECRET, now)).toBe(false)
  })
})

describe('mapStripeStatus', () => {
  it('maps active/trialing to active and terminal states to canceled', () => {
    expect(mapStripeStatus('active')).toBe('active')
    expect(mapStripeStatus('trialing')).toBe('active')
    expect(mapStripeStatus('canceled')).toBe('canceled')
    expect(mapStripeStatus('past_due')).toBe('canceled')
    expect(mapStripeStatus('something_else')).toBe('none')
  })
})

describe('reduceWebhookEvent', () => {
  it('reduces a subscription update to an active outcome with the period end', () => {
    const event: StripeEvent = {
      type: 'customer.subscription.updated',
      data: { object: { customer: 'cus_1', status: 'active', current_period_end: now + 30 * 86_400 } },
    }
    expect(reduceWebhookEvent(event)).toEqual({
      kind: 'subscription',
      customerId: 'cus_1',
      status: 'active',
      currentPeriodEnd: now + 30 * 86_400,
    })
  })

  it('reduces a subscription deletion to canceled', () => {
    const event: StripeEvent = {
      type: 'customer.subscription.deleted',
      data: { object: { customer: 'cus_1', current_period_end: now + 5 * 86_400 } },
    }
    expect(reduceWebhookEvent(event)).toEqual({
      kind: 'subscription',
      customerId: 'cus_1',
      status: 'canceled',
      currentPeriodEnd: now + 5 * 86_400,
    })
  })

  it('ignores unrelated events', () => {
    expect(reduceWebhookEvent({ type: 'invoice.paid', data: { object: {} } })).toBeNull()
  })
})

describe('applyWebhookOutcome', () => {
  async function seedUser(db: ReturnType<typeof createTestDb>, customerId: string) {
    await db
      .prepare('INSERT INTO users (workos_user_id, email, stripe_customer_id, trial_started_at, created_at) VALUES (?, ?, ?, ?, ?)')
      .bind('user_1', 'a@b.co', customerId, now - 40 * 86_400, now - 40 * 86_400)
      .run()
  }

  it('writes an active entitlement for a subscription update', async () => {
    const db = createTestDb()
    await seedUser(db, 'cus_1')
    const outcome = reduceWebhookEvent({
      type: 'customer.subscription.updated',
      data: { object: { customer: 'cus_1', status: 'active', current_period_end: now + 30 * 86_400 } },
    })!
    await applyWebhookOutcome(db, outcome, now)

    const row = await db
      .prepare('SELECT status, current_period_end AS cpe FROM entitlements WHERE workos_user_id = ?')
      .bind('user_1')
      .first<{ status: string; cpe: number }>()
    expect(row).toEqual({ status: 'active', cpe: now + 30 * 86_400 })
  })

  it('writes a canceled entitlement for a subscription deletion', async () => {
    const db = createTestDb()
    await seedUser(db, 'cus_1')
    const outcome = reduceWebhookEvent({
      type: 'customer.subscription.deleted',
      data: { object: { customer: 'cus_1', current_period_end: now + 5 * 86_400 } },
    })!
    await applyWebhookOutcome(db, outcome, now)

    const row = await db
      .prepare('SELECT status FROM entitlements WHERE workos_user_id = ?')
      .bind('user_1')
      .first<{ status: string }>()
    expect(row?.status).toBe('canceled')
  })

  it('links the Stripe customer to the user on checkout completion', async () => {
    const db = createTestDb()
    await db
      .prepare('INSERT INTO users (workos_user_id, email, trial_started_at, created_at) VALUES (?, ?, ?, ?)')
      .bind('user_2', 'c@d.co', now, now)
      .run()
    const outcome = reduceWebhookEvent({
      type: 'checkout.session.completed',
      data: { object: { customer: 'cus_99', client_reference_id: 'user_2' } },
    })!
    await applyWebhookOutcome(db, outcome, now)

    const row = await db
      .prepare('SELECT stripe_customer_id AS id FROM users WHERE workos_user_id = ?')
      .bind('user_2')
      .first<{ id: string }>()
    expect(row?.id).toBe('cus_99')
  })
})
