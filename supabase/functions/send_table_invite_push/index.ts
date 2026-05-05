import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";

type InvitePayload = {
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

async function getPushTokens(
  supabase: ReturnType<typeof createClient>,
  toUserId: string,
) {
  // Primary expected table.
  try {
    const { data } = await supabase
      .from("user_devices")
      .select("push_token")
      .eq("user_id", toUserId)
      .not("push_token", "is", null)
      .order("updated_at", { ascending: false })
      .limit(10);
    const tokens = (data ?? [])
      .map((r: Record<string, unknown>) => String(r.push_token ?? ""))
      .filter((t) => t.length > 0);
    if (tokens.length > 0) return uniq(tokens);
  } catch (_) {
    // fallback below
  }

  // Secondary fallback table name.
  try {
    const { data } = await supabase
      .from("devices")
      .select("push_token")
      .eq("user_id", toUserId)
      .not("push_token", "is", null)
      .order("updated_at", { ascending: false })
      .limit(10);
    const tokens = (data ?? [])
      .map((r: Record<string, unknown>) => String(r.push_token ?? ""))
      .filter((t) => t.length > 0);
    if (tokens.length > 0) return uniq(tokens);
  } catch (_) {
    // no-op
  }

  return [] as string[];
}

async function sendViaFcmLegacy(
  fcmServerKey: string,
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
) {
  const res = await fetch("https://fcm.googleapis.com/fcm/send", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `key=${fcmServerKey}`,
    },
    body: JSON.stringify({
      to: token,
      priority: "high",
      notification: {
        title,
        body,
      },
      data,
    }),
  });

  const raw = await res.text();
  return {
    ok: res.ok,
    status: res.status,
    raw,
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const fcmServerKey = Deno.env.get("FCM_SERVER_KEY");

    if (!url || !serviceRole) {
      return json(500, { ok: false, error: "SUPABASE_ENV_MISSING" });
    }
    if (!fcmServerKey) {
      return json(500, { ok: false, error: "FCM_SERVER_KEY_MISSING" });
    }

    const payload = (await req.json()) as InvitePayload;
    const tableId = payload.table_id?.trim();
    const fromUserId = payload.from_user?.trim();
    const toUserId = payload.to_user?.trim();

    if (!tableId || !fromUserId || !toUserId) {
      return json(400, { ok: false, error: "INVALID_PAYLOAD" });
    }

    const supabase = createClient(url, serviceRole, {
      auth: { persistSession: false },
    });

    let inviterName = "Bir oyuncu";
    const { data: inviterProfile } = await supabase
      .from("profiles")
      .select("username")
      .eq("id", fromUserId)
      .maybeSingle();
    if (inviterProfile?.username) {
      inviterName = String(inviterProfile.username);
    }

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

    const title = "OkeyIX Masa Daveti";
    const body = `${inviterName} seni masaya davet etti`;
    const data = {
      type: "table_invite",
      table_id: tableId,
      from_user: fromUserId,
      to_user: toUserId,
    };

    const results = [];
    for (const token of tokens) {
      const sendResult = await sendViaFcmLegacy(
        fcmServerKey,
        token,
        title,
        body,
        data,
      );
      results.push({
        token_suffix: token.length > 8 ? token.slice(-8) : token,
        ...sendResult,
      });
    }

    const successCount = results.filter((r) => r.ok).length;
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
