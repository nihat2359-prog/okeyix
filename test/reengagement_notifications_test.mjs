import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { secretMatches, classifyFcm, notificationPayload, sendNotification,
  processBatch, googleAccessToken } from '../supabase/functions/process_reengagement_notifications/core.mjs';

const item = { id: '00000000-0000-0000-0000-000000000001', token: 'fake-token', title: 'Başlık', body: 'İçerik' };
const preview = { enabled: true, dry_run: false, within_send_window: true, batch_size: 10, reasons: { eligible: 1 } };
test('dedicated secret rejects empty, weak and incorrect credentials', async () => {
  assert.equal(await secretMatches('', ''), false);
  assert.equal(await secretMatches('short', 'short'), false);
  assert.equal(await secretMatches('a'.repeat(32), 'b'.repeat(32)), false);
  assert.equal(await secretMatches('a'.repeat(32), 'a'.repeat(32)), true);
});
test('only explicit FCM UNREGISTERED invalidates a token', () => {
  const details = (errorCode) => ({ error: { details: [{ '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError', errorCode }] } });
  assert.equal(classifyFcm(404, details('UNREGISTERED')).status, 'invalid_token');
  assert.equal(classifyFcm(400, details('INVALID_ARGUMENT')).status, 'rejected');
  assert.equal(classifyFcm(404, {}).status, 'rejected');
  assert.equal(classifyFcm(200, {}).status, 'unknown');
  assert.equal(classifyFcm(200, { name: 'projects/fake/messages/1' }).status, 'accepted');
});
test('payload opens existing application, uses existing channel, expires by 21:00', () => {
  const now = Date.parse('2026-10-28T20:59:00+03:00');
  const { message } = notificationPayload(item, now);
  assert.deepEqual(message.notification, { title: item.title, body: item.body });
  assert.equal(message.android.notification.channel_id, 'invite_channel');
  assert.equal(message.android.ttl, '60s');
  assert.equal(message.data.table_id, undefined);
  assert.equal(message.data.type, undefined);
  assert.equal(message.data.category, 'reengagement');
  assert.equal(Number(message.apns.headers['apns-expiration']), Date.parse('2026-10-28T21:00:00+03:00') / 1000);
});
test('transport never retries a timeout and never returns tokens or raw errors', async () => {
  let calls = 0;
  const result = await sendNotification('okeyix-test', 'fake-access', item, async () => {
    calls++; throw new Error('fake-token secret-server-response');
  });
  assert.equal(calls, 1);
  assert.deepEqual(result, { status: 'unknown', code: 'NETWORK_OUTCOME_UNKNOWN' });
});
test('FCM transport uses v1 notification request', async () => {
  const result = await sendNotification('okeyix-test', 'fake-access', item, async (url, init) => {
    assert.equal(url, 'https://fcm.googleapis.com/v1/projects/okeyix-test/messages:send');
    assert.equal(init.headers.Authorization, 'Bearer fake-access');
    assert.equal(JSON.parse(init.body).message.token, item.token);
    return new Response(JSON.stringify({ name: 'projects/test/messages/1' }), { status: 200 });
  });
  assert.equal(result.status, 'accepted');
});
for (const [label, change] of [ ['disabled', { enabled: false }], ['dry run', { dry_run: true }],
  ['quiet hours', { within_send_window: false }], ['unknown permission / no eligible', { reasons: { permission_unknown: 3000 } }] ]) {
  test(`${label} performs no OAuth, reservation or FCM call`, async () => {
    const result = await processBatch({ rpc: async (action) => {
      assert.equal(action, 'preview'); return { ...preview, ...change };
    }, getAccessToken: () => assert.fail('OAuth must not run'), send: () => assert.fail('FCM must not run') });
    assert.equal(result.mode, 'no_send');
  });
}
test('OAuth failure reserves no stage', async () => {
  await assert.rejects(processBatch({ rpc: async (action) => { assert.equal(action, 'preview'); return preview; },
    getAccessToken: async () => { throw new Error('AUTH_FAILURE'); }, send: () => assert.fail('FCM') }), /AUTH_FAILURE/);
});
test('authorization recheck cancellation never reaches FCM', async () => {
  const calls = [];
  await processBatch({ rpc: async (action) => {
    calls.push(action);
    return action === 'preview' ? { ...preview, batch_size: 1 } : action === 'claim' ? { id: item.id } : { skipped: 'eligibility_changed' };
  }, getAccessToken: async () => 'access', send: () => assert.fail('FCM') });
  assert.deepEqual(calls, ['preview', 'claim', 'authorize']);
});
test('unknown result is persisted once and stops the batch', async () => {
  const calls = [];
  const result = await processBatch({ rpc: async (action, id, outcome) => {
    calls.push(action);
    if (action === 'preview') return preview;
    if (action === 'claim') return { id: item.id };
    if (action === 'authorize') return item;
    assert.equal(outcome.status, 'unknown'); return { recorded: true };
  }, getAccessToken: async () => 'access', send: async () => ({ status: 'unknown', code: 'NETWORK_OUTCOME_UNKNOWN' }) });
  assert.deepEqual(calls, ['preview', 'claim', 'authorize', 'finish']);
  assert.equal(result.counts.unknown, 1);
});
test('failed history persistence stops without another send', async () => {
  let sends = 0;
  await assert.rejects(processBatch({ rpc: async (action) => {
    if (action === 'preview') return preview;
    if (action === 'claim') return { id: item.id };
    if (action === 'authorize') return item;
    throw new Error('DB_OFFLINE');
  }, getAccessToken: async () => 'access', send: async () => { sends++; return { status: 'accepted' }; } }), /DB_OFFLINE/);
  assert.equal(sends, 1);
});
test('Google OAuth signs JWT with the existing Firebase messaging scope', async () => {
  const keys = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048,
    publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
  const pem = `-----BEGIN PRIVATE KEY-----\n${Buffer.from(await crypto.subtle.exportKey('pkcs8', keys.privateKey)).toString('base64')}\n-----END PRIVATE KEY-----`;
  const token = await googleAccessToken({ client_email: 'test@example.invalid', private_key: pem }, async (url, init) => {
    assert.equal(url, 'https://oauth2.googleapis.com/token');
    const jwt = init.body.get('assertion');
    const [header, body, signature] = jwt.split('.');
    assert.equal(JSON.parse(Buffer.from(body, 'base64url')).scope, 'https://www.googleapis.com/auth/firebase.messaging');
    assert.equal(await crypto.subtle.verify('RSASSA-PKCS1-v1_5', keys.publicKey,
      Buffer.from(signature, 'base64url'), new TextEncoder().encode(`${header}.${body}`)), true);
    return new Response('{"access_token":"offline-test-access"}');
  });
  assert.equal(token, 'offline-test-access');
});
test('cron installs inactive and dedicated endpoint validates its own secret', () => {
  const cron = readFileSync(new URL('../supabase/migrations/20261028000200_reengagement_cron.sql', import.meta.url), 'utf8');
  assert.match(cron, /'0 7-17 \* \* \*'/);
  assert.match(cron, /cron\.alter_job\(jobid,active:=false\)/);
  assert.match(cron, /x-reengagement-secret/);
  const index = readFileSync(new URL('../supabase/functions/process_reengagement_notifications/index.ts', import.meta.url), 'utf8');
  assert.match(index, /secretMatches/);
  assert.doesNotMatch(index, /console\.log/);
});
