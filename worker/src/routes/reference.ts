import { Hono } from 'hono';
import { HttpError, type AppEnv } from '../types';
import { ID_RE, bad, isInt, isValidDate, normIso, normalizeMerchant, oneOf, readJson, reqStr } from '../util';

export const rules = new Hono<AppEnv>();
export const bills = new Hono<AppEnv>();
export const settings = new Hono<AppEnv>();
export const recurring = new Hono<AppEnv>();

rules.get('/', async (c) => {
  const res = await c.env.DB
    .prepare(
      `SELECT r.merchant_key, r.category_id, c.name AS category_name, r.hits, r.updated_at
       FROM merchant_rules r JOIN categories c ON c.id = r.category_id ORDER BY r.hits DESC, r.merchant_key`,
    )
    .all();
  return c.json({ rules: res.results });
});

rules.put('/:merchant_key', async (c) => {
  const key = normalizeMerchant(c.req.param('merchant_key'));
  if (key.length < 1 || key.length > 120) throw bad('merchant_key must be 1 to 120 characters');
  const body = await readJson(c);
  if (!isInt(body.category_id, 1, 1_000_000)) throw bad('category_id must be a number');
  const cat = await c.env.DB.prepare('SELECT kind FROM categories WHERE id = ?').bind(body.category_id).first<{ kind: string }>();
  if (!cat) throw bad('category_id does not exist');
  if (cat.kind !== 'spend') throw bad('rules only apply to spending categories');
  await c.env.DB
    .prepare(
      `INSERT INTO merchant_rules (merchant_key, category_id) VALUES (?, ?)
       ON CONFLICT(merchant_key) DO UPDATE SET category_id = excluded.category_id,
         hits = merchant_rules.hits + 1, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')`,
    )
    .bind(key, body.category_id)
    .run();
  const row = await c.env.DB.prepare('SELECT * FROM merchant_rules WHERE merchant_key = ?').bind(key).first();
  return c.json({ rule: row });
});

bills.get('/', async (c) => {
  const res = await c.env.DB.prepare('SELECT * FROM bills ORDER BY due_date, id').all();
  return c.json({ bills: res.results });
});

bills.put('/:id', async (c) => {
  const id = c.req.param('id');
  if (!ID_RE.test(id)) throw bad('id must be 6 to 64 letters, digits, - or _');
  const b = await readJson(c);
  if (!isValidDate(b.due_date)) throw bad('due_date must be YYYY-MM-DD');
  if (!isInt(b.amount_cents, 0, 100_000_000)) throw bad('amount_cents must be whole cents');
  let paid_at: string | null = null;
  if (b.paid_at !== undefined && b.paid_at !== null) {
    paid_at = isValidDate(b.paid_at) ? b.paid_at : normIso(b.paid_at, 'paid_at');
  }
  await c.env.DB
    .prepare(
      `INSERT INTO bills (id, name, kind, due_date, amount_cents, paid_at) VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET name = excluded.name, kind = excluded.kind, due_date = excluded.due_date,
         amount_cents = excluded.amount_cents, paid_at = excluded.paid_at`,
    )
    .bind(
      id,
      reqStr(b.name, 'name', 120),
      oneOf(b.kind, ['spaylater', 'credit_card', 'rent', 'utilities', 'other'] as const, 'kind'),
      b.due_date,
      b.amount_cents,
      paid_at,
    )
    .run();
  return c.json({ bill: await c.env.DB.prepare('SELECT * FROM bills WHERE id = ?').bind(id).first() });
});

bills.delete('/:id', async (c) => {
  const id = c.req.param('id');
  if (!ID_RE.test(id)) throw bad('id must be 6 to 64 letters, digits, - or _');
  await c.env.DB.prepare('DELETE FROM bills WHERE id = ?').bind(id).run();
  return c.json({ ok: true });
});

recurring.get('/', async (c) => {
  const res = await c.env.DB.prepare('SELECT * FROM recurring WHERE deleted_at IS NULL ORDER BY day_of_month, id').all();
  return c.json({ recurring: res.results });
});

