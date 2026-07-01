import type { Context } from 'hono'
import { decodeJwt } from 'jose'
import type { Env } from './env'

interface WorkosAuthResponse {
  user: { id: string; email: string }
  access_token: string
  refresh_token: string
}

/// The session shape the macOS app decodes (mirrors Swift `AuthSession`; `expiresAt` epoch seconds).
export interface SessionResponse {
  accessToken: string
  refreshToken: string
  userId: string
  email: string
  expiresAt: number
}

const WORKOS_AUTHENTICATE_URL = 'https://api.workos.com/user_management/authenticate'

/// Exchanges a grant with WorkOS User Management. `body` supplies the grant-specific
/// fields (authorization_code or refresh_token). Injectable `fetchImpl` for tests.
export async function authenticateWithWorkos(
  env: Env,
  body: Record<string, string>,
  fetchImpl: typeof fetch = fetch,
): Promise<WorkosAuthResponse> {
  const response = await fetchImpl(WORKOS_AUTHENTICATE_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      client_id: env.WORKOS_CLIENT_ID,
      client_secret: env.WORKOS_API_KEY,
      ...body,
    }),
  })
  if (!response.ok) {
    throw new Error(`workos_authenticate_failed_${response.status}`)
  }
  return (await response.json()) as WorkosAuthResponse
}

/// Maps a WorkOS response to the app session, deriving `expiresAt` from the access token's
/// `exp` claim (fallback: +5 min).
export function toSession(auth: WorkosAuthResponse): SessionResponse {
  const claims = decodeJwt(auth.access_token)
  const expiresAt = typeof claims.exp === 'number' ? claims.exp : Math.floor(Date.now() / 1000) + 300
  return {
    accessToken: auth.access_token,
    refreshToken: auth.refresh_token,
    userId: auth.user.id,
    email: auth.user.email,
    expiresAt,
  }
}

/// Upserts the user, stamping `trial_started_at` exactly once (the ON CONFLICT clause
/// updates only the email, so a returning user's trial start is preserved).
export async function upsertUserStampingTrial(
  db: D1Database,
  user: { id: string; email: string },
  nowSeconds: number,
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO users (workos_user_id, email, trial_started_at, created_at)
       VALUES (?, ?, ?, ?)
       ON CONFLICT(workos_user_id) DO UPDATE SET email = excluded.email`,
    )
    .bind(user.id, user.email, nowSeconds, nowSeconds)
    .run()
}

/// POST /auth/callback { code } → exchange, stamp trial, return session.
export async function handleAuthCallback(c: Context<{ Bindings: Env }>): Promise<Response> {
  const body = await c.req.json<{ code?: string }>().catch(() => ({}) as { code?: string })
  if (!body.code) return c.json({ error: 'missing_code' }, 400)

  let auth: WorkosAuthResponse
  try {
    auth = await authenticateWithWorkos(c.env, { grant_type: 'authorization_code', code: body.code })
  } catch {
    return c.json({ error: 'authentication_failed' }, 401)
  }

  await upsertUserStampingTrial(c.env.DB, auth.user, Math.floor(Date.now() / 1000))
  return c.json(toSession(auth))
}

/// POST /auth/refresh { refreshToken } → new session.
export async function handleAuthRefresh(c: Context<{ Bindings: Env }>): Promise<Response> {
  const body = await c.req.json<{ refreshToken?: string }>().catch(() => ({}) as { refreshToken?: string })
  if (!body.refreshToken) return c.json({ error: 'missing_refresh_token' }, 400)

  let auth: WorkosAuthResponse
  try {
    auth = await authenticateWithWorkos(c.env, { grant_type: 'refresh_token', refresh_token: body.refreshToken })
  } catch {
    return c.json({ error: 'refresh_failed' }, 401)
  }

  return c.json(toSession(auth))
}
