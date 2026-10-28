import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runTest, sendTestNotification } from '../supabase/functions/send_reengagement_test/core.mjs';
import { secretMatches, googleAccessToken } from '../supabase/functions/process_reengagement_notifications/core.mjs';

const id = '00000000-0000-0000-0000-000000000031';
const permit = { ready: true, id, token: 'synthetic-test-token', receipt: 'a'.repeat(64) };
for (const reason of ['TICKET_TARGET_MISMATCH','TICKET_NOT_APPROVED_OR_ALREADY_CONSUMED',
  'TEST_CONSENT_MISSING_OR_EXPIRED','EXISTING_PREFERENCE_DISABLED','TOKEN_CHANGED']) {
  test(`${reason} never reaches Google or FCM`, async () => {
    const result = await runTest({ mode: 'send', rpc: async (action) => {
      assert.equal(action, 'preview'); return { ready: false, reason };
    }, getAccessToken: () => assert.fail('OAuth'), send: () => assert.fail('FCM') });
    assert.equal(result.mode, 'no_send');
  });
}
test('preview never sends even if the ticket is approved', async () => {
  await runTest({ mode: 'preview', rpc: async () => ({ ready: true }),
    getAccessToken: () => assert.fail('OAuth'), send: () => assert.fail('FCM') });
});
test('OAuth failure does not consume the single-use permit', async () => {
  const actions = [];
  await assert.rejects(runTest({ mode: 'send', rpc: async (action) => {
    actions.push(action); return { ready: true };
  }, getAccessToken: async () => { throw new Error('AUTH'); }, send: () => assert.fail('FCM') }), /AUTH/);
  assert.deepEqual(actions, ['preview']);
});
test('eligibility change after OAuth cancels the send', async () => {
  await runTest({ mode: 'send', rpc: async (action) => action === 'preview'
    ? { ready: true } : { ready: false, reason: 'TOKEN_CHANGED' },
  getAccessToken: async () => 'fake', send: () => assert.fail('FCM') });
});
test('one authorized permit makes one FCM call and persists a sanitized result', async () => {
  const actions = []; let sends = 0;
  const result = await runTest({ mode: 'send', rpc: async (action, value) => {
    actions.push(action);
    if (action === 'preview') return { ready: true };
    if (action === 'consume') return permit;
    assert.equal(value.status, 'accepted'); assert.equal(value.receipt, permit.receipt); return { recorded: true };
  }, getAccessToken: async () => 'fake-access', send: async () => {
    sends++; return { status: 'accepted', code: 'FCM_ACCEPTED', http_status: 200 };
  } });
  assert.equal(sends, 1);
  assert.deepEqual(actions, ['preview','consume','finish']);
  assert.equal(result.status, 'accepted');
  assert.equal(result.result_persisted, true);
  assert.equal(result.token, undefined);
  assert.equal(result.receipt, undefined);
});
test('a persistence failure still reports the known FCM result and does not resend', async () => {
  let sends = 0;
  const result = await runTest({ mode: 'send', rpc: async (action) => {
    if (action === 'preview') return { ready: true };
    if (action === 'consume') return permit;
    throw new Error('DB_OFFLINE');
  }, getAccessToken: async () => 'fake', send: async () => {
    sends++; return { status: 'accepted', code: 'FCM_ACCEPTED' };
  } });
  assert.equal(sends, 1);
  assert.equal(result.status, 'accepted');
  assert.equal(result.result_persisted, false);
});
test('manual payload is one token, fixed text, normal app open, five-minute TTL', async () => {
  const result = await sendTestNotification('okeyix-test', 'fake', permit, async (url, init) => {
    assert.equal(url, 'https://fcm.googleapis.com/v1/projects/okeyix-test/messages:send');
    const { message } = JSON.parse(init.body);
    assert.equal(message.token, permit.token);
    assert.equal(message.topic, undefined);
    assert.equal(message.data.table_id, undefined);
    assert.equal(message.data.category, 'reengagement_test');
    assert.equal(message.android.ttl, '300s');
    assert.equal(message.android.notification.channel_id, 'invite_channel');
    return new Response('{"name":"projects/test/messages/one"}');
  });
  assert.equal(result.status, 'accepted');
});
test('manual transport timeouts are unknown and never retried', async () => {
  let calls = 0;
  const result = await sendTestNotification('okeyix-test', 'fake', permit, async () => {
    calls++; throw new Error('sensitive fake-token');
  });
  assert.equal(calls, 1);
  assert.equal(result.status, 'unknown');
  assert.doesNotMatch(JSON.stringify(result), /sensitive|fake-token/);
});

