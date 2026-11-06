import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { bad, readJson } from '../util';

export const ledger = new Hono<AppEnv>();

const MAX_DOC = 900_000;

/** The whole friends ledger as one document. The phone is the only writer, so the newest write wins. */
ledger.get('/', async (c) => {
  const row = await c.env.DB.prepare('SELECT doc, updated_at FROM ledger WHERE id = 1').first<{ doc: string; updated_at: string }>();
  return c.json(row ? { doc: row.doc, updated_at: row.updated_at } : { doc: null, updated_at: null });
});

ledger.put('/', async (c) => {
  const body = await readJson(c);
  if (typeof body.doc !== 'string' || body.doc.length < 2 || body.doc.length > MAX_DOC) throw bad('doc must be JSON text under 900 KB');
  if (typeof body.updated_at !== 'string' || !/^\d{4}-\d{2}-\d{2}T/.test(body.updated_at)) throw bad('updated_at must be an ISO time');
  let parsed: unknown;
  try {
    parsed = JSON.parse(body.doc);
  } catch {
    throw bad('doc is not valid JSON');
  }
  const d = parsed as Record<string, unknown>;
  if (typeof parsed !== 'object' || parsed === null || !Array.isArray(d.friends) || !Array.isArray(d.debts) || !Array.isArray(d.payments)) {
    throw bad('doc needs friends, debts and payments lists');
  }

  const current = await c.env.DB.prepare('SELECT doc, updated_at FROM ledger WHERE id = 1').first<{ doc: string; updated_at: string }>();
  if (current && current.updated_at > body.updated_at) {
    return c.json({ stored: false, doc: current.doc, updated_at: current.updated_at }); // the server copy is newer: the phone should take it
  }
  await c.env.DB
    .prepare('INSERT INTO ledger (id, doc, updated_at) VALUES (1, ?, ?) ON CONFLICT(id) DO UPDATE SET doc = excluded.doc, updated_at = excluded.updated_at')
    .bind(body.doc, body.updated_at)
    .run();
  return c.json({ stored: true, updated_at: body.updated_at });
});
