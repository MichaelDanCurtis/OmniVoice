import { Hono } from 'hono'
import type { Env } from './env'
import { handleEntitlement } from './entitlement'

// Router. Handlers filled in by tasks: T8 entitlement, T9 auth, T10 billing.
const app = new Hono<{ Bindings: Env }>()

app.get('/health', (c) => c.json({ ok: true }))

app.post('/auth/callback', (c) => c.json({ error: 'not_implemented' }, 501))
app.post('/auth/refresh', (c) => c.json({ error: 'not_implemented' }, 501))
app.get('/entitlement', handleEntitlement)
app.post('/billing/checkout', (c) => c.json({ error: 'not_implemented' }, 501))
app.post('/billing/portal', (c) => c.json({ error: 'not_implemented' }, 501))
app.post('/webhooks/stripe', (c) => c.json({ error: 'not_implemented' }, 501))

export default app
