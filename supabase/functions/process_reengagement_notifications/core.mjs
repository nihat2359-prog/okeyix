// Standard Web APIs only. Shared by Deno runtime and offline Node tests.
// Never log tokens, Google response bodies, JWTs or service-account contents.
export async function secretMatches(expected, supplied) {
  if (!expected || expected.length < 32 || !supplied) return false;
  const hash = async (s) => new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s)));
  const [a, b] = await Promise.all([hash(expected), hash(supplied)]);
  let different = 0;
  for (let i = 0; i < a.length; i++) different |= a[i] ^ b[i];
  return different === 0;
}

function base64url(bytes) {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export async function googleAccessToken(account, request = fetch) {
  if (!account?.client_email || !account?.private_key) throw new Error('FIREBASE_ACCOUNT_INVALID');
  const encode = (v) => base64url(new TextEncoder().encode(JSON.stringify(v)));
  const now = Math.floor(Date.now() / 1000);
  const content = `${encode({ alg: 'RS256', typ: 'JWT' })}.${encode({
    iss: account.client_email, scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token', iat: now, exp: now + 3600,
  })}`;
  const pem = account.private_key.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, '');
  const bytes = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', bytes,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(content));
  const response = await request('https://oauth2.googleapis.com/token', {
    method: 'POST', signal: AbortSignal.timeout(10000),
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${content}.${base64url(new Uint8Array(signature))}` }),
  });
  if (!response.ok) throw new Error('GOOGLE_AUTH_FAILED');
  const data = await response.json();
  if (typeof data.access_token !== 'string' || !data.access_token) throw new Error('GOOGLE_AUTH_FAILED');
  return data.access_token;
}

export function notificationPayload(item, now = Date.now()) {
  // No table_id or new navigation contract: OS opens the existing app normally.
  // End queued delivery at the end of today's Istanbul send window (UTC+3).
  const day = new Date(now + 3 * 3600000).toISOString().slice(0, 10);
  const end = Date.parse(`${day}T21:00:00+03:00`);
  const campaign = item.category === 'renewal';
  const ttl = campaign ? 86400 : Math.max(0, Math.min(3600, Math.floor((end - now) / 1000)));
  return { message: {
    token: item.token,
    notification: { title: item.title, body: item.body },
    data: { category: campaign ? 'renewal' : 'reengagement', notification_id: item.id },
    android: { priority: 'normal', ttl: `${ttl}s`,
      notification: { channel_id: 'invite_channel', sound: 'default' } },
    apns: { headers: { 'apns-priority': '10', 'apns-push-type': 'alert',
      'apns-expiration': String(Math.floor((now + ttl * 1000) / 1000)),
      'apns-collapse-id': item.id },
      payload: { aps: { alert: { title: item.title, body: item.body }, sound: 'default' } } },
  } };
}

export function classifyFcm(status, data) {
  if (status >= 200 && status < 300) {
    return data && typeof data.name === 'string' && data.name.length > 0
      ? { status: 'accepted', http_status: status, code: 'FCM_ACCEPTED' }
      : { status: 'unknown', http_status: status, code: 'FCM_RESPONSE_UNRECOGNIZED' };
  }
  const details = Array.isArray(data?.error?.details) ? data.error.details : [];
  const error = details.find((d) => d?.['@type'] === 'type.googleapis.com/google.firebase.fcm.v1.FcmError')?.errorCode;
  // INVALID_ARGUMENT can mean a malformed payload. Never invalidate for it.
  if (error === 'UNREGISTERED') return { status: 'invalid_token', http_status: status, code: 'UNREGISTERED' };
  const codes = new Set(['INVALID_ARGUMENT', 'SENDER_ID_MISMATCH', 'QUOTA_EXCEEDED',
    'UNAVAILABLE', 'INTERNAL', 'THIRD_PARTY_AUTH_ERROR']);
  return { status: 'rejected', http_status: status, code: codes.has(error) ? error : `FCM_HTTP_${status}` };
}

export async function sendNotification(project, accessToken, item, request = fetch) {
  if (!/^[a-z][a-z0-9-]{3,62}$/.test(project)) throw new Error('FIREBASE_PROJECT_INVALID');
  try {
    const response = await request(`https://fcm.googleapis.com/v1/projects/${project}/messages:send`, {
      method: 'POST', signal: AbortSignal.timeout(10000),
      headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(notificationPayload(item)),
    });
    let data;
    try { data = await response.json(); } catch { /* Do not log response bodies. */ }
    return classifyFcm(response.status, data);
  } catch {
    // Network failure may happen AFTER FCM accepts a request. Never auto-retry.
    return { status: 'unknown', code: 'NETWORK_OUTCOME_UNKNOWN' };
  }
}

export async function processBatch({ rpc, getAccessToken, send, now = Date.now }) {
  const preview = await rpc('preview');
  if (!preview.enabled || preview.dry_run || !preview.within_send_window || !(preview.reasons?.eligible > 0)) {
    return { mode: 'no_send', preview };
  }
  // Authenticate Google BEFORE reserving any user/stage. OAuth failure consumes none.
  const accessToken = await getAccessToken();
  const deadline = now() + 45000;
  const counts = { reserved: 0, accepted: 0, rejected: 0, invalid_token: 0, unknown: 0, skipped: 0 };
  for (let i = 0; i < Math.min(25, preview.batch_size); i++) {
    if (now() >= deadline) break;
    const claim = await rpc('claim');
    if (!claim.id) break;
    counts.reserved++;
    const item = await rpc('authorize', claim.id);
    if (!item.token) { counts.skipped++; continue; }
    const result = await send(accessToken, item);
    // On failure to persist: stop. Durable dispatching reservation prevents replay.
    const finished = await rpc('finish', claim.id, result);
    if (finished?.recorded !== true) throw new Error('RESULT_NOT_RECORDED');
    counts[result.status]++;
    if (result.status === 'unknown' || [401, 403, 429].includes(result.http_status)
      || result.http_status >= 500 || result.code === 'INVALID_ARGUMENT') break;
  }
  return { mode: 'processed', counts };
}
