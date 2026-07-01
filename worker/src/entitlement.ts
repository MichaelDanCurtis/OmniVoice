import type { Context } from 'hono'
import type { Env } from './env'
import { trialDays } from './env'
import { verifyWorkosToken, workosJwks } from './workos'

/// A user's trial + subscription facts, joined from the `users` and `entitlements` tables.
export interface EntitlementRow {
  trialStartedAt: number | null
  subStatus: string | null // 'active' | 'canceled' | 'none' | null
  currentPeriodEnd: number | null
}

export interface EntitlementResult {
  status: 'active' | 'trialing' | 'expired' | 'none'
  trialEndsAt?: number
  currentPeriodEnd?: number
}

/// Pure entitlement computation. An active subscription (or a canceled one still within
/// its paid period) wins; otherwise an in-window no-card trial; otherwise expired.
export function computeStatus(row: EntitlementRow | null, nowSeconds: number, days: number): EntitlementResult {
  if (!row) return { status: 'none' }

  const activeSub = row.subStatus === 'active'
  const inCanceledGrace =
    row.subStatus === 'canceled' && row.currentPeriodEnd != null && nowSeconds < row.currentPeriodEnd
  if (activeSub || inCanceledGrace) {
    return row.currentPeriodEnd != null
      ? { status: 'active', currentPeriodEnd: row.currentPeriodEnd }
      : { status: 'active' }
  }

  if (row.trialStartedAt != null) {
    const trialEndsAt = row.trialStartedAt + days * 86_400
    if (nowSeconds < trialEndsAt) {
      return { status: 'trialing', trialEndsAt }
    }
  }

  return { status: 'expired' }
}

export async function readEntitlementRow(db: D1Database, userId: string): Promise<EntitlementRow | null> {
  const row = await db
    .prepare(
      `SELECT u.trial_started_at   AS trialStartedAt,
              e.status             AS subStatus,
              e.current_period_end AS currentPeriodEnd
         FROM users u
         LEFT JOIN entitlements e ON e.workos_user_id = u.workos_user_id
        WHERE u.workos_user_id = ?`,
    )
    .bind(userId)
    .first<EntitlementRow>()
  return row ?? null
}

/// GET /entitlement — Bearer WorkOS token → verify → read D1 → compute → JSON.
export async function handleEntitlement(c: Context<{ Bindings: Env }>): Promise<Response> {
  const header = c.req.header('Authorization') ?? ''
  const token = header.startsWith('Bearer ') ? header.slice('Bearer '.length) : ''
  if (!token) return c.json({ error: 'unauthorized' }, 401)

  let userId: string
  try {
    const payload = await verifyWorkosToken(token, workosJwks(c.env.WORKOS_CLIENT_ID))
    if (!payload.sub) return c.json({ error: 'unauthorized' }, 401)
    userId = payload.sub
  } catch {
    return c.json({ error: 'unauthorized' }, 401)
  }

  const row = await readEntitlementRow(c.env.DB, userId)
  const nowSeconds = Math.floor(Date.now() / 1000)
  return c.json(computeStatus(row, nowSeconds, trialDays(c.env)))
}
