-- NOT APPLIED. Read-only authenticated comparison; no game/payment writers.
BEGIN;
DO $$ BEGIN
  IF current_user<>'postgres' OR NOT EXISTS(SELECT 1 FROM pg_catalog.pg_roles
    WHERE rolname=current_user AND rolbypassrls)
  THEN RAISE EXCEPTION 'STAT_COMPARISON_REQUIRES_POSTGRES'; END IF;
END $$;
CREATE FUNCTION public.okeyix_compare_player(p_opponent_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $body$
DECLARE viewer uuid:=auth.uid();
BEGIN
  IF viewer IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE='42501'; END IF;
  IF p_opponent_id IS NULL OR p_opponent_id=viewer THEN
    RAISE EXCEPTION 'OTHER_PLAYER_REQUIRED' USING ERRCODE='22023'; END IF;
  IF (SELECT count(*) FROM public.users WHERE id IN (viewer,p_opponent_id))<>2 THEN
    RAISE EXCEPTION 'PLAYER_NOT_FOUND' USING ERRCODE='P0002'; END IF;
  RETURN (
    WITH results AS (
      SELECT r.source_start_key AS source_key,p.user_id,p.outcome,
        r.is_okey_finish AS is_okey,r.is_double_finish AS is_double
      FROM public.okeyix_stat_players p JOIN public.okeyix_stat_rounds r
        ON r.id=p.round_id AND r.status='completed'
      WHERE p.user_id IN (viewer,p_opponent_id)
      UNION ALL
      -- One snapshot with permanent results: projection and processed marker
      -- commit together. Unique source/participant keys prevent duplicate hands.
      SELECT e.table_id::text||':'||e.round_no::text||':'||e.seed,p.user_id,
        CASE WHEN e.winner_user_id=p.user_id THEN 'win' ELSE 'loss' END,e.is_okey,e.is_double
      FROM okeyix_stat_private.event_players p JOIN okeyix_stat_private.events e ON e.id=p.event_id
      WHERE p.user_id IN (viewer,p_opponent_id) AND e.kind='complete' AND e.processed_at IS NULL
        AND NOT EXISTS(SELECT 1 FROM public.okeyix_stat_rounds r
          WHERE r.source_start_key=e.table_id::text||':'||e.round_no::text||':'||e.seed
            AND r.status IN ('completed','aborted','draw'))
    ), totals AS (
      SELECT user_id,
        count(*) FILTER(WHERE outcome='win') AS wins,
        count(*) FILTER(WHERE outcome='loss') AS losses,
        count(*) FILTER(WHERE outcome='win' AND NOT is_okey AND NOT is_double) AS normal_wins,
        count(*) FILTER(WHERE outcome='win' AND is_okey) AS okey_wins,
        count(*) FILTER(WHERE outcome='win' AND is_double) AS double_wins,
        count(*) FILTER(WHERE outcome='win' AND is_okey AND is_double) AS okey_double_wins
      FROM results GROUP BY user_id
    ), league_ranges AS (
      SELECT to_jsonb(l)->>'name' AS name,
        (to_jsonb(l)->>'min_rating')::integer AS minimum,
        (to_jsonb(l)->>'max_rating')::integer AS explicit_max,
        lead((to_jsonb(l)->>'min_rating')::integer) OVER(
          ORDER BY (to_jsonb(l)->>'min_rating')::integer,l.id::text) AS next_min
      FROM public.leagues l
    ), players AS (
      SELECT u.id,COALESCE(NULLIF(u.username,''),'Oyuncu') AS username,u.avatar_url,
        (SELECT name FROM league_ranges l WHERE pr.rating>=l.minimum
          AND (CASE WHEN l.explicit_max>0 THEN pr.rating<=l.explicit_max
            ELSE l.next_min IS NULL OR pr.rating<l.next_min END)
          ORDER BY l.minimum DESC LIMIT 1) AS league,
        COALESCE(t.wins,0) AS wins,COALESCE(t.losses,0) AS losses,
        COALESCE(t.normal_wins,0) AS normal_wins,COALESCE(t.okey_wins,0) AS okey_wins,
        COALESCE(t.double_wins,0) AS double_wins,COALESCE(t.okey_double_wins,0) AS okey_double_wins
      FROM public.users u LEFT JOIN public.profiles pr ON pr.id=u.id
      LEFT JOIN totals t ON t.user_id=u.id WHERE u.id IN (viewer,p_opponent_id)
    ), head_to_head AS (
      SELECT count(*) FILTER(WHERE a.outcome='win' AND b.outcome='loss') AS left_wins,
        count(*) FILTER(WHERE b.outcome='win' AND a.outcome='loss') AS right_wins
      FROM results a JOIN results b ON b.source_key=a.source_key
      WHERE a.user_id=viewer AND b.user_id=p_opponent_id
    )
    SELECT jsonb_build_object(
      'left_player',(SELECT to_jsonb(p) FROM players p WHERE id=viewer),
      'right_player',(SELECT to_jsonb(p) FROM players p WHERE id=p_opponent_id),
      'left_wins',h.left_wins,'right_wins',h.right_wins,
      'as_of',statement_timestamp()
    ) FROM head_to_head h
  );
END $body$;
ALTER FUNCTION public.okeyix_compare_player(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.okeyix_compare_player(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.okeyix_compare_player(uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
