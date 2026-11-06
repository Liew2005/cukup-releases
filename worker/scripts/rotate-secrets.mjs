// Usage (run it yourself in a terminal, from the worker folder):  node scripts/rotate-secrets.mjs
// Asks for your new app password (hidden), then sets APP_PASSWORD_HASH and a fresh random JWT_SECRET
// on the Worker. Nothing is printed or saved. Everyone is signed out, so sign in again with the new password.
import { pbkdf2Sync, randomBytes } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { existsSync, unlinkSync } from 'node:fs';

function ask(question) {
  return new Promise((resolve) => {
    process.stdout.write(question);
    const stdin = process.stdin;
    stdin.setRawMode(true);
    stdin.resume();
    stdin.setEncoding('utf8');
    let text = '';
    const onData = (chunk) => {
      for (const c of chunk) {
        if (c === '\r' || c === '\n' || c === '\u0004') {
          stdin.setRawMode(false);
          stdin.pause();
          stdin.off('data', onData);
          process.stdout.write('\n');
          return resolve(text);
        }
        if (c === '\u0003') process.exit(1);
        if (c === '\u007f' || c === '\b') text = text.slice(0, -1);
        else text += c;
      }
    };
    stdin.on('data', onData);
  });
}

function putSecret(name, value) {
  const r = spawnSync('npx', ['wrangler', 'secret', 'put', name], { input: value, shell: true, stdio: ['pipe', 'inherit', 'inherit'], encoding: 'utf8' });
  if (r.status !== 0) {
    console.error(`Could not set ${name}. Nothing else was changed.`);
    process.exit(1);
  }
}

const first = await ask('New app password (any length): ');
if (first.length < 1) {
  console.error('The password cannot be empty.');
  process.exit(1);
}
const second = await ask('Type it again: ');
if (first !== second) {
  console.error('They do not match. Nothing was changed.');
  process.exit(1);
}

const iterations = 100000; // Cloudflare Workers allows at most 100000 for PBKDF2
const salt = randomBytes(16);
const hash = pbkdf2Sync(first, salt, iterations, 32, 'sha256');
putSecret('APP_PASSWORD_HASH', `pbkdf2.${iterations}.${salt.toString('base64url')}.${hash.toString('base64url')}`);
putSecret('JWT_SECRET', randomBytes(48).toString('base64url'));

const old = new URL('../../.app-password.txt', import.meta.url);
if (existsSync(old)) {
  unlinkSync(old);
  console.log('Deleted the old .app-password.txt.');
}
console.log('Done. Open Cukup and sign in with the new password.');
