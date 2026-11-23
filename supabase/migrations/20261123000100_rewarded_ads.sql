-- Deploy with admob-reward callback before enabling ADMOB_REWARDS_ENABLED.
BEGIN;
CREATE SCHEMA IF NOT EXISTS okeyix_ads_private;
REVOKE ALL ON SCHEMA okeyix_ads_private FROM PUBLIC, anon, authenticated;
CREATE TABLE okeyix_ads_private.attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  day date NOT NULL DEFAULT (statement_timestamp() AT TIME ZONE 'Europe/Istanbul')::date,
  created_at timestamptz NOT NULL DEFAULT now(),
  transaction_id text UNIQUE,
  credited boolean NOT NULL DEFAULT false
);
ALTER TABLE okeyix_ads_private.attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON okeyix_ads_private.attempts FROM PUBLIC, anon, authenticated;
CREATE UNIQUE INDEX ad_reward_once_per_day ON okeyix_ads_private.attempts(user_id, day) WHERE credited;

CREATE FUNCTION public.okeyix_ad_reward_status() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  RETURN jsonb_build_object('available', NOT EXISTS (
    SELECT 1 FROM okeyix_ads_private.attempts WHERE user_id=auth.uid() AND credited
      AND day=(statement_timestamp() AT TIME ZONE 'Europe/Istanbul')::date), 'amount',15000,
      'day_key',to_char(statement_timestamp() AT TIME ZONE 'Europe/Istanbul','YYYY-MM-DD'));
END $$;

CREATE FUNCTION public.okeyix_begin_ad_reward() RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE ticket uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  PERFORM 1 FROM public.profiles WHERE id=auth.uid() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PROFILE_NOT_FOUND'; END IF;
  IF EXISTS (SELECT 1 FROM okeyix_ads_private.attempts WHERE user_id=auth.uid() AND credited
    AND day=(statement_timestamp() AT TIME ZONE 'Europe/Istanbul')::date) THEN
    RAISE EXCEPTION 'ALREADY_CLAIMED';
  END IF;
  -- Reuse the current ticket for retries, bounding storage and request spam.
  SELECT id INTO ticket FROM okeyix_ads_private.attempts WHERE user_id=auth.uid()
    AND NOT credited AND created_at>now()-interval '1 hour'
    AND day=(statement_timestamp() AT TIME ZONE 'Europe/Istanbul')::date
    ORDER BY created_at DESC LIMIT 1;
  IF ticket IS NULL THEN
    INSERT INTO okeyix_ads_private.attempts(user_id) VALUES(auth.uid()) RETURNING id INTO ticket;
  END IF;
  RETURN ticket;
END $$;

CREATE FUNCTION public.okeyix_ad_reward_receipt(p_attempt uuid) RETURNS boolean
LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
  SELECT EXISTS(SELECT 1 FROM okeyix_ads_private.attempts
    WHERE id=p_attempt AND user_id=auth.uid() AND credited)
$$;

-- Only the signature-verifying Edge Function may call this endpoint.
CREATE FUNCTION public.okeyix_credit_ad_reward(p_attempt uuid, p_user uuid, p_transaction text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a okeyix_ads_private.attempts; affected integer;
BEGIN
  IF p_transaction IS NULL OR length(p_transaction) NOT BETWEEN 1 AND 256 THEN
    RAISE EXCEPTION 'INVALID_TRANSACTION';
  END IF;
  -- Same profile lock serializes all attempts and concurrent balance changes.
  PERFORM 1 FROM public.profiles WHERE id=p_user FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PROFILE_NOT_FOUND'; END IF;
  SELECT * INTO a FROM okeyix_ads_private.attempts WHERE id=p_attempt AND user_id=p_user FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'INVALID_ATTEMPT'; END IF;
  IF a.credited THEN RETURN a.transaction_id=p_transaction; END IF;
  IF a.created_at<now()-interval '24 hours' THEN RAISE EXCEPTION 'EXPIRED_ATTEMPT'; END IF;
  IF EXISTS(SELECT 1 FROM okeyix_ads_private.attempts WHERE user_id=p_user AND day=a.day AND credited) THEN RETURN false; END IF;
  UPDATE okeyix_ads_private.attempts SET credited=true,transaction_id=p_transaction WHERE id=a.id;
  INSERT INTO public.wallet_transactions(user_id,amount,reason,type,store,note)
    VALUES(p_user,15000,'rewarded_ad','credit','admob','rewarded_ad:'||a.id::text);
  UPDATE public.profiles SET coins=coalesce(coins,0)+15000 WHERE id=p_user;
  GET DIAGNOSTICS affected=ROW_COUNT;
  IF affected<>1 THEN RAISE EXCEPTION 'PROFILE_NOT_FOUND'; END IF;
  RETURN true;
END $$;

REVOKE ALL ON FUNCTION public.okeyix_ad_reward_status(),public.okeyix_begin_ad_reward(),
  public.okeyix_ad_reward_receipt(uuid),public.okeyix_credit_ad_reward(uuid,uuid,text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.okeyix_ad_reward_status(),public.okeyix_begin_ad_reward(),
  public.okeyix_ad_reward_receipt(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.okeyix_credit_ad_reward(uuid,uuid,text) TO service_role;
COMMIT;