function endpoint(env, client) {
  let handler;
  const source = readFileSync(new URL('../supabase/functions/send_reengagement_test/index.ts', import.meta.url), 'utf8')
    .replace(/^import .*;\r?\n/gm, '');
  new Function('createClient','secretMatches','googleAccessToken','runTest','sendTestNotification','Deno',
    stripTypeScriptTypes(source))(client,secretMatches,googleAccessToken,runTest,sendTestNotification,
    { env: { get: (name) => env[name] }, serve: (value) => { handler = value; } });
  return handler;
}
const secret = 'independent-test-secret-more-than-32-chars';
const request = (body, key = secret) => new Request('https://offline.invalid', { method: 'POST',
  headers: { 'x-reengagement-test-secret': key }, body: JSON.stringify(body) });
test('endpoint rejects arbitrary recipient fields and missing independent secret', async () => {
  const handler = endpoint({ REENGAGEMENT_TEST_SECRET: secret }, () => assert.fail('DB'));
  assert.equal((await handler(request({ mode: 'send', ticket_id: id }, 'wrong'))).status, 401);
  assert.equal((await handler(request({ mode: 'send', ticket_id: id, token: 'other-token' }))).status, 400);
  assert.equal((await handler(request({ mode: 'send', ticket_id: id, user_id: id }))).status, 400);
  assert.equal((await handler(request({ mode: 'send', ticket_id: id }))).status, 503);
});
test('endpoint pins target to server configuration and cannot select an HTTP recipient', async () => {
  const user = '00000000-0000-0000-0000-000000000001';
  const device = '00000000-0000-0000-0000-000000000011';
  const handler = endpoint({ REENGAGEMENT_TEST_SECRET: secret, REENGAGEMENT_TEST_USER_ID: user,
    REENGAGEMENT_TEST_DEVICE_ID: device, SUPABASE_URL: 'https://offline.invalid',
    REENGAGEMENT_TEST_RPC_SECRET: 'independent-edge-rpc-secret-with-32-characters',
    SUPABASE_SERVICE_ROLE_KEY: 'fake' }, () => ({ rpc: async (name, args) => {
      assert.equal(name, 'okeyix_reengagement_test_worker');
      assert.equal(args.p_user_id, user); assert.equal(args.p_device_id, device);
      assert.equal(args.p_action, 'preview');
      assert.equal(args.p_rpc_secret, 'independent-edge-rpc-secret-with-32-characters');
      return { data: { ready: false, reason: 'TICKET_NOT_APPROVED_OR_ALREADY_CONSUMED' }, error: null };
    } }));
  assert.equal((await handler(request({ mode: 'send', ticket_id: id }))).status, 200);
});
test('an RPC capability or service key cannot replace the HTTP test secret', async () => {
  const handler = endpoint({ REENGAGEMENT_TEST_SECRET: secret,
    REENGAGEMENT_TEST_RPC_SECRET: 'independent-edge-rpc-secret-with-32-characters' }, () => assert.fail('DB'));
  assert.equal((await handler(request({ mode: 'send', ticket_id: id }, 'independent-edge-rpc-secret-with-32-characters'))).status, 401);
  assert.equal((await handler(request({ mode: 'send', ticket_id: id }, 'service-role-key'))).status, 401);
});
test('a consume response without its one-use receipt cannot reach FCM', async () => {
  await runTest({ mode: 'send', rpc: async (action) => action === 'preview' ? { ready: true }
    : { ready: true, id, token: 'fake' }, getAccessToken: async () => 'fake', send: () => assert.fail('FCM') });
});
