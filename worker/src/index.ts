import { Hono } from 'hono'
import type { Env } from './env'

// Router scaffold. Handlers are filled in by later tasks (T8 entitlement, T9 auth,
// T10 billing); until then they return 501 so the shape is deployable and testable.
const app = new Hono<{ Bindings: Env }>()

app.get('/health', (c) => c.json({ ok: true }))

app.post('/auth/callback', (c) => c.json({ error: 'not_implemented' }, 501))
app.post('/auth/refresh', (c) => c.json({ error: 'not_implemented' }, 501))
app.get('/entitlement', (c) => c.json({ error: 'not_implemented' }, 501))
app.post('/billing/checkout', (c) => c.json({ error: 'not_implemented' }, 501))
app.post('/billing/portal', (c) => c.json({ error: 'not_implemented' }, 501))
app.post('/webhooks/stripe', (c) => c.json({ error: 'not_implemented' }, 501))

export default app
