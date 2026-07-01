import { Hono } from 'hono'
import type { Env } from './env'
import { handleEntitlement } from './entitlement'
import { handleAuthCallback, handleAuthRefresh } from './auth'
import { handleCheckout, handlePortal, handleStripeWebhook } from './billing'

// Router (all handlers implemented; deploy is gated on provisioning — see README).
const app = new Hono<{ Bindings: Env }>()

app.get('/health', (c) => c.json({ ok: true }))

app.post('/auth/callback', handleAuthCallback)
app.post('/auth/refresh', handleAuthRefresh)
app.get('/entitlement', handleEntitlement)
app.post('/billing/checkout', handleCheckout)
app.post('/billing/portal', handlePortal)
app.post('/webhooks/stripe', handleStripeWebhook)

export default app
