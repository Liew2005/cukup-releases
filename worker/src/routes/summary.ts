import { Hono } from 'hono';
import type { D1Database } from '@cloudflare/workers-types';
import type { AppEnv } from '../types';
import { addDays, bad, isValidDate, mondayOf, todayKL, daysBetween } from '../util';

export const summary = new Hono<AppEnv>();

const IN_CAP = "t.deleted_at IS NULL AND t.direction = 'spend' AND t.counts_toward_cap = 1";

async function settingInt(db: D1Database, key: string, fallback: number): Promise<number> {
  const r = await db.prepare('SELECT value FROM settings WHERE key = ?').bind(key).first<{ value: string }>();
  const n = Number(r?.value);
  return Number.isInteger(n) && n > 0 ? n : fallback;
}

const one = (res: { results: unknown[] }): number => ((res.results[0] as { cents: number } | undefined)?.cents ?? 0);

summary.get('/week', async (c) => {
  const today = todayKL();
  const date = c.req.query('date') ?? today;
  if (!isValidDate(date)) throw bad('date must be YYYY-MM-DD');
  const start = mondayOf(date);
  const end = addDays(start, 6);
  const db = c.env.DB;
  const cap = await settingInt(db, 'weekly_cap_cents', 25000);

  const [totalRes, nonCapRes, catRes, dayRes] = await db.batch([
    db.prepare(`SELECT COALESCE(SUM(t.amount_cents), 0) AS cents FROM transactions t WHERE ${IN_CAP} AND t.spent_at BETWEEN ? AND ?`).bind(start, end),
    db
      .prepare(
        `SELECT COALESCE(SUM(t.amount_cents), 0) AS cents FROM transactions t
         WHERE t.deleted_at IS NULL AND t.direction = 'spend' AND t.counts_toward_cap = 0 AND t.spent_at BETWEEN ? AND ?`,
      )
      .bind(start, end),
    db
      .prepare(
        `SELECT c.id AS category_id, c.name, SUM(t.amount_cents) AS spent_cents
         FROM transactions t JOIN categories c ON c.id = t.category_id
         WHERE ${IN_CAP} AND t.spent_at BETWEEN ? AND ? GROUP BY c.id, c.name ORDER BY spent_cents DESC`,
      )
      .bind(start, end),
    db
      .prepare(`SELECT t.spent_at AS date, SUM(t.amount_cents) AS spent_cents FROM transactions t WHERE ${IN_CAP} AND t.spent_at BETWEEN ? AND ? GROUP BY t.spent_at`)
      .bind(start, end),
  ]);

  const spent = one(totalRes);
  const perDay = new Map((dayRes.results as { date: string; spent_cents: number }[]).map((r) => [r.date, r.spent_cents]));
  const by_day = Array.from({ length: 7 }, (_, i) => {
    const d = addDays(start, i);
    return { date: d, spent_cents: perDay.get(d) ?? 0, is_future: d > today };
  });

  const days_left = today < start ? 7 : today > end ? 0 : daysBetween(today, end);
  const left = cap - spent;
  return c.json({
    week_start: start,
    week_end: end,
    cap_cents: cap,
    spent_cents: spent,
    left_cents: left,
    over_cap_cents: Math.max(0, spent - cap),
    outside_cap_cents: one(nonCapRes),
    days_left,
    even_pace_cents: Math.round(cap / 7),
    safe_per_day_cents: days_left > 0 && left > 0 ? Math.floor(left / days_left) : null,
    by_category: catRes.results,
    by_day,
  });
});

summary.get('/month', async (c) => {
  const today = todayKL();
  const month = c.req.query('month') ?? today.slice(0, 7);
  if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(month)) throw bad('month must be YYYY-MM');
  const [y, m] = month.split('-').map(Number);
  const first = `${month}-01`;
  const last = new Date(Date.UTC(y, m, 0)).toISOString().slice(0, 10);
  const db = c.env.DB;
  const cap = await settingInt(db, 'weekly_cap_cents', 25000);
  const budget = await settingInt(db, 'monthly_budget_cents', 110000);

  const [dirRes, fixedRes, catRes, dayRes, capDayRes, sweepRes] = await db.batch([
    db.prepare('SELECT t.direction AS direction, SUM(t.amount_cents) AS cents FROM transactions t WHERE t.deleted_at IS NULL AND t.spent_at BETWEEN ? AND ? GROUP BY t.direction').bind(first, last),
    db.prepare("SELECT COALESCE(SUM(t.amount_cents), 0) AS cents FROM transactions t WHERE t.deleted_at IS NULL AND t.direction = 'spend' AND t.source = 'recurring' AND t.spent_at BETWEEN ? AND ?").bind(first, last),
    db
      .prepare(
        `SELECT c.id AS category_id, c.name, SUM(t.amount_cents) AS spent_cents
         FROM transactions t JOIN categories c ON c.id = t.category_id
         WHERE t.deleted_at IS NULL AND t.direction = 'spend' AND t.spent_at BETWEEN ? AND ?
         GROUP BY c.id, c.name ORDER BY spent_cents DESC`,
      )
      .bind(first, last),
    db.prepare("SELECT t.spent_at AS date, SUM(t.amount_cents) AS spent_cents FROM transactions t WHERE t.deleted_at IS NULL AND t.direction = 'spend' AND t.spent_at BETWEEN ? AND ? GROUP BY t.spent_at ORDER BY t.spent_at").bind(first, last),
    db.prepare(`SELECT t.spent_at AS date, SUM(t.amount_cents) AS cents FROM transactions t WHERE ${IN_CAP} AND t.spent_at BETWEEN ? AND ? GROUP BY t.spent_at`).bind(first, last),
    db.prepare("SELECT COALESCE(SUM(amount_cents), 0) AS cents FROM sweeps WHERE status = 'set_aside' AND deleted_at IS NULL AND week_start BETWEEN ? AND ?").bind(first, last),
  ]);

  let income = 0;
  let spent = 0;
  for (const r of dirRes.results as { direction: string; cents: number }[]) {
    if (r.direction === 'income') income = r.cents;
    else spent = r.cents;
  }

  const capByDay = new Map((capDayRes.results as { date: string; cents: number }[]).map((r) => [r.date, r.cents]));
  const weeks: { week_start: string; spent_cents: number; over_cap: boolean; partial: boolean }[] = [];
  for (let w = mondayOf(first); w <= last; w = addDays(w, 7)) {
    const wEnd = addDays(w, 6);
    let sum = 0;
    for (let d = w < first ? first : w; d <= (wEnd > last ? last : wEnd); d = addDays(d, 1)) sum += capByDay.get(d) ?? 0;
    weeks.push({ week_start: w, spent_cents: sum, over_cap: sum > cap, partial: w < first || wEnd > last || wEnd >= today });
  }

  return c.json({
    month,
    budget_cents: budget,
    income_cents: income,
    spent_cents: spent,
    fixed_cents: one(fixedRes),
    kept_cents: income - spent,
    set_aside_cents: one(sweepRes),
    weekly_cap_cents: cap,
    weeks,
    by_category: catRes.results,
    by_day: dayRes.results,
  });
});
