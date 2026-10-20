-- NOT APPLIED. Apply after statistics migrations 001-003, first in staging.
-- Additive: no game RPC, profile counter, payment formula or projector changes.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $$ BEGIN
  IF current_user<>'postgres' OR NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname=current_user AND rolbypassrls)
    THEN RAISE EXCEPTION 'REFERRAL_REQUIRES_POSTGRES'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_extension WHERE extname='pg_cron')
    THEN RAISE EXCEPTION 'REFERRAL_REQUIRES_PG_CRON'; END IF;
END $$;
CREATE SCHEMA okeyix_referral_private AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA okeyix_referral_private FROM PUBLIC,anon,authenticated,service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA okeyix_referral_private REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

CREATE TABLE okeyix_referral_private.codes (
  user_id uuid PRIMARY KEY,
  code text NOT NULL UNIQUE CHECK(code ~ '^[A-F0-9]{12}$'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  last_attempt_at timestamptz
);
-- Historical identities intentionally have no cascading FK to game/user tables.
CREATE TABLE okeyix_referral_private.invitations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  inviter_id uuid NOT NULL,
  invitee_id uuid NOT NULL UNIQUE,
  code text NOT NULL,
  accepted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  progress smallint NOT NULL DEFAULT 0 CHECK(progress BETWEEN 0 AND 10),
  rewarded_at timestamptz,
  checked_at timestamptz NOT NULL DEFAULT '-infinity',
  error_code text,
  CHECK(inviter_id<>invitee_id),
  CHECK(rewarded_at IS NULL OR progress=10)
);
CREATE INDEX invitations_inviter ON okeyix_referral_private.invitations(inviter_id,accepted_at DESC,id DESC);
CREATE INDEX invitations_pending ON okeyix_referral_private.invitations(checked_at,id) WHERE rewarded_at IS NULL;
CREATE TABLE okeyix_referral_private.payments (
  invitation_id uuid NOT NULL REFERENCES okeyix_referral_private.invitations(id) ON DELETE RESTRICT,
  beneficiary_id uuid NOT NULL,
  amount integer NOT NULL CHECK(amount=1000000),
  wallet_transaction_id uuid NOT NULL UNIQUE,
  PRIMARY KEY(invitation_id,beneficiary_id)
);
ALTER TABLE okeyix_referral_private.codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE okeyix_referral_private.invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE okeyix_referral_private.payments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA okeyix_referral_private FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION okeyix_referral_private.ensure_code(p_user uuid) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE c text;
BEGIN
  IF NOT EXISTS(SELECT 1 FROM public.users WHERE id=p_user AND NOT is_bot) THEN
    RAISE EXCEPTION 'REFERRAL_PLAYER_REQUIRED' USING ERRCODE='42501'; END IF;
  SELECT code INTO c FROM okeyix_referral_private.codes WHERE user_id=p_user;
  IF c IS NOT NULL THEN RETURN c; END IF;
  LOOP
    c:=upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
    BEGIN
      INSERT INTO okeyix_referral_private.codes(user_id,code) VALUES(p_user,c)
        ON CONFLICT(user_id) DO NOTHING;
      SELECT code INTO c FROM okeyix_referral_private.codes WHERE user_id=p_user;
      RETURN c;
    EXCEPTION WHEN unique_violation THEN NULL; -- random code collision only
    END;
  END LOOP;
END $$;

