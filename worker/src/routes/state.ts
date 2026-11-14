import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { bad, readJson } from '../util';

export const state = new Hono<AppEnv>();

const MAX_DOC = 400_000;
const MAX_KEYS = 5000;

/**
 * App state that is not an entry: savings goal and sweeps, shop rules, remembered cards, reminder switches, pay link.
 * Stored as `{ "v": 1, "kv": { key: value } }` with text keys and values. The phone merges before it writes, so the newest write wins here.
 */
state.get('/', async (c) => {
  const row = await c.env.DB.prepare('SELECT doc, updated_at FROM app_state WHERE id = 1').first<{ doc: string; updated_at: string }>();
  return c.json(row ? { doc: row.doc, updated_at: row.updated_at } : { doc: null, updated_at: null });
});

state.put('/', async (c) => {
  const body = await readJson(c);
  if (typeof body.doc !== 'string' || body.doc.length < 2 || body.doc.length > MAX_DOC) throw bad('doc must be JSON text under 400 KB');
  if (typeof body.updated_at !== 'string' || !/^\d{4}-\d{2}-\d{2}T/.test(body.updated_at)) throw bad('updated_at must be an ISO time');
  let parsed: unknown;
  try {
    parsed = JSON.parse(body.doc);
  } catch {
    throw bad('doc is not valid JSON');
  }
  const kv = (parsed as { kv?: unknown } | null)?.kv;
  if (typeof kv !== 'object' || kv === null || Array.isArray(kv)) throw bad('doc needs a kv object');
  const entries = Object.entries(kv as Record<string, unknown>);
  if (entries.length > MAX_KEYS) throw bad('too many values');
  for (const [k, v] of entries) {
    if (k.length < 1 || k.length > 200 || typeof v !== 'string' || v.length > 4000) throw bad('kv keys and values must be short text');
  }

  const current = await c.env.DB.prepare('SELECT doc, updated_at FROM app_state WHERE id = 1').first<{ doc: string; updated_at: string }>();
  if (current && current.updated_at > body.updated_at) {
    return c.json({ stored: false, doc: current.doc, updated_at: current.updated_at }); // the server copy is newer: the phone should merge it and try again
  }
  await c.env.DB
    .prepare('INSERT INTO app_state (id, doc, updated_at) VALUES (1, ?, ?) ON CONFLICT(id) DO UPDATE SET doc = excluded.doc, updated_at = excluded.updated_at')
    .bind(body.doc, body.updated_at)
    .run();
  return c.json({ stored: true, updated_at: body.updated_at });
});
