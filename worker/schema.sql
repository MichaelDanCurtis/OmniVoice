-- OmniVoice account + entitlement schema (Cloudflare D1 / SQLite).
-- Apply with: wrangler d1 execute omnivoice --file schema.sql

CREATE TABLE IF NOT EXISTS users (
  workos_user_id     TEXT PRIMARY KEY,
  email              TEXT,
  stripe_customer_id TEXT,
  trial_started_at   INTEGER,   -- epoch seconds; stamped once on first login
  created_at         INTEGER
);

CREATE TABLE IF NOT EXISTS entitlements (
  workos_user_id     TEXT PRIMARY KEY,
  status             TEXT,      -- 'active' | 'canceled' | 'none'
  current_period_end INTEGER,   -- epoch seconds
  updated_at         INTEGER
);
