// node --test scripts/receipt.test.mjs   (Node 22+ runs the .ts file directly)
import test from 'node:test';
import assert from 'node:assert/strict';
import { toCents, reconcile } from '../src/receipt.ts';

const TODAY = '2026-11-04';

test('toCents handles numbers and messy strings', () => {
  assert.equal(toCents(12.5), 1250);
  assert.equal(toCents(0.1 + 0.2), 30);
  assert.equal(toCents('RM 12.50'), 1250);
  assert.equal(toCents('1,234.50'), 123450);
  assert.equal(toCents('12,50'), 1250);
  assert.equal(toCents('-2.00'), -200);
  assert.equal(toCents('abc'), null);
  assert.equal(toCents(null), null);
  assert.equal(toCents(Infinity), null);
  assert.equal(toCents(1e12), null);
});

test('clean receipt: items + tax + rounding = total', () => {
  const r = reconcile({ merchant: ' Kopitiam  Lim Kee ', date: '2026-11-03', items: [{ name: 'Nasi lemak', price: 8.5 }, { name: 'Teh ais', price: 3.2 }], tax: 0.7, rounding: 0.05, total: 12.45 }, TODAY);
  assert.equal(r.merchant, 'Kopitiam Lim Kee');
  assert.equal(r.total_cents, 1245);
  assert.equal(r.tax_cents, 70);
  assert.equal(r.confidence, 0.95);
  assert.deepEqual(r.warnings, []);
});

test('service charge folds into tax', () => {
  const r = reconcile({ merchant: 'Cafe', items: [{ name: 'Set', price: 20 }], service_charge: 2, tax: 1.32, total: 23.32 }, TODAY);
  assert.equal(r.tax_cents, 332);
  assert.equal(r.confidence, 0.95);
});

test('prices already include tax', () => {
  const r = reconcile({ merchant: 'Mart', items: [{ name: 'A', price: 10 }, { name: 'B', price: 5 }], tax: 0.85, total: 15 }, TODAY);
  assert.ok(r.warnings.includes('prices_include_tax'));
  assert.equal(r.confidence, 0.9);
});

test('mismatch lowers confidence and says by how much', () => {
  const r = reconcile({ merchant: 'Mart', items: [{ name: 'A', price: 10 }], total: 25 }, TODAY);
  assert.equal(r.confidence, 0.5);
  assert.ok(r.warnings.includes('total_mismatch_1500'));
});

test('missing total is inferred; no items is flagged', () => {
  const a = reconcile({ merchant: 'X', items: [{ name: 'A', price: 4 }], tax: 0.24 }, TODAY);
  assert.equal(a.total_cents, 424);
  assert.ok(a.warnings.includes('total_inferred'));
  const b = reconcile({ merchant: 'X', items: [], total: 9.9 }, TODAY);
  assert.ok(b.warnings.includes('no_items'));
  assert.equal(b.total_cents, 990);
  assert.ok(b.confidence <= 0.4);
});

test('discount lines (negative prices) are allowed', () => {
  const r = reconcile({ merchant: 'Mart', items: [{ name: 'A', price: 10 }, { name: 'Promo', price: -2 }], total: 8 }, TODAY);
  assert.equal(r.items[1].price_cents, -200);
  assert.equal(r.confidence, 0.95);
});

test('garbage in is dropped safely', () => {
  const r = reconcile({ merchant: 42, date: '31/02/2026', items: [null, 'x', { name: '', price: 1 }, { name: 'Ok', price: 'free' }, { name: 'Good', price: '3.00' }], total: 'RM 3.00' }, TODAY);
  assert.equal(r.merchant, null);
  assert.equal(r.date, null);
  assert.equal(r.items.length, 1);
  assert.ok(r.warnings.includes('bad_date'));
  assert.ok(r.warnings.includes('no_merchant'));
  assert.ok(r.warnings.includes('some_items_dropped'));
});

test('future dates are rejected, today and tomorrow are fine', () => {
  assert.equal(reconcile({ merchant: 'X', date: '2027-01-01', items: [{ name: 'A', price: 1 }], total: 1 }, TODAY).date, null);
  assert.equal(reconcile({ merchant: 'X', date: '2026-11-04', items: [{ name: 'A', price: 1 }], total: 1 }, TODAY).date, '2026-11-04');
});

test('item cap and non-object input do not throw', () => {
  const items = Array.from({ length: 150 }, (_, i) => ({ name: `i${i}`, price: 1 }));
  assert.equal(reconcile({ items }, TODAY).items.length, 100);
  assert.doesNotThrow(() => reconcile({}, TODAY));
  assert.doesNotThrow(() => reconcile({ items: 'nope' }, TODAY));
});

test('quantity and unit price are kept; inconsistent unit price falls back to the line total', () => {
  const r = reconcile({ merchant: 'Chicken Rice', items: [{ name: 'Rice', qty: 3, unit_price: 11, price: 33 }, { name: 'Tea', qty: 2, unit_price: 2.2, price: 4.4 }, { name: 'Odd', qty: 2, unit_price: 5, price: 7 }], total: 44.4 }, TODAY);
  assert.deepEqual(r.items.map((i) => [i.qty, i.unit_cents, i.price_cents]), [[3, 1100, 3300], [2, 220, 440], [2, 350, 700]]);
});

test('no printed tax means no tax; service and SST are reported separately', () => {
  const none = reconcile({ merchant: 'Chicken Rice', items: [{ name: 'Rice', price: 45.9 }], tax: null, service_charge: 0, total: 45.9 }, TODAY);
  assert.equal(none.tax_cents, 0);
  assert.deepEqual(none.warnings, []);
  const both = reconcile({ merchant: 'Cafe', items: [{ name: 'Set', price: 14 }], service_charge: 1.4, tax: 0.92, rounding: 0.03, total: 16.35 }, TODAY);
  assert.equal(both.service_cents, 140);
  assert.equal(both.sst_cents, 92);
  assert.equal(both.tax_cents, 232);
});
