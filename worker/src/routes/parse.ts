import { Hono } from 'hono';
import { HttpError, type AppEnv } from '../types';
import { bad, normalizeMerchant, readJson, todayKL } from '../util';
import { RECEIPT_SCHEMA, reconcile, systemPrompt } from '../receipt';

export const parse = new Hono<AppEnv>();

// Tried in order. A model that is missing, rate-limited or overloaded falls through to the next.
const DEFAULT_MODELS = ['gemini-3.8-flash', 'gemini-3.6-flash', 'gemini-3.5-flash-lite', 'gemini-3.1-flash-lite'];
const FALLTHROUGH = new Set([404, 429, 500, 503]);

async function callGemini(env: AppEnv['Bindings'], model: string, system: string, text: string): Promise<{ status: number; body: unknown }> {
  const base = env.GEMINI_BASE_URL ?? 'https://generativelanguage.googleapis.com';
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 20_000);
  try {
    const res = await fetch(`${base}/v1beta/models/${encodeURIComponent(model)}:generateContent`, {
      method: 'POST',
      signal: ctrl.signal,
      headers: { 'content-type': 'application/json', 'x-goog-api-key': env.GEMINI_API_KEY ?? '' },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: system }] },
        contents: [{ role: 'user', parts: [{ text: `<receipt_text>\n${text}\n</receipt_text>` }] }],
        generationConfig: { temperature: 0, maxOutputTokens: 2048, responseMimeType: 'application/json', responseSchema: RECEIPT_SCHEMA },
      }),
    });
    let body: unknown = null;
    try {
      body = await res.json();
    } catch {
      /* non-JSON error page */
    }
    return { status: res.status, body };
  } finally {
    clearTimeout(timer);
  }
}

parse.post('/', async (c) => {
  if (!c.env.GEMINI_API_KEY) throw new HttpError(503, 'not_configured', 'Receipt parsing is not set up on the server');
  const body = await readJson(c);
  if (typeof body.text !== 'string') throw bad('text must be the OCR text of the receipt');
  const text = body.text.trim();
  if (text.length < 10) throw bad('text is too short to be a receipt');
  if (text.length > 8000) throw bad('text is too long (8000 characters maximum)');

  const cats = await c.env.DB.prepare("SELECT id, name FROM categories WHERE kind = 'spend' ORDER BY sort_order").all<{ id: number; name: string }>();
  const system = systemPrompt(cats.results.map((r) => r.name));

  const models = c.env.GEMINI_MODEL ? [c.env.GEMINI_MODEL] : DEFAULT_MODELS;
  let used = '';
  let candidate: unknown = null;
  let lastStatus = 0;
  let lastDetail = '';
  for (const model of models) {
    let r;
    try {
      r = await callGemini(c.env, model, system, text);
    } catch {
      lastStatus = 504; // timeout or network error: try the next model
      continue;
    }
    lastStatus = r.status;
    lastDetail = JSON.stringify((r.body as { error?: unknown } | null)?.error ?? '').slice(0, 300);
    if (r.status === 200) {
      used = model;
      candidate = r.body;
      break;
    }
    if (!FALLTHROUGH.has(r.status)) break; // bad key or bad request: another model will not help
  }
  if (!used) {
    const code = lastStatus === 429 ? 'rate_limited' : 'parse_unavailable';
    console.error('gemini failed, last status', lastStatus, lastDetail);
    throw new HttpError(lastStatus === 429 ? 429 : 502, code, 'Could not read the receipt right now. Enter it by hand or try again.');
  }

  let raw: Record<string, unknown>;
  try {
    const parts = (candidate as { candidates?: { content?: { parts?: { text?: string }[] } }[] }).candidates?.[0]?.content?.parts;
    const json = JSON.parse(parts?.map((p) => p.text ?? '').join('') ?? '');
    if (typeof json !== 'object' || json === null || Array.isArray(json)) throw new Error('not an object');
    raw = json as Record<string, unknown>;
  } catch {
    throw new HttpError(502, 'parse_failed', 'The receipt reader gave an unusable answer. Enter it by hand or try again.');
  }

  const result = reconcile(raw, todayKL());

  // Category: a learned merchant rule beats the model's guess.
  let category_id: number | null = null;
  let category_source: 'rule' | 'ai' | null = null;
  if (result.merchant) {
    const rule = await c.env.DB.prepare('SELECT category_id FROM merchant_rules WHERE merchant_key = ?').bind(normalizeMerchant(result.merchant)).first<{ category_id: number }>();
    if (rule) {
      category_id = rule.category_id;
      category_source = 'rule';
    }
  }
  if (category_id === null && result.category_hint) {
    const hit = cats.results.find((r) => r.name.toLowerCase() === result.category_hint!.toLowerCase());
    if (hit) {
      category_id = hit.id;
      category_source = 'ai';
    }
  }

  return c.json({ ...result, category_id, category_source, model: used });
});


