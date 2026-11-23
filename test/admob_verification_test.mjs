import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, createSign } from 'node:crypto';
import { verifyCallback } from '../supabase/functions/admob-reward/verify.mjs';

test('Google SSV verifies exact query bytes and rejects forged rewards', async () => {
  const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const previousFetch = globalThis.fetch;
  globalThis.fetch = async () => new Response(JSON.stringify({ keys: [{
    keyId: 123, pem: publicKey.export({ type: 'spki', format: 'pem' }),
  }] }));
  try {
    const raw = 'ad_unit=unit&custom_data=ticket&user_id=player&transaction_id=tx&timestamp=123';
    const signer = createSign('SHA256');
    signer.update(raw);
    const signed = `${raw}&signature=${signer.sign(privateKey).toString('base64url')}&key_id=123`;
    assert.equal((await verifyCallback(signed)).get('custom_data'), 'ticket');
    await assert.rejects(verifyCallback(signed.replace('ticket', 'stolen')));
    await assert.rejects(verifyCallback(signed + '&user_id=attacker'));
    await assert.rejects(verifyCallback(raw));
    await assert.rejects(verifyCallback(signed.replace('user_id=player', 'user_id=player&user_id=attacker')));
  } finally { globalThis.fetch = previousFetch; }
});
