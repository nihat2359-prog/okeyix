-- NOT APPLIED. Run after 20261027000100. Preserves progress and existing receipts.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $patch$
DECLARE signature text; fn regprocedure; body text; changed text; expected text; installed text;
  old_rewards text:='ARRAY[2500,3000,3500,4000,4500,5000,7500]';
  new_rewards text:='ARRAY[2500,5000,10000,20000,40000,80000,160000]';
BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'POSTGRES_REQUIRED'; END IF;
  FOREACH signature IN ARRAY ARRAY['public.okeyix_daily_reward_status()',
      'public.okeyix_claim_daily_reward()'] LOOP
    fn:=to_regprocedure(signature);
    SELECT prosrc INTO body FROM pg_proc WHERE oid=fn
      AND proowner='postgres'::regrole AND prosecdef;
    IF NOT FOUND THEN RAISE EXCEPTION 'DAILY_REWARD_INSTALL_001_FIRST: %',signature; END IF;
    IF signature='public.okeyix_daily_reward_status()' THEN
      expected:='cf3d6376ee80f02c5da300ed2e923b90'; installed:='675d871b6dbec1c065f3e136532cdd73';
    ELSE
      expected:='62f0dd1bc25816d67a12ea2e49855938'; installed:='dca31437249c1be744525dad998f6eaa';
    END IF;
    IF md5(replace(body,chr(13)||chr(10),chr(10)))=installed THEN CONTINUE; END IF;
    IF md5(replace(body,chr(13)||chr(10),chr(10)))<>expected THEN
      RAISE EXCEPTION 'DAILY_REWARD_SOURCE_CHANGED_REVIEW_REQUIRED: %',signature; END IF;
    changed:=replace(pg_get_functiondef(fn),old_rewards,new_rewards);
    IF signature='public.okeyix_daily_reward_status()' THEN
      -- A reward already received today keeps its actual credited amount.
      changed:=replace(changed,'''day_key'',today',
        '''credited_amount'',(SELECT w.amount FROM public.wallet_transactions w WHERE w.user_id=uid AND w.reason=''daily_bonus'' AND w.note=today),''day_key'',today');
    END IF;
    EXECUTE changed;
    IF (SELECT md5(replace(prosrc,chr(13)||chr(10),chr(10))) FROM pg_proc WHERE oid=fn)<>installed THEN
      RAISE EXCEPTION 'DAILY_REWARD_PATCH_MISMATCH: %',signature; END IF;
  END LOOP;
END $patch$;
NOTIFY pgrst,'reload schema';
COMMIT;
