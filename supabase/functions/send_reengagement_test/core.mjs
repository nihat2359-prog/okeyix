import { classifyFcm, notificationPayload } from '../process_reengagement_notifications/core.mjs';

export async function sendTestNotification(project, accessToken, permit, request = fetch) {
  if (!/^[a-z][a-z0-9-]{3,62}$/.test(project)) throw new Error('FIREBASE_PROJECT_INVALID');
  const payload = notificationPayload({ ...permit, title: 'Okeyix test bildirimi',
    body: 'Bu bildirim yalnızca onayladığın cihaz için gönderildi.' });
  // A manually approved test may run at any hour, independently of automation.
  payload.message.data.category = 'reengagement_test';
  payload.message.android.ttl = '300s';
  payload.message.apns.headers['apns-expiration'] = String(Math.floor(Date.now() / 1000) + 300);
  try {
    const res = await request(`https://fcm.googleapis.com/v1/projects/${project}/messages:send`, {
      method: 'POST', signal: AbortSignal.timeout(10000),
      headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    let data;
    try { data = await res.json(); } catch { /* Never expose raw FCM response. */ }
    return classifyFcm(res.status, data);
  } catch {
    return { status: 'unknown', code: 'NETWORK_OUTCOME_UNKNOWN' };
  }
}

export async function runTest({ mode, rpc, getAccessToken, send }) {
  const preview = await rpc('preview');
  if (mode === 'preview' || !preview.ready) return { mode: 'no_send', ...preview };
  const access = await getAccessToken();
  const permit = await rpc('consume');
  if (!permit.ready || !permit.token || !/^[a-f0-9]{64}$/.test(permit.receipt || '')) {
    return { mode: 'no_send', reason: permit.reason || 'VALID_RECEIPT_REQUIRED' };
  }
  const result = await send(access, permit);
  let saved;
  try { saved = await rpc('finish', { ...result, receipt: permit.receipt }); } catch { /* Never replay a consumed permit. */ }
  return { ticket_id: permit.id, mode: 'test_result', ...result,
    result_persisted: saved?.recorded === true,
    note: 'accepted means FCM accepted, not confirmed delivery; never replay this ticket' };
}
