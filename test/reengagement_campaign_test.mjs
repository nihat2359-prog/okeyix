import test from 'node:test';
import assert from 'node:assert/strict';
import { processCampaignBatch } from '../supabase/functions/process_reengagement_notifications/campaign.mjs';
import { notificationPayload } from '../supabase/functions/process_reengagement_notifications/core.mjs';

const accepted = { status: 'accepted', code: 'FCM_ACCEPTED', http_status: 200 };
const items = Array.from({ length: 5 }, (_, i) => ({ id: `offline-${i}`, token: `fake-${i}` }));
const preview = { enabled: true, within_send_window: true, pending: 5 };
test('campaign preview/paused/quiet/empty states never contact Google', async () => {
  for (const changed of [{ enabled: false }, { within_send_window: false }, { pending: 0 }]) {
    const result = await processCampaignBatch({ rpc: async (action) => {
      assert.equal(action, 'preview'); return { ...preview, ...changed };
    }, getAccessToken: () => assert.fail('OAuth'), send: () => assert.fail('FCM') });
    assert.equal(result.mode, 'no_send');
  }
});
test('OAuth failure consumes no campaign recipients', async () => {
  await assert.rejects(processCampaignBatch({ rpc: async (action) => {
    assert.equal(action, 'preview'); return preview;
  }, getAccessToken: async () => { throw new Error('offline-auth-failed'); }, send: () => assert.fail('FCM') }));
});
test('five parallel sends persist with a pinned campaign and batch receipt', async () => {
  let claimed = false, active = 0, max = 0;
  const result = await processCampaignBatch({ rpc: async (action, id, data) => {
    if (action === 'preview') return preview;
    if (action === 'claim_batch') {
      if (claimed) return { items: [] };
      claimed = true; return { campaign_id: 'offline-campaign', batch_id: 'offline-batch', items };
    }
    assert.equal(action, 'finish_batch'); assert.equal(id, 'offline-campaign');
    assert.equal(data.batch_id, 'offline-batch'); assert.equal(data.results.length, 5);
    assert.deepEqual(data.results.map((r) => r.id), items.map((i) => i.id));
    assert.doesNotMatch(JSON.stringify(data), /fake-/);
    return { recorded: true };
  }, getAccessToken: async () => 'offline-access', send: async () => {
    max = Math.max(max, ++active);
    await new Promise((resolve) => setTimeout(resolve, 1)); active--; return accepted;
  } });
  assert.equal(max, 5); assert.equal(result.counts.accepted, 5);
});
test('unknown send and provider errors are persisted before stopping; never replay', async () => {
  for (const outcome of [{ status: 'unknown', code: 'NETWORK_OUTCOME_UNKNOWN' },
    { status: 'rejected', http_status: 429, code: 'QUOTA_EXCEEDED' }]) {
    const calls = [];
    await processCampaignBatch({ rpc: async (action) => {
      calls.push(action);
      if (action === 'preview') return preview;
      if (action === 'claim_batch') return { campaign_id: 'offline-campaign', batch_id: 'offline-batch', items };
      return { recorded: true };
    }, getAccessToken: async () => 'offline-access', send: async () => outcome });
    assert.deepEqual(calls, ['preview', 'claim_batch', 'finish_batch']);
  }
});
test('failed result persistence stops without taking another group', async () => {
  const calls = [];
  await assert.rejects(processCampaignBatch({ rpc: async (action) => {
    calls.push(action);
    if (action === 'preview') return preview;
    if (action === 'claim_batch') return { campaign_id: 'offline-campaign', batch_id: 'offline-batch', items };
    return { recorded: false };
  }, getAccessToken: async () => 'offline-access', send: async () => accepted }), /RESULT_NOT_RECORDED/);
  assert.deepEqual(calls, ['preview', 'claim_batch', 'finish_batch']);
});
test('invalid tokens do not stop the queue and there is no cumulative daily ceiling', async () => {
  let claims = 0;
  const result = await processCampaignBatch({ rpc: async (action) => {
    if (action === 'preview') return preview;
    if (action === 'claim_batch') { claims++; return { campaign_id: 'offline', batch_id: `batch-${claims}`, items }; }
    return { recorded: true };
  }, getAccessToken: async () => 'offline-access', send: async () => ({ status: 'invalid_token', http_status: 404, code: 'UNREGISTERED' }) });
  assert.equal(claims, 20); assert.equal(result.counts.invalid_token, 100);
  // 100 is a per-request runtime budget; the next invocation can claim more.
});
test('campaign deadline stops before reserving another group', async () => {
  let tick = 0;
  const result = await processCampaignBatch({ rpc: async (action) => { assert.equal(action, 'preview'); return preview; },
    getAccessToken: async () => 'offline', send: () => assert.fail('send'), now: () => (tick++ === 0 ? 0 : 45000) });
  assert.equal(result.counts.reserved, 0);
});
test('last interrupted group is recovered even when there are no pending devices', async () => {
  const calls = [];
  await processCampaignBatch({ rpc: async (action) => {
    calls.push(action);
    return action === 'preview' ? { ...preview, pending: 0, recoverable: 5 } : { items: [] };
  }, getAccessToken: async () => 'offline', send: () => assert.fail('no resend of interrupted group') });
  assert.deepEqual(calls, ['preview', 'claim_batch']);
});
test('renewal notification has 24h TTL and opens existing app without a new route', () => {
  const now = Date.parse('2026-10-30T13:00:00+03:00');
  const { message } = notificationPayload({ id: 'offline-id', token: 'fake-token', category: 'renewal',
    title: 'Okeyix yenilendi! 🀄', body: 'Uygulamayı güncelle, masaya katıl.' }, now);
  assert.equal(message.android.ttl, '86400s');
  assert.equal(Number(message.apns.headers['apns-expiration']), now / 1000 + 86400);
  assert.equal(message.data.category, 'renewal');
  assert.equal(message.data.table_id, undefined);
  assert.equal(message.notification.title, 'Okeyix yenilendi! 🀄');
});
