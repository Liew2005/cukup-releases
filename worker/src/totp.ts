// Time-based one-time codes (RFC 6238): the 6-digit codes an authenticator app shows every 30 seconds.

const B32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

export function base32Decode(input: string): Uint8Array {
  const clean = input.toUpperCase().replace(/[\s=-]/g, '');
  let bits = 0;
  let value = 0;
  const out: number[] = [];
  for (const ch of clean) {
    const idx = B32.indexOf(ch);
    if (idx < 0) throw new Error('not base32');
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return new Uint8Array(out);
}

export async function hotp(key: Uint8Array, counter: number): Promise<string> {
  const msg = new ArrayBuffer(8);
  const view = new DataView(msg);
  view.setUint32(0, Math.floor(counter / 2 ** 32));
  view.setUint32(4, counter >>> 0);
  const k = await crypto.subtle.importKey('raw', key as unknown as ArrayBuffer, { name: 'HMAC', hash: 'SHA-1' }, false, ['sign']);
  const sig = new Uint8Array(await crypto.subtle.sign('HMAC', k, msg));
  const off = sig[19] & 0x0f;
  const n = ((sig[off] & 0x7f) << 24) | (sig[off + 1] << 16) | (sig[off + 2] << 8) | sig[off + 3];
  return String(n % 1_000_000).padStart(6, '0');
}

function sameText(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** True when [code] is the current code, or the one just before or after (clock drift between phone and server). */
export async function verifyTotp(secretBase32: string, code: string, nowMs = Date.now(), window = 1): Promise<boolean> {
  if (!/^\d{6}$/.test(code)) return false;
  let key: Uint8Array;
  try {
    key = base32Decode(secretBase32);
  } catch {
    return false;
  }
  const step = Math.floor(nowMs / 30_000);
  let ok = false;
  for (let d = -window; d <= window; d++) {
    if (sameText(await hotp(key, step + d), code)) ok = true; // check all three so timing does not reveal which one matched
  }
  return ok;
}
