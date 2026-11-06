import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { todayKL } from '../util';

export const exportRoute = new Hono<AppEnv>();

const COLUMNS = [
  'id', 'spent_at', 'direction', 'merchant', 'category', 'amount_rm', 'amount_cents', 'receipt_total_cents',
  'tax_cents', 'payment_type', 'counts_toward_cap', 'source', 'reference', 'note', 'created_at', 'updated_at', 'deleted_at',
] as const;

function cell(v: unknown): string {
  if (v === null || v === undefined) return '';
  let s = String(v);
  if (/^[=+\-@\t\r]/.test(s)) s = `'${s}`; // stop a spreadsheet from running text as a formula
  return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

exportRoute.get('/export.csv', async (c) => {
  const includeDeleted = c.req.query('include_deleted') === '1';
  const res = await c.env.DB
    .prepare(
      `SELECT t.id, t.spent_at, t.direction, t.merchant, c.name AS category, t.amount_cents, t.receipt_total_cents,
              t.tax_cents, t.payment_type, t.counts_toward_cap, t.source, t.reference, t.note, t.created_at, t.updated_at, t.deleted_at
       FROM transactions t JOIN categories c ON c.id = t.category_id
       ${includeDeleted ? '' : 'WHERE t.deleted_at IS NULL'} ORDER BY t.spent_at, t.created_at`,
    )
    .all<Record<string, unknown>>();

  const lines = [COLUMNS.join(',')];
  for (const r of res.results) {
    const row = { ...r, amount_rm: ((r.amount_cents as number) / 100).toFixed(2) };
    lines.push(COLUMNS.map((k) => cell((row as Record<string, unknown>)[k])).join(','));
  }
  return new Response('\uFEFF' + lines.join('\r\n') + '\r\n', {
    headers: {
      'Content-Type': 'text/csv; charset=utf-8',
      'Content-Disposition': `attachment; filename="cukup-export-${todayKL()}.csv"`,
    },
  });
});
