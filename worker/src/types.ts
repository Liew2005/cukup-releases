import type { D1Database } from '@cloudflare/workers-types';

export interface Env {
  DB: D1Database;
  JWT_SECRET: string;
  APP_PASSWORD_HASH: string;
  TOTP_SECRET?: string; // base32; when set, login also needs the 6-digit code from the authenticator app
  GEMINI_API_KEY?: string;
  GEMINI_MODEL?: string; // optional override, otherwise a fallback list is tried
  GEMINI_BASE_URL?: string; // tests only
}

export type AppEnv = { Bindings: Env };

export class HttpError extends Error {
  constructor(
    public status: 400 | 401 | 403 | 404 | 429 | 500 | 502 | 503,
    public code: string,
    message?: string,
  ) {
    super(message ?? code);
  }
}
