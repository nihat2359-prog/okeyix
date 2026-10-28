-- READ ONLY. Replace NULL below with YOUR account UUID: '...'::uuid.
-- Default NULL returns no devices. Never paste a raw push_token into chat.
WITH target AS (SELECT NULL::uuid AS user_id)
SELECT p.id AS user_id,p.username,d.id AS device_row_id,d.platform,d.device_model,
  d.app_version,d.last_seen AS device_last_seen,
  p.allow_game_invites,
  nullif(btrim(d.push_token),'') IS NOT NULL AS has_token,
  left(encode(sha256(convert_to(btrim(d.push_token),'UTF8')),'hex'),12) AS token_fingerprint,
  'unknown'::text AS recorded_platform_permission
FROM target x JOIN public.profiles p ON p.id=x.user_id
JOIN public.user_devices d ON d.user_id=p.id
ORDER BY d.last_seen DESC NULLS LAST,d.id;
