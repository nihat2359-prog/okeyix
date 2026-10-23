-- SALT OKUNUR. start masalarinda bot/insan ve dagitilmis el durumunu ozetler.
-- Kimlik, isim, bakiye veya tas bilgisi dondurmez; hicbir kaydi degistirmez.
WITH state AS (
  SELECT t.id,t.max_players,t.created_at,count(tp.user_id) AS seated,
    count(tp.user_id) FILTER(WHERE u.is_bot=false) AS humans,
    count(tp.user_id) FILTER(WHERE u.is_bot=true) AS bots,
    count(tp.user_id) FILTER(WHERE u.id IS NULL) AS unknown,
    bool_or(jsonb_array_length(CASE WHEN jsonb_typeof(tp.hand)='array'
      THEN tp.hand ELSE '[]'::jsonb END)>0) AS has_hand
  FROM public.tables t LEFT JOIN public.table_players tp ON tp.table_id=t.id
  LEFT JOIN public.users u ON u.id=tp.user_id
  WHERE t.league_id::text='standard' AND t.status='start'
  GROUP BY t.id
)
SELECT max_players AS masa_kapasitesi,count(*) AS masa_sayisi,
  count(*) FILTER(WHERE humans=0 AND unknown=0) AS sadece_bot_masasi,
  count(*) FILTER(WHERE humans>0) AS insan_bulunan_masa,
  count(*) FILTER(WHERE unknown>0) AS kimligi_belirsiz_masa,
  count(*) FILTER(WHERE seated<max_players) AS eksik_oyunculu_masa,
  count(*) FILTER(WHERE has_hand) AS el_dagitilmis_masa,
  floor(extract(epoch FROM now()-min(created_at))/60)::bigint AS en_eski_masa_dakika
FROM state GROUP BY max_players ORDER BY max_players;