CREATE FUNCTION public.okeyix_redeem_invite(p_code text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE u uuid:=auth.uid(); inviter uuid; own_code text; last_attempt timestamptz; c text:=upper(btrim(p_code));
BEGIN
  IF u IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE='42501'; END IF;
  own_code:=okeyix_referral_private.ensure_code(u);
  -- Serialize all attempts for this user, including different-code races.
  SELECT last_attempt_at INTO last_attempt FROM okeyix_referral_private.codes WHERE user_id=u FOR UPDATE;
  IF EXISTS(SELECT 1 FROM okeyix_referral_private.invitations WHERE invitee_id=u) THEN
    RETURN jsonb_build_object('status','already_used'); END IF;
  IF last_attempt>clock_timestamp()-interval '3 seconds' THEN RETURN jsonb_build_object('status','slow_down'); END IF;
  UPDATE okeyix_referral_private.codes SET last_attempt_at=clock_timestamp() WHERE user_id=u;
  IF c IS NULL OR c !~ '^[A-F0-9]{12}$' THEN RETURN jsonb_build_object('status','invalid_code'); END IF;
  IF c=own_code THEN RETURN jsonb_build_object('status','own_code'); END IF;
  SELECT k.user_id INTO inviter FROM okeyix_referral_private.codes k
    JOIN public.users s ON s.id=k.user_id AND NOT s.is_bot WHERE k.code=c;
  IF inviter IS NULL THEN RETURN jsonb_build_object('status','invalid_code'); END IF;
  INSERT INTO okeyix_referral_private.invitations(inviter_id,invitee_id,code) VALUES(inviter,u,c);
  RETURN jsonb_build_object('status','accepted');
END $$;

CREATE FUNCTION okeyix_referral_private.process(p_limit integer DEFAULT 100) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE i record; n integer; done integer:=0; w uuid; affected integer; inviter_wallet_id uuid;
BEGIN
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 1000 THEN RAISE EXCEPTION 'INVALID_LIMIT'; END IF;
  FOR i IN SELECT * FROM okeyix_referral_private.invitations
    WHERE rewarded_at IS NULL AND checked_at<clock_timestamp()-interval '45 seconds'
    ORDER BY checked_at,id LIMIT p_limit FOR UPDATE SKIP LOCKED LOOP
    n:=NULL;
    BEGIN
      -- Only permanent, server-confirmed results. Snapshot bot flags are decisive.
      -- A late projector replay of an old hand cannot count: event finish time
      -- must be later than code acceptance. Distinct round PKs count once.
      SELECT count(*) INTO n FROM (
        SELECT r.id FROM public.okeyix_stat_players me
        JOIN public.okeyix_stat_rounds r ON r.id=me.round_id
        WHERE me.user_id=i.invitee_id AND NOT me.is_bot AND me.outcome IN ('win','loss')
          AND r.status='completed' AND r.finished_at>i.accepted_at
          AND (SELECT count(*) FROM public.okeyix_stat_players p WHERE p.round_id=r.id) IN (2,4)
          AND NOT EXISTS(SELECT 1 FROM public.okeyix_stat_players p WHERE p.round_id=r.id
            AND (p.is_bot OR p.outcome NOT IN ('win','loss')))
          AND (SELECT count(*) FROM public.okeyix_stat_players p WHERE p.round_id=r.id AND p.outcome='win')=1
          AND EXISTS(SELECT 1 FROM public.okeyix_stat_players p WHERE p.round_id=r.id
            AND p.user_id=r.winner_user_id AND p.outcome='win')
        LIMIT 10
      ) valid;
      UPDATE okeyix_referral_private.invitations SET progress=n,checked_at=clock_timestamp(),error_code=NULL WHERE id=i.id;
      IF n=10 THEN
        IF (SELECT count(*) FROM public.users WHERE id IN(i.inviter_id,i.invitee_id) AND NOT is_bot)<>2 THEN
          RAISE EXCEPTION 'REFERRAL_RECIPIENT_MISSING'; END IF;
        -- One ordering across overlapping invitation pairs prevents deadlocks.
        PERFORM id FROM public.profiles WHERE id IN(i.inviter_id,i.invitee_id) ORDER BY id FOR UPDATE;
        IF (SELECT count(*) FROM public.profiles WHERE id IN(i.inviter_id,i.invitee_id) AND coins IS NOT NULL)<>2 THEN
          RAISE EXCEPTION 'REFERRAL_WALLET_UNAVAILABLE'; END IF;
        FOR w IN SELECT id FROM public.profiles WHERE id IN(i.inviter_id,i.invitee_id) ORDER BY id LOOP
          INSERT INTO public.wallet_transactions(user_id,amount,reason,type,store,note)
            VALUES(w,1000000,'friend_referral','credit','system','Okeyix friend referral: '||i.id::text)
            RETURNING id INTO inviter_wallet_id;
          INSERT INTO okeyix_referral_private.payments(invitation_id,beneficiary_id,amount,wallet_transaction_id)
            VALUES(i.id,w,1000000,inviter_wallet_id);
          UPDATE public.profiles SET coins=coins+1000000 WHERE id=w;
          GET DIAGNOSTICS affected=ROW_COUNT;
          IF affected<>1 THEN RAISE EXCEPTION 'REFERRAL_WALLET_UNAVAILABLE'; END IF;
        END LOOP;
        UPDATE okeyix_referral_private.invitations SET rewarded_at=clock_timestamp() WHERE id=i.id;
      END IF;
      done:=done+1;
    EXCEPTION WHEN OTHERS THEN
      -- Subtransaction rolls back BOTH credits, both receipts and progress.
      -- Keep the durable invitation retryable; expose no exception text/PII.
      UPDATE okeyix_referral_private.invitations SET progress=coalesce(n,progress),checked_at=clock_timestamp(),error_code=SQLSTATE WHERE id=i.id;
    END;
  END LOOP;
  RETURN done;
END $$;

CREATE FUNCTION public.okeyix_invite_dashboard() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE u uuid:=auth.uid(); c text;
BEGIN
  IF u IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE='42501'; END IF;
  c:=okeyix_referral_private.ensure_code(u);
  RETURN jsonb_build_object('code',c,
    'total_invites',(SELECT count(*) FROM okeyix_referral_private.invitations WHERE inviter_id=u),
    'successful_invites',(SELECT count(*) FROM okeyix_referral_private.invitations WHERE inviter_id=u AND rewarded_at IS NOT NULL),
    'earned_coin',(SELECT coalesce(sum(p.amount),0) FROM okeyix_referral_private.payments p
      JOIN okeyix_referral_private.invitations i ON i.id=p.invitation_id WHERE i.inviter_id=u AND p.beneficiary_id=u),
    'redemption',(SELECT jsonb_build_object('code',code,'progress',progress,'rewarded',rewarded_at IS NOT NULL)
      FROM okeyix_referral_private.invitations WHERE invitee_id=u));
END $$;

CREATE FUNCTION public.okeyix_invited_friends(p_before_at timestamptz DEFAULT NULL,p_before_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE u uuid:=auth.uid();
BEGIN
  IF u IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE='42501'; END IF;
  IF (p_before_at IS NULL)<>(p_before_id IS NULL) THEN RAISE EXCEPTION 'INVALID_CURSOR'; END IF;
  RETURN (SELECT coalesce(jsonb_agg(to_jsonb(f) ORDER BY accepted_at DESC,id DESC),'[]'::jsonb) FROM (
    SELECT i.id,i.accepted_at,coalesce(nullif(s.username,''),'Oyuncu') AS username,s.avatar_url,
      i.progress,i.rewarded_at IS NOT NULL AS rewarded,CASE WHEN i.rewarded_at IS NOT NULL THEN 1000000 ELSE 0 END AS earned_coin
    FROM okeyix_referral_private.invitations i LEFT JOIN public.users s ON s.id=i.invitee_id
    WHERE i.inviter_id=u AND (p_before_at IS NULL OR (i.accepted_at,i.id)<(p_before_at,p_before_id))
    ORDER BY i.accepted_at DESC,i.id DESC LIMIT 30
  ) f);
END $$;
ALTER FUNCTION public.okeyix_redeem_invite(text) OWNER TO postgres;
ALTER FUNCTION public.okeyix_invite_dashboard() OWNER TO postgres;
ALTER FUNCTION public.okeyix_invited_friends(timestamptz,uuid) OWNER TO postgres;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA okeyix_referral_private FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.okeyix_redeem_invite(text),public.okeyix_invite_dashboard(),
  public.okeyix_invited_friends(timestamptz,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.okeyix_redeem_invite(text),public.okeyix_invite_dashboard(),
  public.okeyix_invited_friends(timestamptz,uuid) TO authenticated;
SELECT cron.schedule('okeyix-friend-referrals','* * * * *','SELECT okeyix_referral_private.process(100);');
NOTIFY pgrst,'reload schema';
COMMIT;
