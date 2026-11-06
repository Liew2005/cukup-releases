// Turns on two-factor login (a 6-digit code from an authenticator app).
// Run it yourself in a terminal from the worker folder:   node scripts/setup-2fa.mjs
// To turn it off again:                                    node scripts/setup-2fa.mjs --off
// Lost your phone? Run it again: it makes a new secret and the old codes stop working.
import { randomBytes, createHmac } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { createInterface } from 'node:readline/promises';
import { stdin, stdout } from 'node:process';

const B32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

function wrangler(args, input) {
  return spawnSync('npx', ['wrangler', ...args], { input, shell: true, stdio: ['pipe', 'inherit', 'inherit'], encoding: 'utf8' });
}

if (process.argv.includes('--off')) {
  const r = wrangler(['secret', 'delete', 'TOTP_SECRET'], 'y\n');
  console.log(r.status === 0 ? 'Two-factor login is off. Passwords alone work again.' : 'Could not remove it. Nothing changed.');
  process.exit(r.status === 0 ? 0 : 1);
}

function base32(buf) {
  let bits = 0, value = 0, out = '';
  for (const b of buf) {
    value = (value << 8) | b;
    bits += 8;
    while (bits >= 5) {
      out += B32[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) out += B32[(value << (5 - bits)) & 31];
  return out;
}

function base32Decode(s) {
  let bits = 0, value = 0;
  const out = [];
  for (const ch of s) {
    value = (value << 5) | B32.indexOf(ch);
    bits += 5;
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 255);
      bits -= 8;
    }
  }
  return Buffer.from(out);
}

function code(secret, atMs) {
  const counter = Math.floor(atMs / 30000);
  const msg = Buffer.alloc(8);
  msg.writeUInt32BE(Math.floor(counter / 2 ** 32), 0);
  msg.writeUInt32BE(counter >>> 0, 4);
  const h = createHmac('sha1', base32Decode(secret)).update(msg).digest();
  const off = h[19] & 15;
  const n = ((h[off] & 0x7f) << 24) | (h[off + 1] << 16) | (h[off + 2] << 8) | h[off + 3];
  return String(n % 1000000).padStart(6, '0');
}

const secret = base32(randomBytes(20));
const spaced = secret.match(/.{1,4}/g).join(' ');
console.log('\nOpen your authenticator app (Google Authenticator, Aegis, Authy...), choose');
console.log('"Add account" then "Enter a setup key", and type:\n');
console.log('  Account name:  Cukup');
console.log(`  Key:           ${spaced}`);
console.log('  Type:          Time based\n');
console.log('Or open this link on the phone that has the app:');
console.log(`  otpauth://totp/Cukup?secret=${secret}&issuer=Cukup\n`);

const rl = createInterface({ input: stdin, output: stdout });
const typed = (await rl.question('Type the 6-digit code the app shows now: ')).replace(/\s/g, '');
rl.close();
const now = Date.now();
if (![-30000, 0, 30000].some((d) => code(secret, now + d) === typed)) {
  console.error('That code did not match, so nothing was changed. Run the script again.');
  process.exit(1);
}

const r = wrangler(['secret', 'put', 'TOTP_SECRET'], secret + '\n');
if (r.status !== 0) {
  console.error('Could not save the secret. Nothing was changed.');
  process.exit(1);
}
console.log('\nDone. From now on, signing in needs your password and a code from the app.');
console.log('Keep the account in your authenticator app. If you lose the phone, run this script again.');
