-- Give online/bot and offline invite tabs independent 80-row budgets.
-- Preserve both tabs when either group contains more than 80 eligible players.
-- Keeps the existing RPC signature, invoker security, ownership and grants.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $$ BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'POSTGRES_REQUIRED'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_proc
    WHERE oid=to_regprocedure('public.get_invitable_players(uuid,uuid,text,integer)')
      AND proowner='postgres'::regrole AND NOT prosecdef
      AND md5(btrim(regexp_replace(prosrc,'\s+',' ','g')))='f74987dee1fe88b9bc575fa6cf5b175c') THEN
    RAISE EXCEPTION 'INVITABLE_PLAYERS_SOURCE_CHANGED';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.get_invitable_players(
  p_table_id uuid,p_user_id uuid,p_league_id text,p_entry_coin integer
) RETURNS TABLE(id uuid,username text,rating integer,coins integer,
  avatar_url text,is_bot boolean,is_in_game boolean)
LANGUAGE sql STABLE AS $function$
WITH league_data AS (
  SELECT l.id,l.min_rating FROM public.leagues l WHERE l.id=p_league_id
), excluded AS (
  SELECT tp.user_id FROM public.table_players tp WHERE tp.table_id=p_table_id
  UNION
  SELECT ti.to_user FROM public.table_invites ti
    WHERE ti.table_id=p_table_id AND ti.status='pending'
  UNION SELECT p_user_id
), candidates AS (
  SELECT p.id,p.username,p.rating,p.coins,coalesce(u.avatar_url,p.avatar)::text AS avatar_url,
    coalesce(u.is_bot,false) AS is_bot,p.is_online,
    EXISTS(SELECT 1 FROM public.table_players tp JOIN public.tables t ON t.id=tp.table_id
      WHERE tp.user_id=p.id AND t.status IN ('waiting','start','starting','playing')) AS is_in_game
  FROM public.profiles p JOIN public.users u ON u.id=p.id CROSS JOIN league_data l
  WHERE NOT EXISTS(SELECT 1 FROM excluded e WHERE e.user_id=p.id)
    AND p.rating>=l.min_rating AND p.coins>=p_entry_coin
    AND (coalesce(u.is_bot,false) OR p.allow_game_invites IS DISTINCT FROM false)
    AND (NOT coalesce(u.is_bot,false) OR l.id NOT IN ('gold','elite'))
    -- Match Flutter's busy-player filter, including bots in waiting seats.
    AND NOT EXISTS(SELECT 1 FROM public.table_players tp JOIN public.tables t ON t.id=tp.table_id
      WHERE tp.user_id=p.id AND tp.table_id<>p_table_id
        AND (t.status IN ('start','starting','playing')
          OR (coalesce(u.is_bot,false) AND t.status='waiting')))
), ranked AS (
  SELECT c.*,row_number() OVER (
    PARTITION BY CASE WHEN c.is_bot OR c.is_online THEN 0 ELSE 1 END
    ORDER BY CASE WHEN NOT c.is_bot AND c.is_online THEN 0 WHEN c.is_bot THEN 1 ELSE 2 END,
      c.rating DESC,c.id
  ) AS invite_rank
  FROM candidates c
)
SELECT c.id,c.username,c.rating,c.coins,c.avatar_url,c.is_bot,c.is_in_game
FROM ranked c
WHERE c.invite_rank<=80
ORDER BY CASE WHEN NOT c.is_bot AND c.is_online THEN 0 WHEN c.is_bot THEN 1 ELSE 2 END,
  c.rating DESC,c.id;
$function$;
NOTIFY pgrst,'reload schema';
COMMIT;
