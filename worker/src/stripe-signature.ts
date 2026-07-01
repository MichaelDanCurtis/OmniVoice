/// Verifies a Stripe webhook signature header (`t=<ts>,v1=<sig>,...`) using HMAC-SHA256
/// over `${t}.${payload}` (Web Crypto — runs on Workers and Node). Returns true only if a
/// `v1` signature matches and the timestamp is within `toleranceSeconds` of `nowSeconds`.
export async function verifyStripeSignature(
  payload: string,
  signatureHeader: string,
  secret: string,
  nowSeconds: number,
  toleranceSeconds = 300,
): Promise<boolean> {
  const fields = new Map<string, string>()
  for (const part of signatureHeader.split(',')) {
    const index = part.indexOf('=')
    if (index === -1) continue
    fields.set(part.slice(0, index).trim(), part.slice(index + 1))
  }

  const timestamp = Number.parseInt(fields.get('t') ?? '', 10)
  const provided = fields.get('v1')
  if (!Number.isFinite(timestamp) || !provided) return false
  if (Math.abs(nowSeconds - timestamp) > toleranceSeconds) return false

  const expected = await hmacSha256Hex(secret, `${timestamp}.${payload}`)
  return timingSafeEqual(expected, provided)
}

async function hmacSha256Hex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const signature = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(message))
  return [...new Uint8Array(signature)].map((byte) => byte.toString(16).padStart(2, '0')).join('')
}

/// Length-checked constant-time-ish comparison of two hex strings.
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false
  let result = 0
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i)
  }
  return result === 0
}
