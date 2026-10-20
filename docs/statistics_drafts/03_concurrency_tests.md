# Arşiv: eski eşzamanlılık test taslağı

Güncel, yerelde çalıştırılmış test: `test/statistics/concurrency.ps1`.
Aşağıdaki metin uygulanmayacak V1 taslağına aittir.

Bu testler çalıştırılmadı. Üretimde çalıştırılmayacak. İki ayrı PostgreSQL
bağlantısı, inceleme sonrası kurulmuş `01_functions.sql` ve
`02_rollback_tests.sql` başındaki sahte kaynak fixture gerekir. Gerçek oyun
RPC'leri çağrılmaz, kaynak oyun tablolarına yazılmaz. Bu testte COMMIT yalnızca
izole veritabanındaki yeni istatistik kayıtlarını kalıcılaştırır.

Kaynak fixture için tam oyun DDL'si bilinmediğinden eksik kolonlarla INSERT
uydurulmadı. UUID `00000000-0000-4000-8000-000000000001`, iki koltuk ve kullanıcı
satırları hazırlanmadan test uygulanamaz. Para makbuzları sentetiktir.

## 1. Eşzamanlı begin

Yeni fixture'da henüz istatistik session bulunmamalı. İki bağlantı da postgres
olmalı. A'da aşağıdaki transaction'ı başlat; uyku sırasında B'de aynı SELECT'i
kendi transaction'ı içinde çalıştır. B, A tamamlanana kadar beklemeli ve sonra
AYNI UUID'yi almalı. Her bağlantıda lock_timeout bekleme süresinden büyük olmalı.

```sql
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL lock_timeout = '15s';
SET LOCAL statement_timeout = '30s';

SELECT public.okeyix_stat_begin_round(
  t.id, t.shuffle_seed::uuid, t.round_count::bigint, t.turn_started_at,
  (SELECT jsonb_agg(jsonb_build_object(
     'user_id', tp.user_id, 'coin_entry', NULL
   ) ORDER BY tp.user_id)
   FROM public.table_players AS tp WHERE tp.table_id = t.id)
)
FROM public.tables AS t
WHERE t.id = '00000000-0000-4000-8000-000000000001';

-- Yalnızca A bağlantısında. B'de bu uyku satırını çıkar.
SELECT pg_sleep(5);
COMMIT;
```

Kontrol: tek session, tek round, iki player. B'nin yalnızca bloklanması yeterli
değil; iki bağlantının dönüş UUID'leri ve aşağıdaki sayılar karşılaştırılmalı.

```sql
SELECT s.id,
       (SELECT count(*) FROM public.okeyix_stat_rounds r
        WHERE r.session_id = s.id) AS rounds,
       (SELECT count(*) FROM public.okeyix_stat_players p
        JOIN public.okeyix_stat_rounds r ON r.id = p.round_id
        WHERE r.session_id = s.id) AS players
FROM public.okeyix_stat_sessions s
WHERE s.table_id = '00000000-0000-4000-8000-000000000001';
```

## 2. Eşzamanlı finalize

Birinci testten sonra, henüz started olan fixture eli için iki bağlantıda aynı
aşağıdaki transaction'ı kullan. Yalnızca A, COMMIT öncesinde beş saniye beklesin.
B beklemeli, A commit edince aynı UUID'yi döndürmeli. Tek win ve tek loss kalmalı.

```sql
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL lock_timeout = '15s';
SET LOCAL statement_timeout = '30s';

SELECT public.okeyix_stat_finalize_round(
  s.table_id, t.shuffle_seed::uuid, r.round_no,
  (SELECT p.user_id FROM public.okeyix_stat_players p
   WHERE p.round_id = r.id AND p.seat_index = 0),
  true, true, r.started_at + interval '1 minute',
  (SELECT jsonb_agg(jsonb_build_object(
     'user_id', p.user_id,
     'coin_reward', CASE WHEN p.seat_index = 0 THEN 900 ELSE 0 END,
     'coin_refund', NULL, 'coin_bonus', NULL, 'coin_penalty', NULL,
     'rating_delta', CASE WHEN p.seat_index = 0 THEN 8 ELSE 0 END
   ) ORDER BY p.user_id)
   FROM public.okeyix_stat_players p WHERE p.round_id = r.id)
)
FROM public.okeyix_stat_sessions s
JOIN public.okeyix_stat_rounds r ON r.session_id = s.id
JOIN public.tables t ON t.id = s.table_id
WHERE s.table_id = '00000000-0000-4000-8000-000000000001'
  AND r.round_no = t.round_count;

-- Yalnızca A bağlantısında.
SELECT pg_sleep(5);
COMMIT;
```

