import { defineConfig } from 'vitest/config'

// The Worker's logic is written as pure functions (computeStatus, JWT verify, Stripe
// signature check, webhook reducer) so unit tests run under plain Node — no miniflare
// harness required. D1 is exercised via a small in-memory fake in the tests.
export default defineConfig({
  test: {
    environment: 'node',
    include: ['test/**/*.test.ts'],
  },
})
