-- Cukup schema v1. Merges the original plan schema with the "Design update" additions
-- (items, income, recurring, goals, sweeps). Timestamps are ISO 8601 UTC so strings compare correctly.

CREATE TABLE categories (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  kind TEXT NOT NULL DEFAULT 'spend' CHECK (kind IN ('spend','income')),
  sort_order INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE transactions (
  id TEXT PRIMARY KEY,                       -- client-made UUID, so syncing twice never duplicates
  spent_at TEXT NOT NULL,                    -- YYYY-MM-DD, Asia/Kuala_Lumpur
  merchant TEXT NOT NULL,
  amount_cents INTEGER NOT NULL CHECK (amount_cents >= 0),  -- Liew's share; RM 12.50 = 1250
  direction TEXT NOT NULL DEFAULT 'spend' CHECK (direction IN ('spend','income')),
  receipt_total_cents INTEGER,               -- full receipt when items were split
  tax_cents INTEGER NOT NULL DEFAULT 0,
  category_id INTEGER NOT NULL REFERENCES categories(id),
  payment_type TEXT NOT NULL CHECK (payment_type IN ('cash','debit','credit_card','spaylater','ewallet')),
  counts_toward_cap INTEGER NOT NULL DEFAULT 1 CHECK (counts_toward_cap IN (0,1)),
  note TEXT,
  source TEXT NOT NULL CHECK (source IN ('scan','manual','quick','import','recurring')),
  reference TEXT,                            -- e-wallet reference, for duplicate checks
  confidence REAL,                           -- 0 to 1 from parsing; null for manual
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  deleted_at TEXT                            -- soft delete so sync can propagate it
);
CREATE INDEX idx_tx_date ON transactions(spent_at);
CREATE INDEX idx_tx_cat_date ON transactions(category_id, spent_at);
CREATE INDEX idx_tx_updated ON transactions(updated_at);
CREATE INDEX idx_tx_reference ON transactions(reference) WHERE reference IS NOT NULL;

CREATE TABLE transaction_items (
  id TEXT PRIMARY KEY,
  transaction_id TEXT NOT NULL REFERENCES transactions(id),
  name TEXT NOT NULL,
  price_cents INTEGER NOT NULL CHECK (price_cents >= 0),
  included INTEGER NOT NULL DEFAULT 1 CHECK (included IN (0,1)),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
CREATE INDEX idx_items_tx ON transaction_items(transaction_id);

CREATE TABLE merchant_rules (
  merchant_key TEXT PRIMARY KEY,             -- lowercase, trimmed merchant name
  category_id INTEGER NOT NULL REFERENCES categories(id),
  hits INTEGER NOT NULL DEFAULT 1,
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE bills (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('spaylater','credit_card','rent','utilities','other')),
  due_date TEXT NOT NULL,
  amount_cents INTEGER NOT NULL CHECK (amount_cents >= 0),
  paid_at TEXT
);

CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE recurring (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  direction TEXT NOT NULL CHECK (direction IN ('spend','income')),
  amount_cents INTEGER NOT NULL CHECK (amount_cents >= 0),
  category_id INTEGER NOT NULL REFERENCES categories(id),
  payment_type TEXT NOT NULL DEFAULT 'debit' CHECK (payment_type IN ('cash','debit','credit_card','spaylater','ewallet')),
  day_of_month INTEGER NOT NULL CHECK (day_of_month BETWEEN 1 AND 28),
  counts_toward_cap INTEGER NOT NULL DEFAULT 0 CHECK (counts_toward_cap IN (0,1)),
  active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0,1)),
  last_posted TEXT,                          -- YYYY-MM of the last month posted
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  deleted_at TEXT
);

CREATE TABLE goals (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  target_cents INTEGER,                      -- NULL = open-ended (ETF fund)
  opening_cents INTEGER NOT NULL DEFAULT 0,
  priority INTEGER NOT NULL,                 -- 1 is swept first
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  deleted_at TEXT
);

CREATE TABLE sweeps (
  id TEXT PRIMARY KEY,
  week_start TEXT NOT NULL UNIQUE,           -- Monday, YYYY-MM-DD, Asia/Kuala_Lumpur
  goal_id TEXT REFERENCES goals(id),
  amount_cents INTEGER NOT NULL CHECK (amount_cents >= 0),
  status TEXT NOT NULL CHECK (status IN ('set_aside','kept')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  deleted_at TEXT
);

CREATE TABLE login_attempts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ip TEXT NOT NULL,
  at TEXT NOT NULL
);
CREATE INDEX idx_login_ip_at ON login_attempts(ip, at);
