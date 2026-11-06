import { Hono } from 'hono';
import { HttpError, type AppEnv } from '../types';
import { ID_RE, bad, isInt, isValidDate, normIso, nowIso, oneOf, optStr, readJson, reqStr } from '../util';

export const transactions = new Hono<AppEnv>();

const PAYMENT = ['cash', 'debit', 'credit_card', 'spaylater', 'ewallet'] as const;
const SOURCE = ['scan', 'manual', 'quick', 'import', 'recurring'] as const;
const DIRECTION = ['spend', 'income'] as const;
const MAX_CENTS = 100_000_000; // RM 1,000,000

interface ItemIn {
  id: string;
  name: string;
  price_cents: number;
  included: 0 | 1;
}

interface TxIn {
  spent_at: string;
  merchant: string;
  amount_cents: number;
  direction: (typeof DIRECTION)[number];
  receipt_total_cents: number | null;
  tax_cents: number;
  category_id: number;
  payment_type: (typeof PAYMENT)[number];
  counts_toward_cap: 0 | 1;
  note: string | null;
  source: (typeof SOURCE)[number];
  reference: string | null;
  confidence: number | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
  items: ItemIn[] | undefined;
}

function bool01(v: unknown, field: string, fallback: 0 | 1): 0 | 1 {
  if (v === undefined) return fallback;
  if (v === true || v === 1) return 1;
  if (v === false || v === 0) return 0;
  throw bad(`${field} must be true or false`);
}

function parseItems(v: unknown): ItemIn[] | undefined {
  if (v === undefined) return undefined;
  if (!Array.isArray(v) || v.length > 100) throw bad('items must be a list of up to 100 items');
  return v.map((raw, i) => {
    if (typeof raw !== 'object' || raw === null) throw bad(`items[${i}] must be an object`);
    const it = raw as Record<string, unknown>;
    if (typeof it.id !== 'string' || !ID_RE.test(it.id)) throw bad(`items[${i}].id is invalid`);
    if (!isInt(it.price_cents, 0, MAX_CENTS)) throw bad(`items[${i}].price_cents must be whole cents`);
    return {
      id: it.id,
      name: reqStr(it.name, `items[${i}].name`, 120),
      price_cents: it.price_cents,
      included: bool01(it.included, `items[${i}].included`, 1),
    };
  });
}

function parseTransaction(b: Record<string, unknown>): TxIn {
  if (!isValidDate(b.spent_at)) throw bad('spent_at must be a real date, YYYY-MM-DD');
  if (!isInt(b.amount_cents, 0, MAX_CENTS)) throw bad('amount_cents must be a whole number of cents');
  if (!isInt(b.category_id, 1, 1_000_000)) throw bad('category_id must be a number');
  const direction = b.direction === undefined ? 'spend' : oneOf(b.direction, DIRECTION, 'direction');
  const payment_type = oneOf(b.payment_type, PAYMENT, 'payment_type');
  const source = oneOf(b.source, SOURCE, 'source');

  let receipt_total_cents: number | null = null;
  if (b.receipt_total_cents !== undefined && b.receipt_total_cents !== null) {
    if (!isInt(b.receipt_total_cents, b.amount_cents, MAX_CENTS)) {
      throw bad('receipt_total_cents must be whole cents and at least amount_cents');
    }
    receipt_total_cents = b.receipt_total_cents;
  }
  let tax_cents = 0;
  if (b.tax_cents !== undefined) {
    if (!isInt(b.tax_cents, 0, MAX_CENTS)) throw bad('tax_cents must be whole cents');
    tax_cents = b.tax_cents;
  }
  let confidence: number | null = null;
  if (b.confidence !== undefined && b.confidence !== null) {
    if (typeof b.confidence !== 'number' || b.confidence < 0 || b.confidence > 1) throw bad('confidence must be 0 to 1');
    confidence = b.confidence;
  }

  // Income never counts toward the weekly cap, and neither do SPayLater purchases.
  let counts_toward_cap = bool01(b.counts_toward_cap, 'counts_toward_cap', 1);
  if (direction === 'income' || payment_type === 'spaylater') counts_toward_cap = 0;

  const now = nowIso();
  return {
    spent_at: b.spent_at,
    merchant: reqStr(b.merchant, 'merchant', 120),
    amount_cents: b.amount_cents,
    direction,
    receipt_total_cents,
    tax_cents,
    category_id: b.category_id,
    payment_type,
    counts_toward_cap,
    note: optStr(b.note, 'note', 500),
    source,
    reference: optStr(b.reference, 'reference', 64),
    confidence,
    created_at: b.created_at === undefined ? now : normIso(b.created_at, 'created_at'),
    updated_at: b.updated_at === undefined ? now : normIso(b.updated_at, 'updated_at'),
    deleted_at: b.deleted_at === undefined || b.deleted_at === null ? null : normIso(b.deleted_at, 'deleted_at'),
    items: parseItems(b.items),
  };
}

