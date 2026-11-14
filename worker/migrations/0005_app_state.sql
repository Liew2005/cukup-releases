-- Small things that used to live only on the phone: savings goal and sweeps, shop-to-category rules,
-- remembered cards, reminder switches and the pay link. One JSON document, newest write wins (like the ledger).
CREATE TABLE app_state (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  doc TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
