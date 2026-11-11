import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type InvitePayload = {
  game_type?: string;
  invite_id?: string;
  table_id?: string;
  from_user?: string;
  to_user?: string;
};

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...CORS_HEADERS,
      "Content-Type": "application/json",
    },
  });
}

function uniq(values: string[]) {
  return [...new Set(values.filter((v) => v.trim().length > 0))];
}

function b64url(input: Uint8Array | string) {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let str = "";
  for (const b of bytes) str += String.fromCharCode(b);
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

async function signJwtRS256(payload: Record<string, unknown>, privateKeyPem: string) {
  const header = { alg: "RS256", typ: "JWT" };
  const encHeader = b64url(JSON.stringify(header));
  const encPayload = b64url(JSON.stringify(payload));
  const data = `${encHeader}.${encPayload}`;

  const cleanPem = privateKeyPem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const keyBytes = Uint8Array.from(atob(cleanPem), (c) => c.charCodeAt(0));

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    keyBytes.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const sig = await crypto.subtle.sign(
    { name: "RSASSA-PKCS1-v1_5" },
    cryptoKey,
    new TextEncoder().encode(data),
  );

  return `${data}.${b64url(new Uint8Array(sig))}`;
}

async function getGoogleAccessToken(serviceAccount: {
  client_email: string;
  private_key: string;
}) {
  const now = Math.floor(Date.now() / 1000);
  const jwt = await signJwtRS256(
    {
      iss: serviceAccount.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    },
    serviceAccount.private_key,
  );

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  const txt = await res.text();
  if (!res.ok) throw new Error(`GOOGLE_TOKEN_ERROR: ${txt}`);
  const data = JSON.parse(txt);
  return data.access_token as string;
}

async function getPushTokens(
  supabase: ReturnType<typeof createClient>,
  toUserId: string,
) {
  try {
    const { data } = await supabase
      .from("user_devices")
      .select("push_token")
      .eq("user_id", toUserId)
      .not("push_token", "is", null)
      .limit(10);

    const tokens = (data ?? [])
      .map((r: Record<string, unknown>) => String(r.push_token ?? ""))
      .filter((t) => t.trim().length > 0);

    if (tokens.length > 0) return uniq(tokens);
  } catch (_) {}

  try {
    const { data } = await supabase
      .from("devices")
      .select("push_token")
      .eq("user_id", toUserId)
      .not("push_token", "is", null)
      .limit(10);

    const tokens = (data ?? [])
      .map((r: Record<string, unknown>) => String(r.push_token ?? ""))
      .filter((t) => t.trim().length > 0);

    if (tokens.length > 0) return uniq(tokens);
  } catch (_) {}

  return [] as string[];
}

async function sendViaFcmV1(
  accessToken: string,
  projectId: string,
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
) {
  const endpoint = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

  const res = await fetch(endpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({
      message: {
        token,
        notification: { title, body },
        data,
        android: {
          priority: "high",
          notification: {
            sound: "default",
            channel_id: "invite_channel",
            default_sound: true,
          },
        },
        apns: {
          headers: {
            "apns-priority": "10",
            "apns-push-type": "alert",
          },
          payload: {
            aps: {
              alert: { title, body },
              sound: "default",
              badge: 1,
            },
          },
        },
      },
    }),
  });

  const raw = await res.text();
  return { ok: res.ok, status: res.status, raw };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const serviceAccountJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
    const projectIdFromSecret = Deno.env.get("FIREBASE_PROJECT_ID");

    if (!url || !serviceRole) {
      return json(500, { ok: false, error: "SUPABASE_ENV_MISSING" });
    }
    if (!serviceAccountJson) {
      return json(500, { ok: false, error: "FIREBASE_SERVICE_ACCOUNT_JSON_MISSING" });
    }

    const payload = (await req.json()) as InvitePayload;
    const tableId = payload.table_id?.trim();
    const fromUserId = payload.from_user?.trim();
    const toUserId = payload.to_user?.trim();

    if (!tableId || !fromUserId || !toUserId) {
      return json(400, { ok: false, error: "INVALID_PAYLOAD" });
    }

    const serviceAccount = JSON.parse(serviceAccountJson) as {
      client_email: string;
      private_key: string;
      project_id?: string;
    };

    const projectId = projectIdFromSecret || serviceAccount.project_id;
    if (!projectId) {
      return json(500, { ok: false, error: "FIREBASE_PROJECT_ID_MISSING" });
    }

    const supabase = createClient(url, serviceRole, {
      auth: { persistSession: false },
    });

    if (payload.game_type === 'pisti') {
      const jwt = req.headers.get('authorization')?.replace(/^Bearer /i, '');
      const { data: identity, error } = await supabase.auth.getUser(jwt ?? '');
      if (error || identity.user?.id !== fromUserId) return json(401, { error: 'AUTH_REQUIRED' });
      const { data: invite } = await supabase.from('okeyix_pisti_invites')
        .select('id,status,expires_at').eq('id', payload.invite_id ?? '')
        .eq('table_id', tableId).eq('from_user', fromUserId).eq('to_user', toUserId).maybeSingle();
      if (!invite || invite.status !== 'pending' || Date.parse(invite.expires_at) <= Date.now()) {
        return json(409, { error: 'INVITE_EXPIRED' });
      }
    }

    let inviterName = "Bir oyuncu";
    const { data: inviterProfile } = await supabase
      .from("profiles")
      .select("username")
      .eq("id", fromUserId)
      .maybeSingle();

    if (inviterProfile?.username) inviterName = String(inviterProfile.username);

    const { data: targetProfile } = await supabase
      .from("profiles")
      .select("allow_game_invites")
      .eq("id", toUserId)
      .maybeSingle();

    if (targetProfile?.allow_game_invites === false) {
      return json(200, {
        ok: true,
        sent: 0,
        reason: "INVITES_DISABLED",
      });
    }

    const tokens = await getPushTokens(supabase, toUserId);
    if (tokens.length === 0) {
      return json(200, { ok: true, sent: 0, reason: "NO_PUSH_TOKEN" });
    }

    const accessToken = await getGoogleAccessToken(serviceAccount);

    const title = payload.game_type === 'pisti' ? 'Okeyix Pişti Daveti' : "OkeyIX Masa Daveti";
    const body = `${inviterName} seni masaya davet etti`;
    const data: Record<string, string> = payload.game_type === 'pisti' ? {
      type: 'pisti_invite', game_type: 'pisti', invite_id: payload.invite_id!,
      table_id: tableId, from_user: fromUserId, to_user: toUserId,
    } : {
      type: "table_invite",
      table_id: tableId,
      from_user: fromUserId,
      to_user: toUserId,
    };

    const results: Array<Record<string, unknown>> = [];
    if (payload.game_type === 'pisti') {
      const { data: claimed, error } = await supabase.rpc('okeyix_pisti_claim_push', { p_invite: payload.invite_id });
      if (error || !claimed) return json(200, { ok: true, sent: 0, reason: 'ALREADY_CLAIMED_OR_EXPIRED' });
    }
    for (const token of tokens) {
      const r = await sendViaFcmV1(accessToken, projectId, token, title, body, data);
      results.push({
        token_suffix: token.length > 8 ? token.slice(-8) : token,
        ...r,
      });
    }

    const successCount = results.filter((r) => r.ok === true).length;
    if (payload.game_type === 'pisti') {
      // Keep provider response bodies out of the public invitation record.
      await supabase.from('okeyix_pisti_invites').update({
        push_outcome: { sent: successCount, results: results.map(r => ({ ok: r.ok, status: r.status })) },
      }).eq('id', payload.invite_id!);
    }
    return json(200, {
      ok: true,
      sent: successCount,
      total: results.length,
      results,
    });
  } catch (e) {
    return json(500, { ok: false, error: String(e) });
  }
});
