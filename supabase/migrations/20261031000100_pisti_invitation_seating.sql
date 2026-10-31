-- Okey-style invitation seating; keep settlement, game rules and JWT checks.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $$
DECLARE definition text;
BEGIN
 definition:=pg_get_functiondef('public.okeyix_pisti_command(uuid,uuid,text,jsonb)'::regprocedure);
 IF position('WHERE b.is_bot AND p.coins>=r.entry_coin' IN definition)=0
 OR position('IF NOT EXISTS(SELECT 1 FROM public.friends WHERE status=''accepted'' AND' IN definition)=0
 THEN RAISE EXCEPTION 'PISTI_COMMAND_DEFINITION_MISMATCH'; END IF;
 definition:=replace(definition,'WHERE b.is_bot AND p.coins>=r.entry_coin',
  'WHERE b.is_bot AND (NOT (p_args ? ''bot_id'') OR b.id=(p_args->>''bot_id'')::uuid) AND p.coins>=r.entry_coin');
 definition:=replace(definition,'IF NOT EXISTS(SELECT 1 FROM public.friends WHERE status=''accepted'' AND',
  'IF r.private AND NOT EXISTS(SELECT 1 FROM public.friends WHERE status=''accepted'' AND');
 EXECUTE definition;
END $$;

CREATE FUNCTION public.okeyix_pisti_invitable_players(p_room uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE r public.okeyix_pisti_rooms%ROWTYPE; uid uuid:=auth.uid(); result jsonb;
BEGIN
 SELECT * INTO r FROM public.okeyix_pisti_rooms WHERE id=p_room;
 IF uid IS NULL OR NOT FOUND OR r.status<>'waiting' OR jsonb_array_length(r.seats)<>1
   OR okeyix_pisti_private.member(r.seats,uid) IS NULL THEN RAISE EXCEPTION 'NOT_A_MEMBER'; END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(candidate)),'[]'::jsonb) INTO result FROM (
  SELECT u.id,u.username,u.avatar_url,u.is_bot,
   (u.is_bot OR coalesce(p.is_online,false)) AS is_online,p.last_seen_at
  FROM public.users u JOIN public.profiles p ON p.id=u.id
  WHERE u.id<>uid AND p.coins>=r.entry_coin
   AND NOT (coalesce(u.is_banned,false) AND (u.ban_until IS NULL OR u.ban_until>clock_timestamp()))
   AND (u.is_bot OR coalesce(p.allow_game_invites,true))
   AND (NOT u.is_bot OR NOT EXISTS(SELECT 1 FROM auth.users a WHERE a.id=u.id))
   AND (NOT r.private OR u.is_bot OR EXISTS(SELECT 1 FROM public.friends f WHERE f.status='accepted'
    AND ((f.user_id=uid AND f.friend_id=u.id) OR (f.friend_id=uid AND f.user_id=u.id))))
   AND NOT EXISTS(SELECT 1 FROM public.table_players tp JOIN public.tables t ON t.id=tp.table_id
    WHERE tp.user_id=u.id AND t.status IN ('waiting','start','starting','playing'))
   AND NOT EXISTS(SELECT 1 FROM public.okeyix_pisti_rooms x WHERE x.status IN ('waiting','playing')
    AND okeyix_pisti_private.member(x.seats,u.id) IS NOT NULL)
  ORDER BY (NOT u.is_bot AND coalesce(p.is_online,false)) DESC,u.is_bot DESC,u.username,u.id LIMIT 200
 ) candidate;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.okeyix_pisti_invitable_players(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.okeyix_pisti_invitable_players(uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
