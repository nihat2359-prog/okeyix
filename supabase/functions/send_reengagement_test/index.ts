import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { secretMatches, googleAccessToken } from '../process_reengagement_notifications/core.mjs';
import { runTest, sendTestNotification } from './core.mjs';

const json = (status: number, body: unknown) => new Response(JSON.stringify(body), {
  status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
});
const uuid = (v: unknown): v is string => typeof v === 'string'
  && /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(v);

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json(405, { error: 'POST_REQUIRED' });
  if (!await secretMatches(Deno.env.get('REENGAGEMENT_TEST_SECRET'), req.headers.get('x-reengagement-test-secret'))) {
    return json(401, { error: 'UNAUTHORIZED' });
  }
  let phase = 'REQUEST';
  try {
    const body = await req.json();
    // No request-supplied recipient, raw token, title, body or batch is accepted.
    if (!body || Object.keys(body).some((k) => !['mode','ticket_id'].includes(k))
      || !['preview','send'].includes(body.mode) || !uuid(body.ticket_id)) {
      return json(400, { error: 'MODE_AND_TICKET_ONLY' });
    }
    const user = Deno.env.get('REENGAGEMENT_TEST_USER_ID');
    const device = Deno.env.get('REENGAGEMENT_TEST_DEVICE_ID');
    const url = Deno.env.get('SUPABASE_URL');
    const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const rpcSecret = Deno.env.get('REENGAGEMENT_TEST_RPC_SECRET');
    if (!uuid(user) || !uuid(device) || !url || !key || !rpcSecret
      || rpcSecret.length < 32 || rpcSecret.length > 256
      || rpcSecret === Deno.env.get('REENGAGEMENT_TEST_SECRET')) {
      return json(503, { error: 'TEST_TARGET_OR_RPC_SECRET_NOT_CONFIGURED' });
    }
    const admin = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
    const rpc = async (action: string, result = {}) => {
      const { data, error } = await admin.rpc('okeyix_reengagement_test_worker', {
        p_action: action, p_ticket_id: body.ticket_id, p_user_id: user, p_device_id: device,
        p_rpc_secret: rpcSecret, p_result: result,
      });
      if (error) throw new Error('DATABASE_ERROR');
      return data;
    };
    let project = '';
    const result = await runTest({ mode: body.mode, rpc, getAccessToken: async () => {
      phase = 'GOOGLE_AUTH';
      const account = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON') || '{}');
      project = Deno.env.get('FIREBASE_PROJECT_ID') || account.project_id;
      if (typeof project !== 'string' || !/^[a-z][a-z0-9-]{3,62}$/.test(project)) throw new Error('FIREBASE_CONFIGURATION');
      const token = await googleAccessToken(account);
      phase = 'DISPATCH';
      return token;
    }, send: (token: string, permit: unknown) => sendTestNotification(project, token, permit) });
    return json(200, result);
  } catch {
    return json(503, { error: phase === 'GOOGLE_AUTH' ? 'GOOGLE_AUTH_OR_FIREBASE_CONFIGURATION_FAILED'
      : phase === 'DISPATCH' ? 'TEST_DISPATCH_OR_RESULT_PERSIST_FAILED' : 'TEST_REQUEST_OR_DATABASE_FAILED',
      retry: 'INSPECT_TICKET_DO_NOT_AUTOMATICALLY_RETRY' });
  }
});
