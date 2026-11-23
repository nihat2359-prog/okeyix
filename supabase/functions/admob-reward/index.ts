import { createClient } from 'npm:@supabase/supabase-js@2';
import { verifyCallback } from './verify.mjs';

Deno.serve(async request => {
  if (request.method !== 'GET') return new Response('Method not allowed', { status: 405 });
  try {
    const params = await verifyCallback(new URL(request.url).search.slice(1));
    // The AdMob console can use a synthetic ad_unit for URL verification.
    // A signed request without recipient/ticket can only test connectivity.
    if (!params.get('user_id') && !params.get('custom_data')) {
      return new Response('Verification OK; no reward credited');
    }
    const allowed = (Deno.env.get('ADMOB_REWARDED_UNITS') ??
      'ca-app-pub-4157424138716357/2553824684,ca-app-pub-4157424138716357/3727305559')
      .split(',').map(s => s.trim()).filter(Boolean);
    // Google SSV may report the numeric unit suffix rather than the SDK ID.
    const unit = params.get('ad_unit') ?? '';
    if (!allowed.length || !allowed.some(id => unit === id || unit === id.split('/').at(-1))) {
      throw new Error('Unknown ad unit');
    }
    const timestamp = Number(params.get('timestamp'));
    if (!Number.isFinite(timestamp) || timestamp > Date.now() + 300000 || timestamp < Date.now() - 86400000) throw new Error('Invalid timestamp');
    const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    const attempt = params.get('custom_data') ?? '';
    const user = params.get('user_id') ?? '';
    const transaction = params.get('transaction_id');
    if (!uuid.test(attempt) || !uuid.test(user) || !transaction) throw new Error('Invalid reward data');
    const client = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const { error } = await client.rpc('okeyix_credit_ad_reward', {
      p_attempt: attempt, p_user: user, p_transaction: transaction,
    });
    if (error) return new Response('Credit unavailable', { status: 500 });
    return new Response('OK');
  } catch (error) {
    console.warn('AdMob callback rejected:', error instanceof Error ? error.message : 'Unknown error');
    return new Response('Callback rejected', { status: 403 });
  }
});