const SELECT_TX = `
  SELECT t.id, t.spent_at, t.merchant, t.amount_cents, t.direction, t.receipt_total_cents, t.tax_cents,
         t.category_id, c.name AS category_name, t.payment_type, t.counts_toward_cap, t.note, t.source,
         t.reference, t.confidence, t.created_at, t.updated_at, t.deleted_at
  FROM transactions t JOIN categories c ON c.id = t.category_id`;

interface TxRow {
  id: string;
  counts_toward_cap: number;
  [key: string]: unknown;
}
interface ItemRow {
  id: string;
  transaction_id: string;
  name: string;
  price_cents: number;
  included: number;
  updated_at: string;
}

function shape(row: TxRow, items: ItemRow[]) {
  return {
    ...row,
    counts_toward_cap: row.counts_toward_cap === 1,
    items: items.map((i) => ({ id: i.id, name: i.name, price_cents: i.price_cents, included: i.included === 1 })),
  };
}

transactions.get('/', async (c) => {
  const q = c.req.query();
  const where: string[] = [];
  const args: (string | number)[] = [];

  if (q.from !== undefined) {
    if (!isValidDate(q.from)) throw bad('from must be YYYY-MM-DD');
    where.push('t.spent_at >= ?');
    args.push(q.from);
  }
  if (q.to !== undefined) {
    if (!isValidDate(q.to)) throw bad('to must be YYYY-MM-DD');
    where.push('t.spent_at <= ?');
    args.push(q.to);
  }
  if (q.updated_since !== undefined) {
    where.push('t.updated_at > ?');
    args.push(normIso(q.updated_since, 'updated_since'));
  }
  if (q.direction !== undefined) {
    where.push('t.direction = ?');
    args.push(oneOf(q.direction, DIRECTION, 'direction'));
  }
  if (q.include_deleted !== '1') where.push('t.deleted_at IS NULL');

  const limit = q.limit === undefined ? 1000 : Number(q.limit);
  if (!isInt(limit, 1, 5000)) throw bad('limit must be 1 to 5000');

  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
  const db = c.env.DB;
  const [txRes, itemRes] = await db.batch([
    db.prepare(`${SELECT_TX} ${whereSql} ORDER BY t.spent_at DESC, t.created_at DESC LIMIT ?`).bind(...args, limit),
    db
      .prepare(`SELECT i.* FROM transaction_items i JOIN transactions t ON t.id = i.transaction_id ${whereSql}`)
      .bind(...args),
  ]);

  const byTx = new Map<string, ItemRow[]>();
  for (const it of itemRes.results as unknown as ItemRow[]) {
    const list = byTx.get(it.transaction_id) ?? [];
    list.push(it);
    byTx.set(it.transaction_id, list);
  }
  const rows = txRes.results as unknown as TxRow[];
  return c.json({ transactions: rows.map((r) => shape(r, byTx.get(r.id) ?? [])) });
});

