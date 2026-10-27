-- NOT APPLIED. Deploy before the Flutter release. Legacy daily RPC is untouched.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $$ BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'POSTGRES_REQUIRED'; END IF;
  IF to_regclass('public.ux_wallet_daily_bonus_once_per_day') IS NULL THEN
    RAISE EXCEPTION 'DAILY_BONUS_UNIQUE_INDEX_REQUIRED'; END IF;
END $$;
CREATE SCHEMA IF NOT EXISTS okeyix_retention_private AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA okeyix_retention_private FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE okeyix_retention_private.reward_progress (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  claims bigint NOT NULL DEFAULT 0 CHECK(claims>=0),
  last_day_key text
);
ALTER TABLE okeyix_retention_private.reward_progress ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON okeyix_retention_private.reward_progress FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.okeyix_daily_reward_status() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE uid uuid:=auth.uid(); n bigint; day integer; last_key text;
  today text:='daily_bonus:'||to_char(statement_timestamp() AT TIME ZONE 'Europe/Istanbul','YYYY-MM-DD');
  rewards integer[]:=ARRAY[2500,3000,3500,4000,4500,5000,7500];
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE='42501'; END IF;
  SELECT claims,last_day_key INTO n,last_key FROM okeyix_retention_private.reward_progress WHERE user_id=uid;
  n:=coalesce(n,0); day:=(n%7)::integer+1;
  IF last_key=today AND n>0 THEN day:=((n-1)%7)::integer+1; END IF;
  RETURN jsonb_build_object('day',day,'amount',rewards[day],'rewards',rewards,
    'available',NOT EXISTS(SELECT 1 FROM public.wallet_transactions
      WHERE user_id=uid AND reason='daily_bonus' AND note=today),
    'day_key',today);
END $$;

CREATE FUNCTION public.okeyix_claim_daily_reward() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE uid uuid:=auth.uid(); n bigint; day integer; amount integer; inserted integer;
  today text:='daily_bonus:'||to_char(statement_timestamp() AT TIME ZONE 'Europe/Istanbul','YYYY-MM-DD');
  rewards integer[]:=ARRAY[2500,3000,3500,4000,4500,5000,7500];
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE='42501'; END IF;
  -- Serialize new-client claims without locking profiles before the wallet
  -- insert: the legacy function inserts the receipt before updating profiles.
  INSERT INTO okeyix_retention_private.reward_progress(user_id) VALUES(uid) ON CONFLICT DO NOTHING;
  SELECT claims INTO n FROM okeyix_retention_private.reward_progress WHERE user_id=uid FOR UPDATE;
  day:=(n%7)::integer+1; amount:=rewards[day];
  INSERT INTO public.wallet_transactions(user_id,amount,reason,type,store,note)
    VALUES(uid,amount,'daily_bonus','credit','system',today)
    ON CONFLICT(user_id,note) WHERE reason='daily_bonus' AND note IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS inserted=ROW_COUNT;
  IF inserted=0 THEN
    RETURN jsonb_build_object('credited',false,'amount',0,'day',day);
  END IF;
  UPDATE public.profiles SET coins=coalesce(coins,0)+amount WHERE id=uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'BONUS_PROFILE_NOT_FOUND'; END IF;
  UPDATE okeyix_retention_private.reward_progress SET claims=claims+1,last_day_key=today WHERE user_id=uid;
  RETURN jsonb_build_object('credited',true,'amount',amount,'day',day);
END $$;
ALTER FUNCTION public.okeyix_daily_reward_status() OWNER TO postgres;
ALTER FUNCTION public.okeyix_claim_daily_reward() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.okeyix_daily_reward_status(),public.okeyix_claim_daily_reward()
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.okeyix_daily_reward_status(),public.okeyix_claim_daily_reward() TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
