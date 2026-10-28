// Runs the actual endpoint handler offline with injected Deno/Supabase adapters.
// Node strips TypeScript syntax; this is not a replacement for deno check.
import test from 'node:test';
import assert from 'node:assert/strict';
import { stripTypeScriptTypes } from 'node:module';
import { readFileSync } from 'node:fs';
import * as core from '../supabase/functions/process_reengagement_notifications/core.mjs';

function handlerWith(env, createClient) {
  let handler;
  const source = readFileSync(new URL('../supabase/functions/process_reengagement_notifications/index.ts', import.meta.url), 'utf8')
    .replace(/^import .*;\r?\n/gm, '');
  const js = stripTypeScriptTypes(source);
  const names = ['createClient', 'googleAccessToken', 'processBatch', 'secretMatches', 'sendNotification', 'Deno'];
  new Function(...names, js)(createClient, core.googleAccessToken, core.processBatch,
    core.secretMatches, core.sendNotification, {
      env: { get: (name) => env[name] }, serve: (value) => { handler = value; },
    });
  return handler;
}
const secret = 'offline-test-secret-at-least-32-chars';
test('actual endpoint rejects unauthorized before creating a DB client', async () => {
  const handler = handlerWith({ REENGAGEMENT_CRON_SECRET: secret }, () => assert.fail('DB must not run'));
  assert.equal((await handler(new Request('https://offline.invalid', { method: 'POST', body: '{}' }))).status, 401);
  assert.equal((await handler(new Request('https://offline.invalid'))).status, 405);
});
test('actual endpoint preview and disabled process need no Firebase credentials', async () => {
  let calls = 0;
  const handler = handlerWith({ REENGAGEMENT_CRON_SECRET: secret, SUPABASE_URL: 'https://offline.invalid',
    SUPABASE_SERVICE_ROLE_KEY: 'fake-service-key' }, () => ({ rpc: async (name, args) => {
      assert.equal(name, 'okeyix_reengagement_worker');
      assert.equal(args.p_action, 'preview'); calls++;
      return { data: { enabled: false, dry_run: true }, error: null };
    } }));
  for (const mode of ['preview', 'process']) {
    const response = await handler(new Request('https://offline.invalid', {
      method: 'POST', headers: { 'x-reengagement-secret': secret }, body: JSON.stringify({ mode }),
    }));
    assert.equal(response.status, 200);
  }
  assert.equal(calls, 2);
});
test('actual endpoint sanitizes database errors', async () => {
  const handler = handlerWith({ REENGAGEMENT_CRON_SECRET: secret, SUPABASE_URL: 'https://offline.invalid',
    SUPABASE_SERVICE_ROLE_KEY: 'fake-service-key' }, () => ({ rpc: async () => ({
      error: { message: 'sensitive fake-token data' }, data: null,
    }) }));
  const response = await handler(new Request('https://offline.invalid', { method: 'POST',
    headers: { 'x-reengagement-secret': secret }, body: '{"mode":"process"}' }));
  assert.equal(response.status, 503);
  assert.doesNotMatch(await response.text(), /sensitive|fake-token/);
});
