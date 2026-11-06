-- Friends, what they owe and what they paid back: one small JSON document, last write wins.
CREATE TABLE ledger (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  doc TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
