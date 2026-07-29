import { jwtVerify, createRemoteJWKSet, type JWTPayload, type JWTVerifyGetKey } from 'jose'
import type { Context } from 'hono'
import type { Env } from './env'

/// WorkOS publishes a JWKS per environment keyed by client id.
export function workosJwksUrl(clientId: string): string {
  return `https://api.workos.com/sso/jwks/${clientId}`
}

let cachedJwks: JWTVerifyGetKey | undefined

/// Remote JWKS resolver (cached across requests within an isolate). Tests pass their
/// own local resolver instead.
export function workosJwks(clientId: string): JWTVerifyGetKey {
  if (!cachedJwks) {
    cachedJwks = createRemoteJWKSet(new URL(workosJwksUrl(clientId)))
  }
  return cachedJwks
}

/// Verifies a WorkOS access token offline against the JWKS. Returns the claims
/// (`sub` = workos_user_id). Throws on any signature/expiry failure.
export async function verifyWorkosToken(token: string, getKey: JWTVerifyGetKey): Promise<JWTPayload> {
  const { payload } = await jwtVerify(token, getKey)
  return payload
}

/// Extracts and verifies the Bearer WorkOS token from a request, returning the
/// `workos_user_id` (`sub`) or null when missing/invalid.
export async function authenticatedUserId(c: Context<{ Bindings: Env }>): Promise<string | null> {
  const header = c.req.header('Authorization') ?? ''
  const token = header.startsWith('Bearer ') ? header.slice('Bearer '.length) : ''
  if (!token) return null
  try {
    const payload = await verifyWorkosToken(token, workosJwks(c.env.WORKOS_CLIENT_ID))
    return payload.sub ?? null
  } catch {
    return null
  }
}
