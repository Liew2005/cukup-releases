import type { Context } from 'hono';
import { HttpError } from './types';

export const ID_RE = /^[A-Za-z0-9_-]{6,64}$/;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const ISO_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,3})?(Z|[+-]\d{2}:\d{2})$/;

export const bad = (message: string) => new HttpError(400, 'invalid_request', message);

export function isValidDate(s: unknown): s is string {
  if (typeof s !== 'string' || !DATE_RE.test(s)) return false;
  const d = new Date(`${s}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s;
}

/** Today's date in Asia/Kuala_Lumpur as YYYY-MM-DD. */
export function todayKL(now: Date = new Date()): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Kuala_Lumpur',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(now);
}

export function addDays(date: string, n: number): string {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

/** Monday of the week (Mon to Sun) that contains the date. */
export function mondayOf(date: string): string {
  const dow = new Date(`${date}T00:00:00Z`).getUTCDay(); // 0 = Sunday
  return addDays(date, -((dow + 6) % 7));
}

export function daysBetween(a: string, b: string): number {
  return Math.round((Date.parse(`${b}T00:00:00Z`) - Date.parse(`${a}T00:00:00Z`)) / 86400000);
}

export const nowIso = () => new Date().toISOString();

export function normIso(v: unknown, field: string): string {
  if (typeof v !== 'string' || !ISO_RE.test(v) || Number.isNaN(Date.parse(v))) {
    throw bad(`${field} must be an ISO 8601 timestamp, e.g. 2026-11-04T12:00:00Z`);
  }
  return new Date(v).toISOString();
}

export function isInt(v: unknown, min: number, max: number): v is number {
  return typeof v === 'number' && Number.isInteger(v) && v >= min && v <= max;
}

export function reqStr(v: unknown, field: string, max: number): string {
  if (typeof v !== 'string') throw bad(`${field} is required`);
  const s = v.trim();
  if (s.length < 1 || s.length > max) throw bad(`${field} must be 1 to ${max} characters`);
  return s;
}

export function optStr(v: unknown, field: string, max: number): string | null {
  if (v === undefined || v === null || v === '') return null;
  if (typeof v !== 'string' || v.length > max) throw bad(`${field} must be text up to ${max} characters`);
  return v.trim() || null;
}

export function oneOf<T extends string>(v: unknown, list: readonly T[], field: string): T {
  if (typeof v === 'string' && (list as readonly string[]).includes(v)) return v as T;
  throw bad(`${field} must be one of: ${list.join(', ')}`);
}

export function normalizeMerchant(s: string): string {
  return s.trim().toLowerCase().replace(/\s+/g, ' ');
}

export async function readJson(c: Context): Promise<Record<string, unknown>> {
  let body: unknown;
  try {
    body = await c.req.json();
  } catch {
    throw new HttpError(400, 'invalid_json', 'Body must be valid JSON');
  }
  if (typeof body !== 'object' || body === null || Array.isArray(body)) {
    throw new HttpError(400, 'invalid_json', 'Body must be a JSON object');
  }
  return body as Record<string, unknown>;
}
