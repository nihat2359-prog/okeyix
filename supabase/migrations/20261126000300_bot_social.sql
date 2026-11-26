BEGIN;

-- Membership-scoped receipts survive reconnects, but reset on leaving the table.
CREATE TABLE public.okeyix_bot_social_state (
  membership_id uuid PRIMARY KEY REFERENCES public.table_players(id) ON DELETE CASCADE,
  bot_membership_id uuid NOT NULL REFERENCES public.table_players(id) ON DELETE CASCADE,
  started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  greeted boolean NOT NULL DEFAULT false,
  tea_sent boolean NOT NULL DEFAULT false,
  asked boolean NOT NULL DEFAULT false,
  congratulated_at timestamptz,
  last_reply_at timestamptz,
  last_message_id uuid
);
ALTER TABLE public.okeyix_bot_social_state ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.okeyix_bot_social_state FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.okeyix_bot_social_tick(p_table_id uuid, p_closed_finish_at timestamptz DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE
  t public.tables%ROWTYPE;
  human public.table_players%ROWTYPE;
  bot public.table_players%ROWTYPE;
  s public.okeyix_bot_social_state%ROWTYPE;
  msg public.table_messages%ROWTYPE;
  reply text;
  normalized text;
  gift public.okeyix_gift_catalog%ROWTYPE;
  wallet_id uuid;
  purchase_seq bigint;
  moment timestamptz := clock_timestamp();
BEGIN
  IF auth.uid() IS NULL THEN RETURN; END IF;
  SELECT * INTO t FROM public.tables WHERE id=p_table_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;
  SELECT p.* INTO human FROM public.table_players p JOIN public.users u ON u.id=p.user_id
    WHERE p.table_id=t.id AND p.user_id=auth.uid() AND NOT u.is_bot;
  IF NOT FOUND THEN RETURN; END IF;
  SELECT p.* INTO bot FROM public.table_players p JOIN public.users u ON u.id=p.user_id
    WHERE p.table_id=t.id AND u.is_bot ORDER BY p.seat_index LIMIT 1;
  IF NOT FOUND THEN RETURN; END IF;
  INSERT INTO public.okeyix_bot_social_state(membership_id,bot_membership_id)
    VALUES(human.id,bot.id) ON CONFLICT DO NOTHING;
  SELECT * INTO s FROM public.okeyix_bot_social_state WHERE membership_id=human.id FOR UPDATE;
  IF s.bot_membership_id<>bot.id THEN RETURN; END IF;

  -- Opening actions are separated in time; each is committed only once.
  IF t.status='playing' AND moment>=s.started_at+interval '2 seconds' AND NOT s.greeted
      AND t.chat_enabled THEN
    INSERT INTO public.table_messages(table_id,sender_id,role,type,content)
      VALUES(t.id,bot.user_id,'player','text','Bol şans');
    UPDATE public.okeyix_bot_social_state SET greeted=true,last_reply_at=moment WHERE membership_id=human.id;
    RETURN;
  END IF;
  IF t.status='playing' AND t.max_players=2 AND NOT s.tea_sent
      AND moment>=s.started_at+interval '5 seconds'
      AND (SELECT count(*) FROM public.table_players WHERE table_id=t.id)=2 THEN
    SELECT * INTO gift FROM public.okeyix_gift_catalog WHERE id='cay' AND enabled;
    IF FOUND THEN
      UPDATE public.profiles SET coins=coins-gift.price WHERE id=bot.user_id AND coins>=gift.price;
      IF FOUND THEN
        INSERT INTO public.wallet_transactions(user_id,amount,reason,type,store,note)
          VALUES(bot.user_id,-gift.price,'table_gift','debit','system','cay') RETURNING id INTO wallet_id;
        INSERT INTO public.okeyix_table_gift_purchases(request_id,table_id,sender_id,recipient_id,gift_id,price,wallet_transaction_id)
          VALUES(gen_random_uuid(),t.id,bot.user_id,human.user_id,'cay',gift.price,wallet_id) RETURNING seq INTO purchase_seq;
        INSERT INTO public.okeyix_table_last_gifts(table_id,user_id,membership_id,purchase_seq,gift_id)
          VALUES(t.id,human.user_id,human.id,purchase_seq,'cay')
          ON CONFLICT(table_id,user_id) DO UPDATE SET membership_id=excluded.membership_id,
            purchase_seq=excluded.purchase_seq,gift_id=excluded.gift_id;
        UPDATE public.okeyix_bot_social_state SET tea_sent=true WHERE membership_id=human.id;
      END IF;
    END IF;
  END IF;
  IF NOT t.chat_enabled THEN RETURN; END IF;

  -- The UI supplies its closed receipt; the winner and finish time remain server verified.
  IF t.last_winner_user_id=human.user_id AND t.last_finish_at=p_closed_finish_at
      AND t.last_finish_at>=s.started_at AND moment>=t.last_finish_at+interval '4 seconds'
      AND s.congratulated_at IS DISTINCT FROM t.last_finish_at THEN
    INSERT INTO public.table_messages(table_id,sender_id,role,type,content)
      VALUES(t.id,bot.user_id,'player','text','Tebrikler');
    UPDATE public.okeyix_bot_social_state SET congratulated_at=t.last_finish_at,last_reply_at=moment
      WHERE membership_id=human.id;
    RETURN;
  END IF;
  IF t.status<>'playing' OR NOT s.greeted OR
      moment<coalesce(s.last_reply_at,s.started_at)+interval '12 seconds' THEN RETURN; END IF;

  -- Only fresh human text can trigger replies. Bot messages never trigger bots.
  SELECT * INTO msg FROM public.table_messages WHERE table_id=t.id AND sender_id=human.user_id
    AND role='player' AND type='text' AND created_at>s.started_at
    AND created_at>moment-interval '45 seconds' AND created_at<=moment-interval '3 seconds'
    AND created_at>coalesce((SELECT created_at FROM public.table_messages WHERE id=s.last_message_id),s.started_at)
    ORDER BY created_at DESC,id DESC LIMIT 1;
  IF FOUND THEN
    normalized := translate(lower(msg.content),'ıİşğüöç','iİsguoc');
    reply := CASE
      WHEN normalized LIKE '%tebrik%' THEN 'teşekkürler'
      WHEN normalized ~ '(merhaba|selam)' THEN 'selam iyi oyunlar'
      WHEN normalized LIKE '%nasilsin%' THEN 'iyiyim sen nasılsın'
      WHEN normalized ~ '(bot musun|robot musun|gercek misin)' THEN 'evet oyun botuyum :)'
      WHEN normalized ~ '(nereli|nerede|kac yas|adin ne)' THEN 'ben oyun botuyum ya :)'
      WHEN normalized ~ '(rovan|tekrar|bir el daha)' THEN 'olur oynayalım'
      WHEN normalized ~ '(cay|tesekkur)' THEN 'afiyet olsun :)'
      WHEN normalized LIKE '%bol sans%' THEN 'sağ ol sana da'
      WHEN normalized ~ '(nasil gidiyor|el nasil)' THEN 'daha toparlayamadım sende nasıl'
      WHEN normalized LIKE '%?%' THEN 'taşlara daldım ya'
      ELSE NULL END;
    UPDATE public.okeyix_bot_social_state SET last_message_id=msg.id WHERE membership_id=human.id;
  ELSIF NOT s.asked AND moment>=s.started_at+interval '45 seconds'
      AND NOT EXISTS(SELECT 1 FROM public.table_messages WHERE table_id=t.id
        AND created_at>moment-interval '15 seconds') THEN
    reply := 'nasıl gidiyo taşlar iyi mi';
    UPDATE public.okeyix_bot_social_state SET asked=true WHERE membership_id=human.id;
  END IF;
  IF reply IS NOT NULL THEN
    INSERT INTO public.table_messages(table_id,sender_id,role,type,content)
      VALUES(t.id,bot.user_id,'player','text',reply);
    UPDATE public.okeyix_bot_social_state SET last_reply_at=moment WHERE membership_id=human.id;
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.okeyix_bot_social_tick(uuid,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.okeyix_bot_social_tick(uuid,timestamptz) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
