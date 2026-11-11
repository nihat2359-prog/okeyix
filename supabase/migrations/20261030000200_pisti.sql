-- NOT APPLIED. Additive Pişti sessions; no Okey tables, triggers or rating changes.
BEGIN;
SET LOCAL lock_timeout='5s';
CREATE SCHEMA okeyix_pisti_private;
REVOKE ALL ON SCHEMA okeyix_pisti_private FROM PUBLIC,anon,authenticated;
CREATE TABLE public.okeyix_pisti_settings (
 id boolean PRIMARY KEY DEFAULT true CHECK(id), enabled boolean NOT NULL DEFAULT false,
 stakes integer[] NOT NULL DEFAULT ARRAY[1000,5000,10000], target integer NOT NULL DEFAULT 101 CHECK(target BETWEEN 1 AND 1001),
 turn_seconds integer NOT NULL DEFAULT 20 CHECK(turn_seconds BETWEEN 10 AND 60),
 disconnect_seconds integer NOT NULL DEFAULT 90 CHECK(disconnect_seconds BETWEEN 30 AND 300),
 timeout_limit integer NOT NULL DEFAULT 3 CHECK(timeout_limit BETWEEN 1 AND 10)
);
INSERT INTO public.okeyix_pisti_settings DEFAULT VALUES;
CREATE TABLE public.okeyix_pisti_rooms (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), game_type text NOT NULL DEFAULT 'pisti' CHECK(game_type='pisti'),
 owner_id uuid NOT NULL REFERENCES public.users(id), private boolean NOT NULL DEFAULT false,
 spectators_enabled boolean NOT NULL DEFAULT true, chat_enabled boolean NOT NULL DEFAULT true,
 entry_coin integer NOT NULL CHECK(entry_coin>0 AND entry_coin<=100000000),
 status text NOT NULL DEFAULT 'waiting' CHECK(status IN ('waiting','playing','finished','closed')),
 seats jsonb NOT NULL DEFAULT '[]', version bigint NOT NULL DEFAULT 0,
 match_id uuid, summary jsonb, deadline timestamptz,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(), updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE okeyix_pisti_private.sessions (
 room_id uuid PRIMARY KEY REFERENCES public.okeyix_pisti_rooms(id), state jsonb,
 settings jsonb NOT NULL, paid boolean NOT NULL DEFAULT false,
 last_seen jsonb NOT NULL DEFAULT '{}', timeouts integer[] NOT NULL DEFAULT ARRAY[0,0],
 rematch uuid[] NOT NULL DEFAULT '{}'
);
CREATE TABLE okeyix_pisti_private.requests (
 user_id uuid NOT NULL, request_id uuid NOT NULL, action text NOT NULL, args jsonb NOT NULL,
 result jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(user_id,request_id)
);
CREATE TABLE public.okeyix_pisti_careers (
 user_id uuid PRIMARY KEY REFERENCES public.users(id), rating integer NOT NULL DEFAULT 1000,
 wins integer NOT NULL DEFAULT 0, losses integer NOT NULL DEFAULT 0,
 matches integer NOT NULL DEFAULT 0, pistis integer NOT NULL DEFAULT 0
);
CREATE TABLE public.okeyix_pisti_results (
 match_id uuid PRIMARY KEY, room_id uuid NOT NULL, game_type text NOT NULL DEFAULT 'pisti',
 players jsonb NOT NULL, winner integer, reason text NOT NULL, scores jsonb NOT NULL,
 rounds jsonb NOT NULL, pistis jsonb NOT NULL, entry_coin integer NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE public.okeyix_pisti_invites (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), table_id uuid NOT NULL REFERENCES public.okeyix_pisti_rooms(id),
 game_type text NOT NULL DEFAULT 'pisti', from_user uuid NOT NULL REFERENCES public.users(id),
 to_user uuid NOT NULL REFERENCES public.users(id), status text NOT NULL DEFAULT 'pending'
 CHECK(status IN ('pending','accepted','rejected')), created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 expires_at timestamptz NOT NULL DEFAULT clock_timestamp()+interval '60 seconds'
);
CREATE TABLE public.okeyix_pisti_messages (
 id uuid PRIMARY KEY, table_id uuid NOT NULL REFERENCES public.okeyix_pisti_rooms(id),
 user_id uuid NOT NULL REFERENCES public.users(id), username text NOT NULL,
 kind text NOT NULL CHECK(kind IN ('text','voice','gift')), body text NOT NULL CHECK(length(body)<=1000),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX pisti_messages_room ON public.okeyix_pisti_messages(table_id,created_at);
CREATE INDEX pisti_rooms_active ON public.okeyix_pisti_rooms(status,deadline);
CREATE INDEX pisti_invites_recipient ON public.okeyix_pisti_invites(to_user,status,expires_at);
CREATE TABLE okeyix_pisti_private.ledger (
 match_id uuid NOT NULL, user_id uuid NOT NULL, kind text NOT NULL,
 wallet_id uuid NOT NULL UNIQUE REFERENCES public.wallet_transactions(id),
 PRIMARY KEY(match_id,user_id,kind)
);
CREATE TABLE public.okeyix_pisti_admin_audit (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, admin_id text NOT NULL,
 action text NOT NULL, room_id uuid, details jsonb NOT NULL DEFAULT '{}', created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE FUNCTION okeyix_pisti_private.member(seats jsonb,u uuid) RETURNS integer
LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT (ordinality-1)::integer FROM jsonb_array_elements(seats) WITH ORDINALITY
 WHERE value->>'id'=u::text LIMIT 1
$$;
CREATE FUNCTION okeyix_pisti_private.pass_until(p_note text,p_created timestamptz) RETURNS timestamptz
LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $$
BEGIN
 IF p_note LIKE 'spectator_pass_until:%' THEN RETURN substring(p_note FROM 22)::timestamptz; END IF;
 RETURN p_created+interval '24 hours';
EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN RETURN p_created+interval '24 hours';
END $$;
CREATE FUNCTION okeyix_pisti_private.spectator_allowed(p_seats jsonb,p_user uuid) RETURNS boolean
LANGUAGE sql STABLE SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM public.friends f JOIN jsonb_array_elements(p_seats) p ON
  ((f.user_id=p_user AND f.friend_id=(p->>'id')::uuid) OR (f.friend_id=p_user AND f.user_id=(p->>'id')::uuid)) WHERE f.status='accepted')
 OR EXISTS(SELECT 1 FROM public.wallet_transactions w WHERE w.user_id=p_user AND w.reason='spectator_pass_purchase'
  AND w.amount<0 AND okeyix_pisti_private.pass_until(w.note,w.created_at)>clock_timestamp())
$$;
CREATE FUNCTION public.okeyix_pisti_view_allowed(p_room uuid,p_user uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT p_user IS NOT NULL AND EXISTS(SELECT 1 FROM public.okeyix_pisti_rooms r WHERE r.id=p_room AND
  (okeyix_pisti_private.member(r.seats,p_user) IS NOT NULL OR
   (NOT r.private AND r.spectators_enabled AND okeyix_pisti_private.spectator_allowed(r.seats,p_user))))
$$;
CREATE FUNCTION public.okeyix_pisti_can_view(p_room uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT auth.uid() IS NOT NULL AND EXISTS(SELECT 1 FROM public.okeyix_pisti_rooms r
 WHERE r.id=p_room AND (okeyix_pisti_private.member(r.seats,auth.uid()) IS NOT NULL
 OR (NOT r.private AND r.spectators_enabled AND okeyix_pisti_private.spectator_allowed(r.seats,auth.uid()))))
$$;
ALTER TABLE public.okeyix_pisti_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.okeyix_pisti_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.okeyix_pisti_careers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.okeyix_pisti_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.okeyix_pisti_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.okeyix_pisti_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.okeyix_pisti_admin_audit ENABLE ROW LEVEL SECURITY;
CREATE POLICY pisti_settings_read ON public.okeyix_pisti_settings FOR SELECT TO authenticated USING(true);
CREATE POLICY pisti_rooms_read ON public.okeyix_pisti_rooms FOR SELECT TO authenticated
 USING(NOT private OR okeyix_pisti_private.member(seats,auth.uid()) IS NOT NULL);
CREATE POLICY pisti_careers_read ON public.okeyix_pisti_careers FOR SELECT TO authenticated USING(true);
CREATE POLICY pisti_results_read ON public.okeyix_pisti_results FOR SELECT TO authenticated USING(true);
CREATE POLICY pisti_invites_read ON public.okeyix_pisti_invites FOR SELECT TO authenticated USING(auth.uid() IN(from_user,to_user));
CREATE POLICY pisti_messages_read ON public.okeyix_pisti_messages FOR SELECT TO authenticated USING(public.okeyix_pisti_can_view(table_id));
REVOKE ALL ON public.okeyix_pisti_settings,public.okeyix_pisti_rooms,public.okeyix_pisti_careers,
 public.okeyix_pisti_results,public.okeyix_pisti_invites,public.okeyix_pisti_messages,public.okeyix_pisti_admin_audit
 FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.okeyix_pisti_settings,public.okeyix_pisti_rooms,public.okeyix_pisti_careers,
 public.okeyix_pisti_results,public.okeyix_pisti_invites,public.okeyix_pisti_messages TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA okeyix_pisti_private TO service_role;
GRANT USAGE ON SCHEMA okeyix_pisti_private TO service_role;
REVOKE ALL ON ALL TABLES IN SCHEMA okeyix_pisti_private FROM PUBLIC,anon,authenticated;
GRANT ALL ON public.okeyix_pisti_settings,public.okeyix_pisti_rooms,public.okeyix_pisti_careers,
 public.okeyix_pisti_results,public.okeyix_pisti_invites,public.okeyix_pisti_messages,public.okeyix_pisti_admin_audit TO service_role;
GRANT USAGE ON SEQUENCE public.okeyix_pisti_admin_audit_id_seq TO service_role;

CREATE FUNCTION okeyix_pisti_private.wallet(m uuid,u uuid,k text,amount integer) RETURNS void
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE w uuid; balance integer;
BEGIN
 IF EXISTS(SELECT 1 FROM okeyix_pisti_private.ledger WHERE match_id=m AND user_id=u AND kind=k) THEN RETURN; END IF;
 SELECT coins INTO balance FROM public.profiles WHERE id=u FOR UPDATE;
 IF balance IS NULL OR balance+amount<0 THEN RAISE EXCEPTION 'NOT_ENOUGH_COINS'; END IF;
 UPDATE public.profiles SET coins=coins+amount WHERE id=u;
 INSERT INTO public.wallet_transactions(user_id,amount,reason,type,store,note)
 VALUES(u,amount,'pisti_'||k,CASE WHEN amount<0 THEN 'debit' ELSE 'credit' END,'system',m::text) RETURNING id INTO w;
 INSERT INTO okeyix_pisti_private.ledger VALUES(m,u,k,w);
END $$;

CREATE FUNCTION okeyix_pisti_private.settle(r public.okeyix_pisti_rooms,s jsonb) RETURNS void
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE i integer; u uuid; win integer:=(s->>'winner')::integer; why text:=s->>'reason'; n integer;
BEGIN
 INSERT INTO public.okeyix_pisti_results(match_id,room_id,players,winner,reason,scores,rounds,pistis,entry_coin)
 VALUES(r.match_id,r.id,r.seats,win,why,s->'total',s->'rounds',s->'pistiTotal',r.entry_coin) ON CONFLICT DO NOTHING;
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n=0 THEN RETURN; END IF;
 -- Stable profile lock order agrees with admission; settlement is one transaction.
 PERFORM id FROM public.profiles WHERE id IN (SELECT (value->>'id')::uuid FROM jsonb_array_elements(r.seats)) ORDER BY id FOR UPDATE;
 FOR i IN 0..1 LOOP
  u:=(r.seats->i->>'id')::uuid;
  IF why='admin_cancel' THEN PERFORM okeyix_pisti_private.wallet(r.match_id,u,'refund',r.entry_coin);
  ELSIF i=win THEN PERFORM okeyix_pisti_private.wallet(r.match_id,u,'prize',r.entry_coin*2); END IF;
  IF why<>'admin_cancel' THEN
   INSERT INTO public.okeyix_pisti_careers(user_id,rating,wins,losses,matches,pistis)
    VALUES(u,1000+CASE WHEN i=win THEN 16 ELSE -16 END,CASE WHEN i=win THEN 1 ELSE 0 END,
     CASE WHEN i=win THEN 0 ELSE 1 END,1,coalesce((s->'pistiTotal'->>i)::integer,0))
   ON CONFLICT(user_id) DO UPDATE SET rating=greatest(0,public.okeyix_pisti_careers.rating+CASE WHEN i=win THEN 16 ELSE -16 END),
    wins=public.okeyix_pisti_careers.wins+CASE WHEN i=win THEN 1 ELSE 0 END,
    losses=public.okeyix_pisti_careers.losses+CASE WHEN i=win THEN 0 ELSE 1 END,
    matches=public.okeyix_pisti_careers.matches+1,pistis=public.okeyix_pisti_careers.pistis+coalesce((s->'pistiTotal'->>i)::integer,0);
  END IF;
 END LOOP;
END $$;

-- Service-only entry points. Edge verifies JWT with auth.getUser; clients cannot
-- impersonate p_user or submit state. Private state never enters Realtime.
CREATE FUNCTION public.okeyix_pisti_load(p_room uuid) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
 SELECT jsonb_build_object('room',to_jsonb(r),'session',to_jsonb(s),'now',clock_timestamp())
 FROM public.okeyix_pisti_rooms r JOIN okeyix_pisti_private.sessions s ON s.room_id=r.id WHERE r.id=p_room
$$;
CREATE FUNCTION public.okeyix_pisti_commit(p_room uuid,p_version bigint,p_state jsonb,
 p_user uuid,p_request uuid,p_card integer DEFAULT NULL,p_initial boolean DEFAULT false) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r public.okeyix_pisti_rooms%ROWTYPE; cfg jsonb; i integer; u uuid;
BEGIN
 SELECT * INTO r FROM public.okeyix_pisti_rooms WHERE id=p_room FOR UPDATE;
 IF r.version<>p_version OR r.status NOT IN ('waiting','playing') THEN RETURN false; END IF;
 SELECT settings INTO cfg FROM okeyix_pisti_private.sessions WHERE room_id=r.id;
 IF p_initial THEN
  IF r.status<>'waiting' OR jsonb_array_length(r.seats)<>2
    OR EXISTS(SELECT 1 FROM jsonb_array_elements(r.seats) WHERE NOT (value->>'ready')::boolean) THEN RETURN false; END IF;
  PERFORM id FROM public.profiles WHERE id IN(SELECT (value->>'id')::uuid FROM jsonb_array_elements(r.seats)) ORDER BY id FOR UPDATE;
  r.match_id:=gen_random_uuid();
  FOR i IN 0..1 LOOP
   u:=(r.seats->i->>'id')::uuid;
   PERFORM okeyix_pisti_private.wallet(r.match_id,u,'entry',-r.entry_coin);
  END LOOP;
  UPDATE okeyix_pisti_private.sessions SET paid=true, timeouts=ARRAY[0,0],
   rematch='{}',last_seen=jsonb_build_object(r.seats->0->>'id',clock_timestamp(),r.seats->1->>'id',clock_timestamp()) WHERE room_id=r.id;
 END IF;
 IF p_request IS NOT NULL THEN
  INSERT INTO okeyix_pisti_private.requests(user_id,request_id,action,args,result)
   VALUES(p_user,p_request,'play',jsonb_build_object('room_id',p_room,'card',p_card),'{}');
 END IF;
 UPDATE okeyix_pisti_private.sessions SET state=p_state WHERE room_id=r.id;
 UPDATE public.okeyix_pisti_rooms SET match_id=r.match_id,version=version+1,updated_at=clock_timestamp(),
  status=CASE WHEN p_state->>'status'='finished' THEN 'finished' ELSE 'playing' END,
  deadline=clock_timestamp()+make_interval(secs=>CASE WHEN (r.seats->((p_state->>'turn')::integer)->>'bot')::boolean THEN 2 ELSE (cfg->>'turn_seconds')::integer END),
  summary=jsonb_build_object('total',p_state->'total','reason',p_state->'reason','winner',p_state->'winner',
   'round',p_state->'round','deal',p_state->'deal','turn',p_state->'turn') WHERE id=r.id;
 IF p_state->>'status'='finished' THEN PERFORM okeyix_pisti_private.settle(r,p_state); END IF;
 RETURN true;
END $$;

CREATE FUNCTION public.okeyix_pisti_command(p_user uuid,p_request uuid,p_action text,p_args jsonb DEFAULT '{}') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r public.okeyix_pisti_rooms%ROWTYPE; cfg public.okeyix_pisti_settings%ROWTYPE;
 old okeyix_pisti_private.requests%ROWTYPE; urow record; bot record; bot_claimed boolean:=false; i integer; rid uuid; result jsonb; inv record; remaining_seats jsonb; pass_end timestamptz;
BEGIN
 IF p_user IS NULL OR p_request IS NULL OR NOT EXISTS(SELECT 1 FROM public.users WHERE id=p_user AND NOT is_bot)
 THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM public.users WHERE id=p_user AND is_banned
  AND (ban_until IS NULL OR ban_until>clock_timestamp())) THEN RAISE EXCEPTION 'PLAYER_BANNED'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pisti-user:'||p_user::text,0));
 SELECT * INTO old FROM okeyix_pisti_private.requests WHERE user_id=p_user AND request_id=p_request;
 IF FOUND THEN
  IF old.action<>p_action OR old.args<>p_args THEN RAISE EXCEPTION 'REQUEST_CONFLICT'; END IF;
  RETURN old.result;
 END IF;
 SELECT * INTO cfg FROM public.okeyix_pisti_settings WHERE id;
 IF NOT cfg.enabled AND p_action NOT IN ('heartbeat','leave','reject') THEN RAISE EXCEPTION 'PISTI_DISABLED'; END IF;
 IF p_action IN ('create','quick','join','accept') THEN
  IF EXISTS(SELECT 1 FROM public.table_players p JOIN public.tables t ON t.id=p.table_id
   WHERE p.user_id=p_user AND t.status IN ('waiting','start','starting','playing')) THEN RAISE EXCEPTION 'ALREADY_SEATED_OKEY'; END IF;
  SELECT * INTO r FROM public.okeyix_pisti_rooms WHERE status IN ('waiting','playing')
   AND okeyix_pisti_private.member(seats,p_user) IS NOT NULL ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
  IF FOUND THEN result:=jsonb_build_object('room_id',r.id); ELSE
   IF p_action='quick' THEN
    SELECT * INTO r FROM public.okeyix_pisti_rooms WHERE status='waiting' AND NOT private
     AND jsonb_array_length(seats)=1 AND entry_coin<=(SELECT coins FROM public.profiles WHERE id=p_user)
     ORDER BY entry_coin,created_at FOR UPDATE SKIP LOCKED LIMIT 1;
    IF FOUND THEN rid:=r.id; END IF;
   ELSIF p_action='accept' THEN
    SELECT * INTO inv FROM public.okeyix_pisti_invites WHERE id=(p_args->>'invite_id')::uuid FOR UPDATE;
    IF NOT FOUND OR inv.to_user<>p_user OR inv.status<>'pending' OR inv.expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'INVITE_EXPIRED'; END IF;
    rid:=inv.table_id;
   ELSIF p_action='join' THEN rid:=(p_args->>'room_id')::uuid;
   END IF;
   IF rid IS NOT NULL THEN
    SELECT * INTO r FROM public.okeyix_pisti_rooms WHERE id=rid FOR UPDATE;
    IF NOT FOUND OR r.status<>'waiting' OR jsonb_array_length(r.seats)<>1 THEN RAISE EXCEPTION 'TABLE_FULL'; END IF;
    IF r.private AND p_action<>'accept' THEN RAISE EXCEPTION 'INVITE_REQUIRED'; END IF;
   ELSE
    IF p_action NOT IN ('quick','create') THEN RAISE EXCEPTION 'TABLE_NOT_FOUND'; END IF;
    IF NOT coalesce((p_args->>'entry_coin')::integer,cfg.stakes[1])=ANY(cfg.stakes) THEN RAISE EXCEPTION 'INVALID_STAKES'; END IF;
    INSERT INTO public.okeyix_pisti_rooms(owner_id,private,entry_coin,spectators_enabled,chat_enabled)
     VALUES(p_user,coalesce((p_args->>'private')::boolean,false),coalesce((p_args->>'entry_coin')::integer,cfg.stakes[1]),
      coalesce((p_args->>'spectators_enabled')::boolean,true),coalesce((p_args->>'chat_enabled')::boolean,true)) RETURNING * INTO r;
    INSERT INTO okeyix_pisti_private.sessions(room_id,settings) VALUES(r.id,to_jsonb(cfg));
   END IF;
   IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=p_user AND coins>=r.entry_coin) THEN RAISE EXCEPTION 'NOT_ENOUGH_COINS'; END IF;
   SELECT username,avatar_url INTO urow FROM public.users WHERE id=p_user;
   UPDATE public.okeyix_pisti_rooms SET seats=seats||jsonb_build_array(jsonb_build_object('id',p_user,'name',coalesce(urow.username,'Oyuncu'),'avatar',urow.avatar_url,'bot',false,'ready',false)),
    version=version+1,updated_at=clock_timestamp() WHERE id=r.id;
   UPDATE okeyix_pisti_private.sessions SET last_seen=last_seen||jsonb_build_object(p_user::text,clock_timestamp()) WHERE room_id=r.id;
   IF p_action='accept' THEN UPDATE public.okeyix_pisti_invites SET status='accepted' WHERE id=inv.id; END IF;
   result:=jsonb_build_object('room_id',r.id);
  END IF;
 ELSE
  SELECT * INTO r FROM public.okeyix_pisti_rooms WHERE id=(p_args->>'room_id')::uuid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'TABLE_NOT_FOUND'; END IF;
  i:=okeyix_pisti_private.member(r.seats,p_user);
  IF p_action='buy_pass' THEN
   IF r.private OR NOT r.spectators_enabled THEN RAISE EXCEPTION 'VIEW_DENIED'; END IF;
   IF NOT okeyix_pisti_private.spectator_allowed(r.seats,p_user) THEN
    PERFORM id FROM public.profiles WHERE id=p_user AND coins>=10000 FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'NOT_ENOUGH_COINS'; END IF;
    pass_end:=clock_timestamp()+interval '24 hours';
    UPDATE public.profiles SET coins=coins-10000 WHERE id=p_user;
    INSERT INTO public.wallet_transactions(user_id,amount,reason,type,store,note)
     VALUES(p_user,-10000,'spectator_pass_purchase','debit','system','spectator_pass_until:'||pass_end::text);
   END IF;
  ELSIF p_action='reject' THEN
   UPDATE public.okeyix_pisti_invites SET status='rejected' WHERE id=(p_args->>'invite_id')::uuid AND to_user=p_user AND status='pending';
  ELSE
   IF i IS NULL THEN RAISE EXCEPTION 'NOT_A_MEMBER'; END IF;
   IF p_action='heartbeat' THEN
    UPDATE okeyix_pisti_private.sessions SET last_seen=last_seen||jsonb_build_object(p_user::text,clock_timestamp()) WHERE room_id=r.id;
   ELSIF p_action='ready' THEN
    IF r.status<>'waiting' THEN RAISE EXCEPTION 'TABLE_NOT_WAITING'; END IF;
    UPDATE public.okeyix_pisti_rooms SET seats=jsonb_set(seats,ARRAY[i::text,'ready'],to_jsonb(coalesce((p_args->>'ready')::boolean,true))),version=version+1,updated_at=clock_timestamp() WHERE id=r.id;
   ELSIF p_action='bot' THEN
    IF r.status<>'waiting' OR r.owner_id<>p_user OR jsonb_array_length(r.seats)<>1 THEN RAISE EXCEPTION 'TABLE_FULL'; END IF;
    FOR bot IN SELECT b.id,b.username,b.avatar_url FROM public.users b JOIN public.profiles p ON p.id=b.id
     WHERE b.is_bot AND p.coins>=r.entry_coin AND NOT EXISTS(SELECT 1 FROM auth.users a WHERE a.id=b.id)
     AND NOT EXISTS(SELECT 1 FROM public.table_players tp JOIN public.tables t ON t.id=tp.table_id WHERE tp.user_id=b.id AND t.status IN ('waiting','start','starting','playing'))
     AND NOT EXISTS(SELECT 1 FROM public.okeyix_pisti_rooms x WHERE x.status IN ('waiting','playing') AND okeyix_pisti_private.member(x.seats,b.id) IS NOT NULL)
     ORDER BY b.id LOOP
     IF pg_try_advisory_xact_lock(hashtextextended('quick-bot:'||bot.id::text,0))
      AND NOT EXISTS(SELECT 1 FROM public.okeyix_pisti_rooms x WHERE x.status IN ('waiting','playing') AND okeyix_pisti_private.member(x.seats,bot.id) IS NOT NULL)
      AND NOT EXISTS(SELECT 1 FROM public.table_players tp JOIN public.tables t ON t.id=tp.table_id WHERE tp.user_id=bot.id AND t.status IN ('waiting','start','starting','playing')) THEN bot_claimed:=true; EXIT; END IF;
    END LOOP;
    IF NOT bot_claimed THEN RAISE EXCEPTION 'NO_BOT_AVAILABLE'; END IF;
    UPDATE public.okeyix_pisti_rooms SET seats=seats||jsonb_build_array(jsonb_build_object('id',bot.id,'name',coalesce(bot.username,'Bot'),'avatar',bot.avatar_url,'bot',true,'ready',true)),version=version+1,updated_at=clock_timestamp() WHERE id=r.id;
   ELSIF p_action='leave' THEN
    IF r.status='playing' THEN RAISE EXCEPTION 'FORFEIT_REQUIRED'; END IF;
    remaining_seats:=r.seats-i;
    UPDATE public.okeyix_pisti_rooms SET seats=CASE WHEN r.status='finished' THEN r.seats ELSE remaining_seats END,status=CASE WHEN r.status='finished' OR jsonb_array_length(remaining_seats)=0 OR (remaining_seats->0->>'bot')::boolean THEN 'closed' ELSE 'waiting' END,
     owner_id=CASE WHEN r.status<>'finished' AND jsonb_array_length(remaining_seats)>0 THEN (remaining_seats->0->>'id')::uuid ELSE owner_id END,version=version+1,updated_at=clock_timestamp() WHERE id=r.id;
   ELSIF p_action='rematch' THEN
    IF r.status<>'finished' OR jsonb_array_length(r.seats)<>2 THEN RAISE EXCEPTION 'REMATCH_UNAVAILABLE'; END IF;
    UPDATE okeyix_pisti_private.sessions SET rematch=array_append(rematch,p_user) WHERE room_id=r.id AND NOT p_user=ANY(rematch);
    IF (SELECT count(*) FROM jsonb_array_elements(r.seats) p WHERE (p->>'bot')::boolean OR (p->>'id')::uuid=ANY((SELECT rematch FROM okeyix_pisti_private.sessions WHERE room_id=r.id)::uuid[]))=2 THEN
     UPDATE public.okeyix_pisti_rooms SET status='waiting',summary=NULL,deadline=NULL,version=version+1,
      seats=jsonb_set(jsonb_set(seats,'{0,ready}','true'),'{1,ready}','true'),updated_at=clock_timestamp() WHERE id=r.id;
     UPDATE okeyix_pisti_private.sessions SET state=NULL,paid=false,rematch='{}' WHERE room_id=r.id;
    END IF;
   ELSIF p_action='invite' THEN
    IF r.status<>'waiting' OR jsonb_array_length(r.seats)<>1 THEN RAISE EXCEPTION 'TABLE_FULL'; END IF;
    IF NOT EXISTS(SELECT 1 FROM public.friends WHERE status='accepted' AND
      ((user_id=p_user AND friend_id=(p_args->>'to_user')::uuid) OR (friend_id=p_user AND user_id=(p_args->>'to_user')::uuid))) THEN RAISE EXCEPTION 'FRIEND_REQUIRED'; END IF;
    IF EXISTS(SELECT 1 FROM public.profiles WHERE id=(p_args->>'to_user')::uuid AND NOT allow_game_invites) THEN RAISE EXCEPTION 'INVITES_DISABLED'; END IF;
    INSERT INTO public.okeyix_pisti_invites(table_id,from_user,to_user) VALUES(r.id,p_user,(p_args->>'to_user')::uuid) RETURNING id INTO rid;
   ELSE RAISE EXCEPTION 'UNKNOWN_ACTION'; END IF;
  END IF;
  result:=jsonb_build_object('room_id',r.id,'invite_id',rid);
 END IF;
 IF p_action<>'heartbeat' THEN INSERT INTO okeyix_pisti_private.requests VALUES(p_user,p_request,p_action,p_args,result,clock_timestamp()); END IF;
 RETURN result;
END $$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA okeyix_pisti_private FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.okeyix_pisti_can_view(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.okeyix_pisti_can_view(uuid) TO authenticated;
-- RLS calls this immutable helper with already-public seats only.
GRANT USAGE ON SCHEMA okeyix_pisti_private TO authenticated;
GRANT EXECUTE ON FUNCTION okeyix_pisti_private.member(jsonb,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.okeyix_pisti_load(uuid),public.okeyix_pisti_commit(uuid,bigint,jsonb,uuid,uuid,integer,boolean),
 public.okeyix_pisti_command(uuid,uuid,text,jsonb),public.okeyix_pisti_view_allowed(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.okeyix_pisti_load(uuid),public.okeyix_pisti_commit(uuid,bigint,jsonb,uuid,uuid,integer,boolean),
 public.okeyix_pisti_command(uuid,uuid,text,jsonb),public.okeyix_pisti_view_allowed(uuid,uuid) TO service_role;
DO $$ BEGIN
 ALTER PUBLICATION supabase_realtime ADD TABLE public.okeyix_pisti_rooms;
 ALTER PUBLICATION supabase_realtime ADD TABLE public.okeyix_pisti_invites;
 ALTER PUBLICATION supabase_realtime ADD TABLE public.okeyix_pisti_messages;
END $$;
NOTIFY pgrst,'reload schema';
COMMIT;
