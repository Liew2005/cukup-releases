// Usage: node scripts/hash-password.mjs "your password (10+ characters)"
// Prints a value for the APP_PASSWORD_HASH secret. Format: pbkdf2.<iterations>.<salt>.<hash> (base64url).
import { pbkdf2Sync, randomBytes } from 'node:crypto';

const password = process.argv[2];
if (!password || password.length < 10) {
  console.error('Usage: node scripts/hash-password.mjs "<password, at least 10 characters>"');
  process.exit(1);
}
const iterations = 100000; // Cloudflare Workers allows at most 100000 for PBKDF2
const salt = randomBytes(16);
const hash = pbkdf2Sync(password, salt, iterations, 32, 'sha256');
console.log(`pbkdf2.${iterations}.${salt.toString('base64url')}.${hash.toString('base64url')}`);
