import { describe, it, expect } from 'vitest'
import { SignJWT, generateKeyPair, exportJWK, createLocalJWKSet } from 'jose'
import { computeStatus, type EntitlementRow } from '../src/entitlement'
import { verifyWorkosToken } from '../src/workos'

const DAY = 86_400
const now = 1_000_000_000

describe('computeStatus', () => {
  it('returns none when there is no user row', () => {
    expect(computeStatus(null, now, 14)).toEqual({ status: 'none' })
  })

  it('returns active for an active subscription', () => {
    const row: EntitlementRow = { trialStartedAt: now - 30 * DAY, subStatus: 'active', currentPeriodEnd: now + 20 * DAY }
    expect(computeStatus(row, now, 14)).toEqual({ status: 'active', currentPeriodEnd: now + 20 * DAY })
  })

  it('honors a canceled subscription until the period end', () => {
    const row: EntitlementRow = { trialStartedAt: now - 30 * DAY, subStatus: 'canceled', currentPeriodEnd: now + 5 * DAY }
    expect(computeStatus(row, now, 14)).toEqual({ status: 'active', currentPeriodEnd: now + 5 * DAY })
  })

  it('expires a canceled subscription past its period end', () => {
    const row: EntitlementRow = { trialStartedAt: now - 30 * DAY, subStatus: 'canceled', currentPeriodEnd: now - DAY }
    expect(computeStatus(row, now, 14)).toEqual({ status: 'expired' })
  })

  it('returns trialing while inside the trial window', () => {
    const row: EntitlementRow = { trialStartedAt: now - 3 * DAY, subStatus: null, currentPeriodEnd: null }
    expect(computeStatus(row, now, 14)).toEqual({ status: 'trialing', trialEndsAt: now - 3 * DAY + 14 * DAY })
  })

  it('expires once the trial window has passed', () => {
    const row: EntitlementRow = { trialStartedAt: now - 20 * DAY, subStatus: null, currentPeriodEnd: null }
    expect(computeStatus(row, now, 14)).toEqual({ status: 'expired' })
  })
})

describe('verifyWorkosToken', () => {
  async function makeKeys() {
    const { publicKey, privateKey } = await generateKeyPair('RS256', { extractable: true })
    const jwk = await exportJWK(publicKey)
    jwk.kid = 'test-key'
    jwk.alg = 'RS256'
    const getKey = createLocalJWKSet({ keys: [jwk] })
    return { privateKey, getKey }
  }

  it('accepts a validly signed token and returns its claims', async () => {
    const { privateKey, getKey } = await makeKeys()
    const token = await new SignJWT({})
      .setProtectedHeader({ alg: 'RS256', kid: 'test-key' })
      .setSubject('user_123')
      .setIssuedAt()
      .setExpirationTime('1h')
      .sign(privateKey)

    const payload = await verifyWorkosToken(token, getKey)
    expect(payload.sub).toBe('user_123')
  })

  it('rejects a tampered token', async () => {
    const { privateKey, getKey } = await makeKeys()
    const token = await new SignJWT({})
      .setProtectedHeader({ alg: 'RS256', kid: 'test-key' })
      .setSubject('user_123')
      .setIssuedAt()
      .setExpirationTime('1h')
      .sign(privateKey)

    const tampered = token.slice(0, -3) + 'AAA'
    await expect(verifyWorkosToken(tampered, getKey)).rejects.toThrow()
  })
})
