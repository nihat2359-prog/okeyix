import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { googleAccessToken, processBatch, secretMatches, sendNotification } from './core.mjs';
import { processCampaignBatch } from './campaign.mjs';

const json = (status: number, body: unknown) => new Response(JSON.stringify(body), {
  status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
});

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json(405, { error: 'POST_REQUIRED' });
  if (!await secretMatches(Deno.env.get('REENGAGEMENT_CRON_SECRET'), req.headers.get('x-reengagement-secret'))) {
    return json(401, { error: 'UNAUTHORIZED' });
  }
  try {
    const body = await req.json();
    if (!body || !['preview', 'process', 'campaign_preview', 'campaign_process'].includes(body.mode)
      || Object.keys(body).some((key) => key !== 'mode')) return json(400, { error: 'MODE_REQUIRED' });
    const campaign = body.mode.startsWith('campaign_');
    const url = Deno.env.get('SUPABASE_URL');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!url || !serviceKey) return json(503, { error: 'SERVER_CONFIGURATION_MISSING' });
    const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const rpc = async (action: string, id: string | null = null, result = {}) => {
      const { data, error } = await admin.rpc(campaign ? 'okeyix_renewal_worker' : 'okeyix_reengagement_worker', {
        p_action: action, p_id: id, p_result: result,
      });
      if (error) throw new Error('REENGAGEMENT_DATABASE_ERROR');
      return data;
    };
    if (body.mode === 'preview' || body.mode === 'campaign_preview') return json(200, await rpc('preview'));
    let project = '';
    const process = campaign ? processCampaignBatch : processBatch;
    const result = await process({ rpc, getAccessToken: async () => {
      const raw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON');
      if (!raw) throw new Error('FIREBASE_ACCOUNT_MISSING');
      const account = JSON.parse(raw);
      project = Deno.env.get('FIREBASE_PROJECT_ID') || account.project_id;
      if (typeof project !== 'string' || !/^[a-z][a-z0-9-]{3,62}$/.test(project)) {
        throw new Error('FIREBASE_PROJECT_INVALID');
      }
      return await googleAccessToken(account);
    }, send: (token: string, item: unknown) => sendNotification(project, token, item) });
    return json(200, result);
  } catch {
    // Database/Google errors can include credentials or raw tokens. Return only a
    // stable code. Individual FCM outcomes are retained as sanitized SQL history.
    return json(503, { error: 'REENGAGEMENT_PROCESS_FAILED', retry: 'NEXT_SCHEDULE_ONLY' });
  }
});
