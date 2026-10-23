-- SALT OKUNUR. Tamamini SQL Editor'da calistirip tek JSON sonucunu paylasin.
-- Hesap, masa veya bakiye degistirmez; kimlik/anahtar dondurmez.
WITH occupancy AS (
  SELECT t.id,t.league_id,t.status,count(p.user_id) AS seated
  FROM public.tables t LEFT JOIN public.table_players p ON p.table_id=t.id
  GROUP BY t.id,t.league_id,t.status
), grouped AS (
  SELECT league_id,status,count(*) AS total,
    count(*) FILTER(WHERE seated=0) AS empty,
    count(*) FILTER(WHERE seated>0) AS occupied
  FROM occupancy WHERE status IN ('waiting','start','starting','playing')
  GROUP BY league_id,status
)
SELECT jsonb_build_object(
  'kurulum_yuklu',to_regclass('okeyix_ready_private.policy') IS NOT NULL,
  'otomatik_masalar_aktif',CASE
    WHEN to_regclass('okeyix_ready_private.policy') IS NULL THEN 'kurulu degil'
    ELSE (xpath('//enabled/text()',query_to_xml(
      'SELECT enabled FROM okeyix_ready_private.policy',true,false,'')))[1]::text END,
  'sistem_hesabi_hazir',EXISTS(SELECT 1 FROM auth.users
    WHERE raw_app_meta_data->>'okeyix_system'='ready_tables_owner'
      AND banned_until>now() AND last_sign_in_at IS NULL),
  'masalar',coalesce((SELECT jsonb_agg(jsonb_build_object(
    'lig',league_id,'durum',status,'toplam',total,
    'oyuncusuz',empty,'oyunculu',occupied) ORDER BY league_id,status)
    FROM grouped),'[]'::jsonb)
) AS hazir_masa_durumu;
