// Start `wrangler dev` with GEMINI_BASE_URL=http://127.0.0.1:8799 and GEMINI_API_KEY=stub in .dev.vars, then:
//   node --test scripts/parse.test.mjs
import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';

const BASE = process.env.BASE ?? 'http://127.0.0.1:8787';
const PASSWORD = process.env.TEST_PASSWORD ?? 'local-test-password-1';
let token = '';
let mode = 'good';
let seen = [];

const stub = http.createServer((req, res) => {
  let body = '';
  req.on('data', (d) => (body += d));
  req.on('end', () => {
    seen.push({ url: req.url, key: req.headers['x-goog-api-key'], body: JSON.parse(body || '{}') });
    const model = decodeURIComponent(req.url.split('/models/')[1].split(':')[0]);
    if (mode === 'fallback' && model === 'gemini-3.8-flash') { res.writeHead(429).end('{}'); return; }
    if (mode === 'down') { res.writeHead(503).end('{}'); return; }
    if (mode === 'badkey') { res.writeHead(400).end('{}'); return; }
    const payload = mode === 'junk'
      ? 'not json at all'
      : JSON.stringify({ merchant: 'Kopitiam Lim Kee', date: '2026-11-03', items: [{ name: 'Nasi lemak', price: 8.5 }, { name: 'Teh ais', price: 3.2 }], tax: 0.7, rounding: 0.05, total: 12.45, category: 'Food' });
    res.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({ candidates: [{ content: { parts: [{ text: payload }] } }] }));
  });
});

async function api(method, path, body) {
  const res = await fetch(BASE + path, { method, headers: { 'content-type': 'application/json', ...(token ? { authorization: 'Bearer ' + token } : {}) }, body: body ? JSON.stringify(body) : undefined });
  return { status: res.status, json: await res.json().catch(() => null) };
}
const TEXT = 'KOPITIAM LIM KEE\n03/11/2026\nNasi lemak 8.50\nTeh ais 3.20\nSST 0.70\nRounding 0.05\nTOTAL 12.45';

before(async () => {
  await new Promise((r) => stub.listen(8799, '127.0.0.1', r));
  const login = await fetch(BASE + '/auth/login', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ password: PASSWORD }) });
  token = (await login.json()).token;
});
after(() => stub.close());

test('requires auth', async () => {
  const t = token; token = '';
  assert.equal((await api('POST', '/parse-receipt', { text: TEXT })).status, 401);
  token = t;
});

test('validates input', async () => {
  assert.equal((await api('POST', '/parse-receipt', {})).status, 400);
  assert.equal((await api('POST', '/parse-receipt', { text: 'hi' })).status, 400);
  assert.equal((await api('POST', '/parse-receipt', { text: 'x'.repeat(8001) })).status, 400);
});

test('good parse returns cents, category and sends the key and receipt text', async () => {
  mode = 'good'; seen = [];
  const r = await api('POST', '/parse-receipt', { text: TEXT });
  assert.equal(r.status, 200);
  assert.equal(r.json.merchant, 'Kopitiam Lim Kee');
  assert.equal(r.json.total_cents, 1245);
  assert.equal(r.json.items.length, 2);
  assert.equal(r.json.confidence, 0.95);
  assert.equal(r.json.category_source, 'ai');
  assert.ok(r.json.category_id > 0);
  assert.equal(seen.length, 1);
  assert.equal(seen[0].key, 'stub');
  assert.ok(seen[0].body.contents[0].parts[0].text.includes('Nasi lemak'));
  assert.ok(seen[0].body.generationConfig.responseSchema);
});

test('learned merchant rule beats the model category', async () => {
  mode = 'good';
  const cats = (await api('GET', '/categories')).json.categories.filter((c) => c.kind === 'spend');
  const other = cats.find((c) => c.name !== 'Food').id;
  await api('PUT', '/rules/' + encodeURIComponent('Kopitiam Lim Kee'), { category_id: other });
  const r = await api('POST', '/parse-receipt', { text: TEXT });
  assert.equal(r.json.category_source, 'rule');
  assert.equal(r.json.category_id, other);
});

test('rate-limited first model falls through to the next', async () => {
  mode = 'fallback'; seen = [];
  const r = await api('POST', '/parse-receipt', { text: TEXT });
  assert.equal(r.status, 200);
  assert.equal(r.json.model, 'gemini-3.6-flash');
  assert.equal(seen.length, 2);
});

test('failures become clear errors, not crashes', async () => {
  mode = 'down';
  assert.equal((await api('POST', '/parse-receipt', { text: TEXT })).status, 502);
  mode = 'junk';
  assert.equal((await api('POST', '/parse-receipt', { text: TEXT })).json.error, 'parse_failed');
  mode = 'badkey'; seen = [];
  assert.equal((await api('POST', '/parse-receipt', { text: TEXT })).status, 502);
  assert.equal(seen.length, 1, 'a bad request must not burn through every model');
});

