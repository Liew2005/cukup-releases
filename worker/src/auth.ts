import type { MiddlewareHandler } from 'hono';
import { HttpError, type AppEnv } from './types';

const enc = new TextEncoder();
const TOKEN_TTL_SECONDS = 30 * 24 * 60 * 60;

function b64uEncode(bytes: Uint8Array): string {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function b64uDecode(str: string): Uint8Array<ArrayBuffer> {
  const pad = '='.repeat((4 - (str.length % 4)) % 4);
  const bin = atob(str.replace(/-/g, '+').replace(/_/g, '/') + pad);
  return Uint8Array.from(bin, (ch) => ch.charCodeAt(0));
}

const hmacKey = (secret: string, usages: KeyUsage[]) =>
  crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, usages);

export async function signToken(secret: string): Promise<{ token: string; expiresIn: number }> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64uEncode(enc.encode(JSON.stringify({ alg: 'HS256', typ: 'JWT' })));
  const payload = b64uEncode(enc.encode(JSON.stringify({ sub: 'owner', iat: now, exp: now + TOKEN_TTL_SECONDS })));
  const data = `${header}.${payload}`;
  const sig = await crypto.subtle.sign('HMAC', await hmacKey(secret, ['sign']), enc.encode(data));
  return { token: `${data}.${b64uEncode(new Uint8Array(sig))}`, expiresIn: TOKEN_TTL_SECONDS };
}

export async function verifyToken(secret: string, token: string): Promise<boolean> {
  const parts = token.split('.');
  if (parts.length !== 3) return false;
  try {
    const header = JSON.parse(new TextDecoder().decode(b64uDecode(parts[0])));
    if (header.alg !== 'HS256') return false;
    const ok = await crypto.subtle.verify(
      'HMAC',
      await hmacKey(secret, ['verify']),
      b64uDecode(parts[2]),
      enc.encode(`${parts[0]}.${parts[1]}`),
    );
    if (!ok) return false;
    const payload = JSON.parse(new TextDecoder().decode(b64uDecode(parts[1])));
    return typeof payload.exp === 'number' && payload.exp > Math.floor(Date.now() / 1000);
  } catch {
    return false;
  }
}

function constantTimeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

/** Stored format: pbkdf2.<iterations>.<salt b64url>.<hash b64url>. Make one with scripts/hash-password.mjs. */
export async function verifyPassword(password: string, stored: string): Promise<boolean> {
  const parts = stored.split('.');
  if (parts.length !== 4 || parts[0] !== 'pbkdf2') return false;
  const iterations = Number(parts[1]);
  if (!Number.isInteger(iterations) || iterations < 1000 || iterations > 100000) return false;
  try {
    const salt = b64uDecode(parts[2]);
    const expected = b64uDecode(parts[3]);
    const key = await crypto.subtle.importKey('raw', enc.encode(password), 'PBKDF2', false, ['deriveBits']);
    const bits = new Uint8Array(
      await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt, iterations }, key, expected.length * 8),
    );
    return constantTimeEqual(bits, expected);
  } catch {
    return false;
  }
}

export const requireAuth: MiddlewareHandler<AppEnv> = async (c, next) => {
  if (!c.env.JWT_SECRET) throw new HttpError(500, 'server_misconfigured', 'JWT_SECRET is not set');
  const match = /^Bearer (.+)$/.exec(c.req.header('Authorization') ?? '');
  if (!match || !(await verifyToken(c.env.JWT_SECRET, match[1]))) {
    throw new HttpError(401, 'unauthorized', 'Missing or invalid token');
  }
  await next();
};


