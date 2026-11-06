// Checks src/totp.ts against the RFC 6238 test vectors. Run:  node --experimental-strip-types scripts/totp-check.mjs
import { base32Decode, hotp, verifyTotp } from '../src/totp.ts';

// RFC 6238 uses the ASCII key "12345678901234567890"; its base32 form is GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ.
const secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
const key = base32Decode(secret);
let failed = 0;
const eq = (name, got, want) => {
  if (got !== want) {
    failed++;
    console.error(`FAIL ${name}: got ${got}, want ${want}`);
  } else console.log(`ok   ${name}`);
};

// RFC vectors (SHA-1, shown as 8 digits in the RFC; the last 6 digits are what we produce)
eq('t=59', await hotp(key, Math.floor(59 / 30)), '287082');
eq('t=1111111109', await hotp(key, Math.floor(1111111109 / 30)), '081804');
eq('t=1111111111', await hotp(key, Math.floor(1111111111 / 30)), '050471');
eq('t=1234567890', await hotp(key, Math.floor(1234567890 / 30)), '005924');
eq('t=2000000000', await hotp(key, Math.floor(2000000000 / 30)), '279037');

const now = 1111111109 * 1000;
eq('accepts the current code', await verifyTotp(secret, '081804', now), true);
eq('accepts the previous step (drift)', await verifyTotp(secret, '081804', now + 30_000), true);
eq('rejects two steps old', await verifyTotp(secret, '081804', now + 90_000), false);
eq('rejects a wrong code', await verifyTotp(secret, '000000', now), false);
eq('rejects non-digits', await verifyTotp(secret, '12ab56', now), false);
eq('rejects short codes', await verifyTotp(secret, '8180', now), false);
eq('rejects a broken secret', await verifyTotp('not base32!!', '081804', now), false);

console.log(failed ? `${failed} failed` : 'all passed');
process.exit(failed ? 1 : 0);
