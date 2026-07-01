import { describe, it, expect } from 'vitest'
import { SignJWT, generateKeyPair } from 'jose'
import { authenticateWithWorkos, toSession, upsertUserStampingTrial } from '../src/auth'
import type { Env } from '../src/env'
import { createTestDb } from './helpers/d1'

const env = {
  WORKOS_CLIENT_ID: 'client_test',
  WORKOS_API_KEY: 'sk_test',
} as unknown as Env

async function makeAccessToken(sub: string, exp: number): Promise<string> {
  const { privateKey } = await generateKeyPair('RS256', { extractable: true })
  return new SignJWT({})
    .setProtectedHeader({ alg: 'RS256' })
    .setSubject(sub)
    .setIssuedAt()
    .setExpirationTime(exp)
    .sign(privateKey)
}

describe('authenticateWithWorkos', () => {
  it('posts the grant with client credentials and parses the response', async () => {
    let captured: { url: string; body: unknown } | null = null
    const fakeFetch = (async (url: string, init?: RequestInit) => {
      captured = { url, body: JSON.parse(String(init?.body)) }
      return new Response(
        JSON.stringify({ user: { id: 'user_1', email: 'a@b.co' }, access_token: 'at', refresh_token: 'rt' }),
        { status: 200, headers: { 'Content-Type': 'application/json' } },
      )
    }) as unknown as typeof fetch

    const result = await authenticateWithWorkos(env, { grant_type: 'authorization_code', code: 'abc' }, fakeFetch)

    expect(result.user.id).toBe('user_1')
    expect(captured!.url).toContain('/user_management/authenticate')
    expect(captured!.body).toMatchObject({
      client_id: 'client_test',
      client_secret: 'sk_test',
      grant_type: 'authorization_code',
      code: 'abc',
    })
  })

  it('throws on a non-2xx WorkOS response', async () => {
    const fakeFetch = (async () => new Response('nope', { status: 401 })) as unknown as typeof fetch
    await expect(
      authenticateWithWorkos(env, { grant_type: 'authorization_code', code: 'bad' }, fakeFetch),
    ).rejects.toThrow(/workos_authenticate_failed_401/)
  })
})

describe('toSession', () => {
  it('derives expiresAt from the access token exp claim', async () => {
    const exp = 2_000_000_000
    const accessToken = await makeAccessToken('user_9', exp)
    const session = toSession({ user: { id: 'user_9', email: 'x@y.co' }, access_token: accessToken, refresh_token: 'rt' })
    expect(session).toMatchObject({ accessToken, refreshToken: 'rt', userId: 'user_9', email: 'x@y.co', expiresAt: exp })
  })
})

describe('upsertUserStampingTrial', () => {
  it('stamps trial_started_at once and preserves it across re-login', async () => {
    const db = createTestDb()
    await upsertUserStampingTrial(db, { id: 'user_1', email: 'first@b.co' }, 1000)
    await upsertUserStampingTrial(db, { id: 'user_1', email: 'updated@b.co' }, 5000)

    const row = await db
      .prepare('SELECT email, trial_started_at AS trialStartedAt FROM users WHERE workos_user_id = ?')
      .bind('user_1')
      .first<{ email: string; trialStartedAt: number }>()

    expect(row).toEqual({ email: 'updated@b.co', trialStartedAt: 1000 })
  })
})