recurring.put('/:id', async (c) => {
  const id = c.req.param('id');
  if (!ID_RE.test(id)) throw bad('id must be 6 to 64 letters, digits, - or _');
  const b = await readJson(c);
  const direction = oneOf(b.direction, ['spend', 'income'] as const, 'direction');
  const payment = oneOf(b.payment_type, ['cash', 'debit', 'credit_card', 'spaylater', 'ewallet'] as const, 'payment_type');
  if (!isInt(b.amount_cents, 1, 100_000_000)) throw bad('amount_cents must be whole cents above zero');
  if (!isInt(b.category_id, 1, 1_000_000)) throw bad('category_id is invalid');
  if (!isInt(b.day_of_month, 1, 28)) throw bad('day_of_month must be 1 to 28');
  const lastPosted = b.last_posted === null || b.last_posted === undefined ? null : String(b.last_posted);
  if (lastPosted !== null && !/^\d{4}-(0[1-9]|1[0-2])$/.test(lastPosted)) throw bad('last_posted must be YYYY-MM');
  // Income and SPayLater never count toward the weekly cap, same rule as transactions.
  const counts = direction === 'spend' && payment !== 'spaylater' && (b.counts_toward_cap === true || b.counts_toward_cap === 1) ? 1 : 0;
  await c.env.DB
    .prepare(
      `INSERT INTO recurring (id, title, direction, amount_cents, category_id, payment_type, day_of_month, counts_toward_cap, active, last_posted)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET title = excluded.title, direction = excluded.direction, amount_cents = excluded.amount_cents,
         category_id = excluded.category_id, payment_type = excluded.payment_type, day_of_month = excluded.day_of_month,
         counts_toward_cap = excluded.counts_toward_cap, active = excluded.active, last_posted = excluded.last_posted,
         updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'), deleted_at = NULL`,
    )
    .bind(id, reqStr(b.title, 'title', 120), direction, b.amount_cents, b.category_id, payment, b.day_of_month, counts, b.active === false || b.active === 0 ? 0 : 1, lastPosted)
    .run();
  return c.json({ recurring: await c.env.DB.prepare('SELECT * FROM recurring WHERE id = ?').bind(id).first() });
});

recurring.delete('/:id', async (c) => {
  const id = c.req.param('id');
  if (!ID_RE.test(id)) throw bad('id must be 6 to 64 letters, digits, - or _');
  await c.env.DB.prepare(`UPDATE recurring SET deleted_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ?`).bind(id).run();
  return c.json({ ok: true });
});

const READ_ONLY = new Set(['timezone', 'week_starts_on']);

settings.get('/', async (c) => {
  const res = await c.env.DB.prepare('SELECT key, value FROM settings ORDER BY key').all<{ key: string; value: string }>();
  return c.json({ settings: Object.fromEntries(res.results.map((r) => [r.key, r.value])) });
});

settings.put('/:key', async (c) => {
  const key = c.req.param('key');
  if (!/^[a-z][a-z0-9_]{0,39}$/.test(key)) throw bad('key must be lowercase letters, digits and _');
  if (READ_ONLY.has(key)) throw new HttpError(403, 'read_only', `${key} cannot be changed`);
  const body = await readJson(c);
  if (typeof body.value !== 'string' && typeof body.value !== 'number') throw bad('value must be text or a number');
  const value = String(body.value).trim();
  if (value.length < 1 || value.length > 100) throw bad('value must be 1 to 100 characters');

  if (key.endsWith('_cents')) {
    const n = Number(value);
    if (!Number.isInteger(n) || n < (key === 'weekly_cap_cents' ? 1 : 0) || n > 100_000_000) {
      throw bad(`${key} must be a whole number of cents${key === 'weekly_cap_cents' ? ', above zero' : ''}`);
    }
  }
  if (key.endsWith('_enabled') && value !== '0' && value !== '1') throw bad(`${key} must be 0 or 1`);
  if (key.endsWith('_time') && !/^([01]\d|2[0-3]):[0-5]\d$/.test(value)) throw bad(`${key} must be HH:MM`);

  await c.env.DB
    .prepare('INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value')
    .bind(key, value)
    .run();
  return c.json({ key, value });
});
