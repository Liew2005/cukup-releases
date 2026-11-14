// Run with `wrangler dev` already serving on BASE. Usage: node --test scripts/smoke.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';

const BASE = process.env.BASE ?? 'http://127.0.0.1:8787';
const PASSWORD = process.env.TEST_PASSWORD ?? 'local-test-password-1';
let token = '';
const uid = () => 't' + crypto.randomUUID().replace(/-/g, '').slice(0, 20);

async function api(method, path, body, auth = true) {
  const res = await fetch(BASE + path, {
    method,
    headers: { ...(body ? { 'content-type': 'application/json' } : {}), ...(auth && token ? { authorization: 'Bearer ' + token } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json; try { json = JSON.parse(text); } catch { json = null; }
  return { status: res.status, json, text, res };
}
// A date inside the current week keeps these tests independent of the calendar.
const today = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kuala_Lumpur' }).format(new Date());

test('health is public', async () => {
  const r = await api('GET', '/health', null, false);
  assert.equal(r.status, 200);
  assert.equal(r.json.ok, true);
});

test('protected routes return 401 without a token', async () => {
  for (const [m, p] of [['GET', '/transactions'], ['GET', '/summary/week'], ['GET', '/summary/month'], ['GET', '/categories'], ['GET', '/rules'], ['GET', '/bills'], ['GET', '/settings'], ['GET', '/export.csv'], ['PUT', '/transactions/abcdef1']]) {
    const r = await api(m, p, m === 'PUT' ? {} : null, false);
    assert.equal(r.status, 401, `${m} ${p}`);
  }
  const bad = await fetch(BASE + '/transactions', { headers: { authorization: 'Bearer not.a.token' } });
  assert.equal(bad.status, 401);
});

test('wrong password is rejected, right password returns a token', async () => {
  const wrong = await api('POST', '/auth/login', { password: 'nope-nope-nope' }, false);
  assert.equal(wrong.status, 401);
  const ok = await api('POST', '/auth/login', { password: PASSWORD }, false);
  assert.equal(ok.status, 200);
  assert.ok(ok.json.token);
  token = ok.json.token;
});

let spendCat, incomeCat;
test('categories and settings', async () => {
  const c = await api('GET', '/categories');
  assert.equal(c.status, 200);
  spendCat = c.json.categories.find((x) => x.kind === 'spend').id;
  incomeCat = c.json.categories.find((x) => x.kind === 'income').id;
  assert.equal(c.json.categories.filter((x) => x.kind === 'spend').length, 7);
  const s = await api('GET', '/settings');
  assert.equal(s.json.settings.weekly_cap_cents, '25000');
  assert.equal((await api('PUT', '/settings/timezone', { value: 'UTC' })).status, 403);
  assert.equal((await api('PUT', '/settings/weekly_cap_cents', { value: 'abc' })).status, 400);
  assert.equal((await api('PUT', '/settings/weekly_cap_cents', { value: 25000 })).status, 200);
});

test('transaction create, idempotent retry, validation', async () => {
  const id = uid();
  const body = { spent_at: today, merchant: 'Smoke Kopitiam', amount_cents: 980, category_id: spendCat, payment_type: 'cash', source: 'manual' };
  const a = await api('PUT', '/transactions/' + id, body);
  assert.equal(a.status, 200);
  assert.equal(a.json.applied, true);
  const b = await api('PUT', '/transactions/' + id, body);
  assert.equal(b.status, 200);
  const list = await api('GET', '/transactions?from=' + today + '&to=' + today);
  assert.equal(list.json.transactions.filter((t) => t.id === id).length, 1);
  assert.equal((await api('PUT', '/transactions/' + uid(), { ...body, amount_cents: 9.5 })).status, 400);
  assert.equal((await api('PUT', '/transactions/' + uid(), { ...body, spent_at: '2026-02-30' })).status, 400);
  assert.equal((await api('PUT', '/transactions/' + uid(), { ...body, category_id: 99999 })).status, 400);
  assert.equal((await api('PUT', '/transactions/' + uid(), { ...body, category_id: incomeCat })).status, 400);
  await api('DELETE', '/transactions/' + id);
});

test('last write wins, stale write ignored, soft delete', async () => {
  const id = uid();
  const base = { spent_at: today, merchant: 'LWW Shop', amount_cents: 1000, category_id: spendCat, payment_type: 'debit', source: 'manual' };
  await api('PUT', '/transactions/' + id, { ...base, updated_at: '2026-11-04T10:00:00.000Z' });
  const stale = await api('PUT', '/transactions/' + id, { ...base, amount_cents: 5, updated_at: '2026-11-04T09:00:00.000Z' });
  assert.equal(stale.json.applied, false);
  assert.equal((await api('GET', '/transactions/' + id)).json.transaction.amount_cents, 1000);
  const fresh = await api('PUT', '/transactions/' + id, { ...base, amount_cents: 1200, updated_at: '2026-11-04T11:00:00.000Z' });
  assert.equal(fresh.json.applied, true);
  assert.equal((await api('GET', '/transactions/' + id)).json.transaction.amount_cents, 1200);
  assert.equal((await api('DELETE', '/transactions/' + id)).status, 200);
  assert.equal((await api('DELETE', '/transactions/' + id)).status, 200);
  assert.equal((await api('GET', '/transactions?from=' + today + '&to=' + today)).json.transactions.some((t) => t.id === id), false);
  assert.equal((await api('GET', '/transactions?include_deleted=1&from=' + today + '&to=' + today)).json.transactions.some((t) => t.id === id), true);
  assert.equal((await api('DELETE', '/transactions/' + uid())).status, 404);
});

test('item split stores items and your share', async () => {
  const id = uid();
  const r = await api('PUT', '/transactions/' + id, {
    spent_at: today, merchant: 'Split Mart', amount_cents: 1500, receipt_total_cents: 4000, category_id: spendCat,
    payment_type: 'ewallet', source: 'scan',
    items: [{ id: uid(), name: 'Mine', price_cents: 1500, included: true }, { id: uid(), name: 'Friend', price_cents: 2500, included: false }],
  });
  assert.equal(r.status, 200);
  const t = (await api('GET', '/transactions/' + id)).json.transaction;
  assert.equal(t.items.length, 2);
  assert.equal(t.receipt_total_cents, 4000);
  await api('DELETE', '/transactions/' + id);
});

test('cap counts only in-cap spending; income and SPayLater stay outside', async () => {
  const before = (await api('GET', '/summary/week?date=' + today)).json;
  const mk = (extra) => ({ spent_at: today, merchant: 'Cap Test', amount_cents: 1000, category_id: spendCat, payment_type: 'cash', source: 'manual', ...extra });
  const ids = [uid(), uid(), uid()];
  await api('PUT', '/transactions/' + ids[0], mk({}));
  await api('PUT', '/transactions/' + ids[1], mk({ payment_type: 'spaylater', counts_toward_cap: 1 }));
  await api('PUT', '/transactions/' + ids[2], mk({ direction: 'income', category_id: incomeCat, amount_cents: 50000 }));
  const after = (await api('GET', '/summary/week?date=' + today)).json;
  assert.equal(after.spent_cents - before.spent_cents, 1000);
  assert.equal(after.left_cents, after.cap_cents - after.spent_cents);
  assert.equal(after.outside_cap_cents - before.outside_cap_cents, 1000);
  assert.equal(after.by_day.length, 7);
  assert.equal(after.cap_cents, 25000);
  const month = (await api('GET', '/summary/month?month=' + today.slice(0, 7))).json;
  assert.ok(month.income_cents >= 50000);
  assert.equal(month.kept_cents, month.income_cents - month.spent_cents);
  assert.equal((await api('GET', '/summary/month?month=2026-13')).status, 400);
  assert.equal((await api('GET', '/summary/week?date=bad')).status, 400);
  for (const i of ids) await api('DELETE', '/transactions/' + i);
});

test('rules and bills', async () => {
  const r = await api('PUT', '/rules/' + encodeURIComponent('Smoke  Kopitiam'), { category_id: spendCat });
  assert.equal(r.status, 200);
  const rules = (await api('GET', '/rules')).json.rules;
  assert.ok(rules.some((x) => x.merchant_key === r.json.rule.merchant_key));
  assert.equal((await api('PUT', '/rules/x', { category_id: incomeCat })).status, 400);
  const bills = (await api('GET', '/bills')).json.bills;
  assert.equal(bills.length >= 5, true);
  assert.equal(bills.filter((b) => b.kind === 'spaylater').reduce((s, b) => s + b.amount_cents, 0), 88778);
  const b0 = bills[0];
  const paid = await api('PUT', '/bills/' + b0.id, { name: b0.name, kind: b0.kind, due_date: b0.due_date, amount_cents: b0.amount_cents, paid_at: today });
  assert.equal(paid.status, 200);
  assert.equal(paid.json.bill.paid_at, today);
  await api('PUT', '/bills/' + b0.id, { name: b0.name, kind: b0.kind, due_date: b0.due_date, amount_cents: b0.amount_cents, paid_at: null });
});

test('csv export is formula-safe', async () => {
  const id = uid();
  await api('PUT', '/transactions/' + id, { spent_at: today, merchant: '=HYPERLINK("x")', amount_cents: 100, category_id: spendCat, payment_type: 'cash', source: 'manual' });
  const r = await api('GET', '/export.csv');
  assert.equal(r.status, 200);
  assert.match(r.res.headers.get('content-type'), /text\/csv/);
  assert.ok(r.text.includes("'=HYPERLINK"));
  assert.ok(!/,=HYPERLINK/.test(r.text));
  await api('DELETE', '/transactions/' + id);
});

test('custom categories: add, rename, keep out of the cap, delete moves entries to Other', async () => {
  const name = 'Zz ' + uid().slice(1, 9);
  const made = await api('POST', '/categories', { name, kind: 'spend', cap_default: false });
  assert.equal(made.status, 201);
  const cat = made.json.category;
  assert.equal(cat.name, name);
  assert.equal(cat.cap_default, 0);

  assert.equal((await api('POST', '/categories', { name: name.toUpperCase(), kind: 'spend' })).status, 400); // same name, different case
  assert.equal((await api('POST', '/categories', { name: '', kind: 'spend' })).status, 400);
  assert.equal((await api('POST', '/categories', { name: 'Nope', kind: 'saving' })).status, 400);

  const renamed = await api('PUT', '/categories/' + cat.id, { name: name + ' 2', cap_default: true, sort_order: 55 });
  assert.equal(renamed.status, 200);
  assert.equal(renamed.json.category.name, name + ' 2');
  assert.equal(renamed.json.category.cap_default, 1);
  assert.equal(renamed.json.category.sort_order, 55);

  const list = (await api('GET', '/categories')).json.categories;
  assert.ok(list.some((c) => c.id === cat.id && c.cap_default === 1));
  assert.equal(list.find((c) => c.name === 'Bills').cap_default, 0);
  const other = list.find((c) => c.name === 'Other');

  // the fallbacks are fixed
  assert.equal((await api('PUT', '/categories/' + other.id, { name: 'Misc' })).status, 400);
  assert.equal((await api('DELETE', '/categories/' + other.id)).status, 400);
  assert.equal((await api('PUT', '/categories/' + other.id, { cap_default: true })).status, 200);

  const id = uid();
  await api('PUT', '/transactions/' + id, { spent_at: today, merchant: 'Cat test', amount_cents: 100, category_id: cat.id, payment_type: 'cash', source: 'manual' });
  const gone = await api('DELETE', '/categories/' + cat.id);
  assert.equal(gone.status, 200);
  assert.equal(gone.json.moved_to, other.id);
  assert.equal(gone.json.moved_entries, 1);
  assert.equal((await api('GET', '/transactions/' + id)).json.transaction.category_id, other.id);
  assert.equal((await api('DELETE', '/categories/' + cat.id)).status, 404);
  await api('DELETE', '/transactions/' + id);
});

test('app state: stores a kv document, newest write wins, rejects bad shapes', async () => {
  const doc = (kv) => JSON.stringify({ v: 1, kv });
  const t1 = new Date().toISOString();
  const put = await api('PUT', '/state', { doc: doc({ 'goal.name': 'Trip', 'rule.mixue': '1' }), updated_at: t1 });
  assert.equal(put.status, 200);
  assert.equal(put.json.stored, true);

  const got = await api('GET', '/state');
  assert.equal(got.status, 200);
  assert.deepEqual(JSON.parse(got.json.doc).kv, { 'goal.name': 'Trip', 'rule.mixue': '1' });
  assert.equal(got.json.updated_at, t1);

  // an older write does not replace a newer copy: the server hands its copy back
  const stale = await api('PUT', '/state', { doc: doc({ 'goal.name': 'Old' }), updated_at: '2020-01-01T00:00:00.000Z' });
  assert.equal(stale.json.stored, false);
  assert.equal(JSON.parse(stale.json.doc).kv['goal.name'], 'Trip');

  assert.equal((await api('PUT', '/state', { doc: 'not json', updated_at: t1 })).status, 400);
  assert.equal((await api('PUT', '/state', { doc: JSON.stringify({ v: 1 }), updated_at: t1 })).status, 400);
  assert.equal((await api('PUT', '/state', { doc: doc({ a: 5 }), updated_at: t1 })).status, 400);
  assert.equal((await api('PUT', '/state', { doc: doc({ a: '1' }) })).status, 400);
  assert.equal((await api('GET', '/state', null, false)).status, 401);
});
