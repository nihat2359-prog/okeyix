import { createVerify } from 'node:crypto';
import { Buffer } from 'node:buffer';
const keyUrl = 'https://www.gstatic.com/admob/reward/verifier-keys.json';
let cached = [];
let expires = 0;

// Google signs the original, encoded query bytes preceding &signature=.
export async function verifyCallback(raw) {
  const cut = raw.indexOf('&signature=');
  if (cut < 1) throw new Error('Missing signature');
  const tail = new URLSearchParams(raw.slice(cut + 1));
  if ([...tail.keys()].join(',') !== 'signature,key_id') throw new Error('Invalid signature tail');
  const params = new URLSearchParams(raw.slice(0, cut));
  for (const key of params.keys()) {
    if (params.getAll(key).length !== 1) throw new Error('Duplicate parameter');
  }
  if (Date.now() >= expires) {
    const response = await fetch(keyUrl, { signal: AbortSignal.timeout(8000) });
    if (!response.ok) throw new Error('Key fetch failed');
    cached = (await response.json()).keys;
    expires = Date.now() + 3600000;
  }
  const key = cached.find(k => String(k.keyId) === tail.get('key_id'));
  if (!key) { expires = 0; throw new Error('Unknown key'); }
  const verifier = createVerify('SHA256');
  verifier.update(raw.slice(0, cut));
  if (!verifier.verify(key.pem, Buffer.from(tail.get('signature'), 'base64url'))) throw new Error('Invalid signature');
  return params;
}