Sonuç sorgusu:

```sql
SELECT r.status, r.is_okey_finish, r.is_double_finish,
       count(*) FILTER (WHERE p.outcome = 'win') AS wins,
       count(*) FILTER (WHERE p.outcome = 'loss') AS losses
FROM public.okeyix_stat_sessions s
JOIN public.okeyix_stat_rounds r ON r.session_id = s.id
JOIN public.okeyix_stat_players p ON p.round_id = r.id
WHERE s.table_id = '00000000-0000-4000-8000-000000000001'
GROUP BY r.id, r.status, r.is_okey_finish, r.is_double_finish;
```

## 3. Çelişkili eşzamanlı sonuç

Yeni, started fixture ile 2. testi tekrarla; B bağlantısında p_is_okey=false
gönder. A'nın true sonucu commit ederse B `STAT_RESULT_REPLAY_CONFLICT` almalı.
B'nin transaction'ını ROLLBACK yap. İlk sonucu ve makbuzları değiştirmediğini
kontrol et. A'nın COMMIT değil ROLLBACK yaptığı varyantta B ilk başarılı yazar
olabilir; bu ikinci sonuç sayılmaz.

Bu bekleme beklentileri READ COMMITTED içindir. REPEATABLE READ/SERIALIZABLE
varyantlarında serialization failure ayrı beklenen sonuç olabilir; aynı başarılı
ödemenin yeniden yapılmasıyla karıştırılmamalı. Retry politikası transaction
sınırına ve kesin commit bilgisine göre ayrıca test edilir.

## 4. Gerçek rol testi

İzole veritabanında postgres bağlantısından iki ayrı test uygula. Beklenen
sonuç fonksiyona girmeden `permission denied for function` hatasıdır.
Her denemeden sonra ROLLBACK yap. Dummy argümanlar gerçek oyun oluşturmaz.

```sql
BEGIN;
SET LOCAL ROLE authenticated;
SELECT public.okeyix_stat_begin_round(
  NULL::uuid, NULL::uuid, NULL::bigint, NULL::timestamptz, NULL::jsonb
);
ROLLBACK;
```

```sql
BEGIN;
SET LOCAL ROLE anon;
SELECT public.okeyix_stat_finalize_round(
  NULL::uuid, NULL::uuid, NULL::bigint, NULL::uuid,
  NULL::boolean, NULL::boolean, NULL::timestamptz, NULL::jsonb
);
ROLLBACK;
```

service_role de taslakta yetkisizdir; aynı test onunla da uygulanır. PostgREST
JWT uçtan uca testi ayrıca gerekir; SET ROLE bunun tamamının yerine geçmez.

## 5. Entegrasyon öncesi ek matris

- Normal, yalnız okeyli, yalnız çiftli ve ikisi birlikte bitiş.
- İnsan ve bot kazanan; bot bayrağı kaynaktan gelmeli.
- Profil/bot kaydı eksik veya NULL user_id: begin hata vermeli, kısmi stat kalmamalı.
- Farklı kaynak anahtarıyla açık el varken begin: otomatik abort yapmadan reddetmeli.
- Farklı seed/round/tarih ile tekrar: sessizce ikinci kayıt oluşturmamalı.
- Tüm mali bileşenler biliniyorken net = reward+refund+bonus-entry-penalty.
- Mali bileşenlerden biri NULL iken net NULL; alan adı hatası reddedilmeli.
- Deferred FK: isolated fixture'da oyuncu olmayan kazananla doğrudan stat
  güncellemesi commit/SET CONSTRAINTS aşamasında reddedilmeli.
- Oyun ödeme transaction'ı geri alınırsa aynı transaction'daki stat da geri alınmalı.
- Kaynak masa izole fixture'da silindikten sonra var olan stat kayıtları korunmalı;
  önceki makbuzla replay çalışmalı, yeni sonuç/başlangıç uydurulmamalı.
- Bu son iki test yalnızca ayrıca onaylanmış izole kaynak-fixture işlemleriyle
  yapılabilir; bu belgeler kaynak oyuna yazan test SQL'i içermez.
