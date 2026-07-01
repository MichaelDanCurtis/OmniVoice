import { jwtVerify, createRemoteJWKSet, type JWTPayload, type JWTVerifyGetKey } from 'jose'

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
