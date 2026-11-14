import { Hono } from 'hono';
import { HttpError, type AppEnv } from '../types';
import { bad, isInt, nowIso, oneOf, readJson, reqStr } from '../util';

export const categories = new Hono<AppEnv>();

const KIND = ['spend', 'income'] as const;
const COLS = 'id, name, kind, sort_order, cap_default';
const MAX_CATEGORIES = 40;

/** Entries land here when their category is deleted, so these two cannot be renamed or removed. */
const fallbackName = (kind: string) => (kind === 'income' ? 'Other income' : 'Other');
const isFallback = (name: string) => name === 'Other' || name === 'Other income';

function flag(v: unknown, fallback: 0 | 1): 0 | 1 {
  if (v === undefined) return fallback;
  if (v === true || v === 1) return 1;
  if (v === false || v === 0) return 0;
  throw bad('cap_default must be true or false');
}

function catId(raw: string): number {
  const id = Number(raw);
  if (!isInt(id, 1, 1_000_000)) throw bad('id must be a number');
  return id;
}

interface Row {
  id: number;
  name: string;
  kind: string;
  sort_order: number;
  cap_default: number;
}

categories.get('/', async (c) => {
  const res = await c.env.DB.prepare(`SELECT ${COLS} FROM categories ORDER BY sort_order, id`).all();
  return c.json({ categories: res.results });
});

categories.post('/', async (c) => {
  const b = await readJson(c);
  const name = reqStr(b.name, 'name', 30);
  const kind = oneOf(b.kind, KIND, 'kind');
  const cap = flag(b.cap_default, 1);
  const db = c.env.DB;
  const count = await db.prepare('SELECT COUNT(*) AS n FROM categories').first<{ n: number }>();
  if ((count?.n ?? 0) >= MAX_CATEGORIES) throw bad(`You can have up to ${MAX_CATEGORIES} categories`);
  if (await db.prepare('SELECT id FROM categories WHERE lower(name) = lower(?)').bind(name).first()) throw bad('A category with that name already exists');
  const row = await db
    .prepare(`INSERT INTO categories (name, kind, sort_order, cap_default) VALUES (?, ?, (SELECT COALESCE(MAX(sort_order), 0) + 1 FROM categories), ?) RETURNING ${COLS}`)
    .bind(name, kind, cap)
    .first<Row>();
  return c.json({ category: row }, 201);
});

categories.put('/:id', async (c) => {
  const id = catId(c.req.param('id'));
  const b = await readJson(c);
  const db = c.env.DB;
  const cur = await db.prepare(`SELECT ${COLS} FROM categories WHERE id = ?`).bind(id).first<Row>();
  if (!cur) throw new HttpError(404, 'not_found', 'No such category');
  let name = cur.name;
  if (b.name !== undefined) {
    name = reqStr(b.name, 'name', 30);
    if (name !== cur.name && isFallback(cur.name)) throw bad(`"${cur.name}" cannot be renamed`);
    if (name.toLowerCase() !== cur.name.toLowerCase() && (await db.prepare('SELECT id FROM categories WHERE lower(name) = lower(?) AND id <> ?').bind(name, id).first())) {
      throw bad('A category with that name already exists');
    }
  }
  let sort = cur.sort_order;
  if (b.sort_order !== undefined) {
    if (!isInt(b.sort_order, 0, 10_000)) throw bad('sort_order must be a whole number');
    sort = b.sort_order;
  }
  const cap = flag(b.cap_default, cur.cap_default === 1 ? 1 : 0);
  const row = await db.prepare(`UPDATE categories SET name = ?, sort_order = ?, cap_default = ? WHERE id = ? RETURNING ${COLS}`).bind(name, sort, cap, id).first<Row>();
  return c.json({ category: row });
});

/** Removes a category. Its entries, repeating items and shop rules move to Other (or Other income) first. */
categories.delete('/:id', async (c) => {
  const id = catId(c.req.param('id'));
  const db = c.env.DB;
  const cur = await db.prepare(`SELECT ${COLS} FROM categories WHERE id = ?`).bind(id).first<Row>();
  if (!cur) throw new HttpError(404, 'not_found', 'No such category');
  if (isFallback(cur.name)) throw bad(`"${cur.name}" cannot be deleted`);
  const to = await db.prepare('SELECT id FROM categories WHERE name = ?').bind(fallbackName(cur.kind)).first<{ id: number }>();
  if (!to) throw new HttpError(500, 'internal', 'Fallback category is missing');
  const now = nowIso();
  const res = await db.batch([
    db.prepare('UPDATE transactions SET category_id = ?, updated_at = ? WHERE category_id = ?').bind(to.id, now, id),
    db.prepare('UPDATE recurring SET category_id = ?, updated_at = ? WHERE category_id = ?').bind(to.id, now, id),
    db.prepare('UPDATE merchant_rules SET category_id = ?, updated_at = ? WHERE category_id = ?').bind(to.id, now, id),
    db.prepare('DELETE FROM categories WHERE id = ?').bind(id),
  ]);
  return c.json({ deleted: true, moved_to: to.id, moved_entries: res[0].meta.changes ?? 0 });
});