async function loadOne(db: AppEnv['Bindings']['DB'], id: string) {
  const row = await db.prepare(`${SELECT_TX} WHERE t.id = ?`).bind(id).first<TxRow>();
  if (!row) return null;
  const items = await db.prepare('SELECT * FROM transaction_items WHERE transaction_id = ?').bind(id).all<ItemRow>();
  return shape(row, items.results);
}

transactions.get('/:id', async (c) => {
  const found = await loadOne(c.env.DB, c.req.param('id'));
  if (!found) throw new HttpError(404, 'not_found', 'No such transaction');
  return c.json({ transaction: found });
});

// Create or update by client-made id. Idempotent. Last write wins by updated_at.
transactions.put('/:id', async (c) => {
  const id = c.req.param('id');
  if (!ID_RE.test(id)) throw bad('id must be 6 to 64 letters, digits, - or _');
  const t = parseTransaction(await readJson(c));
  const db = c.env.DB;

  const cat = await db.prepare('SELECT kind FROM categories WHERE id = ?').bind(t.category_id).first<{ kind: string }>();
  if (!cat) throw bad('category_id does not exist');
  if (cat.kind !== t.direction) throw bad(`category is for ${cat.kind}, but direction is ${t.direction}`);

  const res = await db
    .prepare(
      `INSERT INTO transactions (id, spent_at, merchant, amount_cents, direction, receipt_total_cents, tax_cents,
         category_id, payment_type, counts_toward_cap, note, source, reference, confidence, created_at, updated_at, deleted_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET
         spent_at = excluded.spent_at, merchant = excluded.merchant, amount_cents = excluded.amount_cents,
         direction = excluded.direction, receipt_total_cents = excluded.receipt_total_cents, tax_cents = excluded.tax_cents,
         category_id = excluded.category_id, payment_type = excluded.payment_type,
         counts_toward_cap = excluded.counts_toward_cap, note = excluded.note, source = excluded.source,
         reference = excluded.reference, confidence = excluded.confidence,
         updated_at = excluded.updated_at, deleted_at = excluded.deleted_at
       WHERE excluded.updated_at >= transactions.updated_at`,
    )
    .bind(
      id, t.spent_at, t.merchant, t.amount_cents, t.direction, t.receipt_total_cents, t.tax_cents,
      t.category_id, t.payment_type, t.counts_toward_cap, t.note, t.source, t.reference, t.confidence,
      t.created_at, t.updated_at, t.deleted_at,
    )
    .run();

  const applied = (res.meta.changes ?? 0) > 0;
  if (applied && t.items) {
    await db.batch([
      db.prepare('DELETE FROM transaction_items WHERE transaction_id = ?').bind(id),
      ...t.items.map((it) =>
        db
          .prepare('INSERT INTO transaction_items (id, transaction_id, name, price_cents, included, updated_at) VALUES (?, ?, ?, ?, ?, ?)')
          .bind(it.id, id, it.name, it.price_cents, it.included, t.updated_at),
      ),
    ]);
  }
  return c.json({ applied, transaction: await loadOne(db, id) });
});

// Soft delete, so other devices learn about it on the next sync.
transactions.delete('/:id', async (c) => {
  const id = c.req.param('id');
  const db = c.env.DB;
  const existing = await db.prepare('SELECT deleted_at FROM transactions WHERE id = ?').bind(id).first<{ deleted_at: string | null }>();
  if (!existing) throw new HttpError(404, 'not_found', 'No such transaction');
  if (existing.deleted_at === null) {
    const now = nowIso();
    await db.prepare('UPDATE transactions SET deleted_at = ?, updated_at = ? WHERE id = ?').bind(now, now, id).run();
  }
  return c.json({ ok: true, transaction: await loadOne(db, id) });
});
