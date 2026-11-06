import { Hono } from 'hono';
import { signToken, verifyPassword } from '../auth';
import { verifyTotp } from '../totp';
import { HttpError, type AppEnv } from '../types';
import { readJson } from '../util';

export const auth = new Hono<AppEnv>();

/** Lets the login screen know whether to ask for a code. Reveals nothing secret. */
auth.get('/config', (c) => c.json({ totp: Boolean(c.env.TOTP_SECRET) }));

const MAX_FAILURES = 5;
const WINDOW_MS = 15 * 60 * 1000;

auth.post('/login', async (c) => {
  if (!c.env.JWT_SECRET || !c.env.APP_PASSWORD_HASH) {
    throw new HttpError(500, 'server_misconfigured', 'Secrets are not set');
  }
  const db = c.env.DB;
  const ip = c.req.header('CF-Connecting-IP') ?? 'local';
  const since = new Date(Date.now() - WINDOW_MS).toISOString();

  await db.prepare('DELETE FROM login_attempts WHERE at < ?').bind(since).run();
  const row = await db
    .prepare('SELECT COUNT(*) AS n FROM login_attempts WHERE ip = ? AND at >= ?')
    .bind(ip, since)
    .first<{ n: number }>();
  if ((row?.n ?? 0) >= MAX_FAILURES) {
    throw new HttpError(429, 'too_many_attempts', 'Too many failed tries. Wait 15 minutes.');
  }

  const body = await readJson(c);
  const password = typeof body.password === 'string' ? body.password : '';
  const passwordOk = password.length > 0 && password.length <= 200 && (await verifyPassword(password, c.env.APP_PASSWORD_HASH));
  // Two-factor: when TOTP_SECRET is set, the code is checked every time, so the error never says which half was wrong.
  const code = typeof body.code === 'string' ? body.code.replace(/\s/g, '') : '';
  const codeOk = c.env.TOTP_SECRET ? await verifyTotp(c.env.TOTP_SECRET, code) : true;
  if (!passwordOk || !codeOk) {
    await db.prepare('INSERT INTO login_attempts (ip, at) VALUES (?, ?)').bind(ip, new Date().toISOString()).run();
    throw new HttpError(401, 'invalid_credentials', c.env.TOTP_SECRET ? 'Wrong password or code' : 'Wrong password');
  }

  await db.prepare('DELETE FROM login_attempts WHERE ip = ?').bind(ip).run();
  const { token, expiresIn } = await signToken(c.env.JWT_SECRET);
  return c.json({ token, expires_in: expiresIn });
});
