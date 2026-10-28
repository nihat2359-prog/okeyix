# Otomatik geri kazanım — Supabase kurulum ve işletim

Durum (28 Ekim 2026): **production migration'ları uygulandı, production Edge deploy edildi,
otomasyon ve Cron aktif.** Kullanıcının son açık talebiyle 004 migration'ı doğrulanmış izin
kaydı zorunluluğunu kaldırdı; son canlı kontrolde uygun alıcı sayısı **2.247**.
Telefonun OS/kanal izinleri aşılmaz; token izin kanıtı sayılmaz.
Kanıtlar: [canlı kurulum kaydı](reengagement_production_status_20261028.md).

**Politika değişikliği:** Bu belgedeki ayrı izin kaydı oluşturma ve `permission_unknown`
nedeniyle engelleme açıklamaları ilk 001 sürümüne aittir; 004 sonrasında otomasyon bu
kayıtları zorunlu tutmaz. Geçerli tek cihaz token'ı ile gönderim denenir. Mevcut
`allow_game_invites=false` tercihi, dört aşama, 72 saat ve diğer güvenlik filtreleri korunur.
Flutter, Web Admin, `register_device`, mevcut `send_table_invite_push`, FCM/APNs ayarları değişmedi.

Yalnızca kendi telefonuna, otomasyonu açmadan test için
[ayrı tek cihaz testi](reengagement_manual_test.md) kullanılmalı. Bu test için
otomasyon migration’ları veya Cron kurulumu gerekmez.

## Doğrulanan mevcut yapı ve önemli sınır

28 Ekim 2026 şema çıktısında 3.227 profil, 3.110 adet 48 saatten uzun pasif profil,
64 aktiflik tarihi bulunmayan profil ve 2.669 token içeren cihaz kaydı var.
Token sayısı kullanıcı veya izinli kullanıcı sayısı değildir.

Aktiflik `profiles.last_seen_at`, cihaz sıralaması `user_devices.last_seen` üzerinden alınır.
Gönderim, paylaşılan canlı davet fonksiyonundaki HTTP v1 / RS256 Google OAuth yöntemini,
aynı `FIREBASE_SERVICE_ACCOUNT_JSON` ve `FIREBASE_PROJECT_ID` ortam değişkenlerini kullanır.
Depodaki eski davet göndericisi canlı kaynakla farklıdır; **bu çalışma onu değiştirmez veya deploy etmez.**

**Mevcut şemada hatırlatma onayı veya işletim sistemi bildirim izin durumu yok.**
`register_device` bunları saklamıyor. `allow_game_invites=true` hatırlatma onayı değildir;
false değeri ek bir engelleme olarak korunur. Token hiçbir koşulda izin kanıtı sayılmaz.
Bu nedenle mevcut oyuncular otomatik olarak izinli yapılmaz; varsayılan sonuç `permission_unknown` olur.

Mobil değişiklik olmadan güncel iOS/Android izin durumunu sorgulamak mümkün değil.
SQL Editor’dan kaydedilen bağımsız doğrulama, yalnızca doğrulama anına ait bilgidir;
sonradan cihaz ayarlarından kapatılan izni sunucu anında bilemez. İşletim sistemi ayrıca kendi
izinini uygular. Kayıt yoksa, süresi dolmuşsa veya token değişmişse gönderim yapılmaz.
**Genel kullanıma açılmadan önce güvenilir izin kaynağı sağlanmalıdır; izin bilinmiyor engeli kaldırılmamalı.**

## Oluşturulan nesneler

| Nesne | Amaç |
|---|---|
| `okeyix_reengagement_private.settings` | Tek satır ayar; `enabled=false`, `dry_run=true` |
| `okeyix_reengagement_private.permissions` | Kullanıcı + cihaz + token özetine bağlı doğrulanmış onay/izin; boş başlar |
| `okeyix_reengagement_private.deliveries` | Aşama/dönem tekilliği, rezervasyon, sonuç, token geçersizliği |
| `okeyix_reengagement_private.candidates()` | Token göstermeyen uygunluk ve hariç tutulma nedenleri |
| `public.okeyix_reengagement_worker()` | Yalnızca service_role için önizleme, rezervasyon, son kontrol, sonuç |
| `okeyix_reengagement_private.invoke_worker()` | Vault’tan gizli anahtarla Edge Function çağrısı |
| `okeyix-reengagement-hourly` | Başlangıçta pasif Cron |
| `process_reengagement_notifications` | Ayrı ve sunucuya özel Edge Function |

Mevcut tablolara kolon/trigger/policy eklenmez; eski tokenlar silinmez. Üçüncü yeni tablo
izin bilgisi mevcut olmadığı için gereklidir. Private şema uygulamaya açılmaz;
anon/authenticated rollerine worker RPC yetkisi verilmez.

## Gönderim kuralları ve hata davranışı

- Varsayılan eşikler: **48 saat / 5 gün / 12 gün / 19 gün**. Dördüncü aşamadan sonra gönderim yok.
- Dönem anahtarı `profiles.last_seen_at` değeridir. Yeni aktiflik yeni dönem oluşturur;
  kullanıcının tüm dönemlerindeki son rezervasyon için en az 72 saat aralık yine korunur.
- Otomasyon geç açılmışsa yalnızca zamanı gelmiş en yüksek aşama seçilir.
  Kaçırılmış aşamalar peş peşe gönderilmez. Örneğin 15 günlük pasif kullanıcı üçüncü aşamadan başlar.
- Aynı dönem/aşama benzersizdir; ayar satırının transaction kilidi eşzamanlı rezervasyonu engeller.
- İstanbul 10:00 dahil, 21:00 hariç. Cron UTC `0 7-17 * * *` ile saatte bir çalışır.
  Başlangıçta kapalıdır. SQL ve worker gönderimden önce zaman/ayar kontrolünü tekrar yapar.
- Varsayılan çalışma başına 10, günlük en fazla 100 rezervasyon; bir worker en fazla 45 saniye
  yeni iş alır. Her ağ isteğinin ayrıca zaman aşımı vardır. Boş/kapalı çalışmada FCM/OAuth çağrısı yok.
- Null/gelecek aktiflik, bot, silinmiş/eksik auth hesabı, yasak/askı, mevcut davet tercihi kapalı,
  desteklenmeyen platform, geçersiz veya izni bilinmeyen token hariç tutulur.
- En güncel geçerli cihaz seçilir; bu cihazın izni bilinmiyorsa eski cihazın izni ödünç alınmaz.
- Gönderimden hemen önce aktiflik, hesap durumu, token sahipliği ve izin yeniden kontrol edilir.
  Kontrol ile dış servis çağrısı arasında çok küçük kaçınılmaz bir yarış aralığı vardır;
  dış FCM çağrısı PostgreSQL transaction’ının parçası olamaz.
- FCM `UNREGISTERED` dönerse token özeti geçmişte geçersiz olarak işaretlenir. Mevcut
  davet altyapısının token kaydı değiştirilmez. Sonraki uygun aşamada başka geçerli cihaz seçilebilir.
  `INVALID_ARGUMENT` token silme nedeni değildir; içerik hatası da olabilir.
- Zaman aşımı/bağlantı kopması FCM kabulünden sonra oluşabilir. Bu durumda `unknown` yazılır
  ve aynı aşama otomatik tekrar gönderilmez. Kesilen worker rezervasyonu da aynı şekilde ele alınır.
  Kesin reddedilen aşamalar da otomatik tekrar denenmez; güvenli tarafta kalıp dört aşama sınırı korunur.
  Bu tercih bazı hatırlatmaların atlanmasına yol açabilir; mükerrer gönderimden kaçınmak içindir.
- `accepted`, **FCM’nin isteği kabul etmesi** demektir; teslim/okuma veya uygulamaya dönüş kanıtı değildir.
  Mobil değişiklik olmadan bildirim tıklaması ölçülmez. Bu sürüm dönüşüm metriği iddia etmez.
- Payload normal `notification` title/body içerir. `table_id` yoktur; bildirim uygulamayı normal
  açar ve mevcut oturum/başlangıç akışı çalışır. Yeni ekran yönlendirmesine bağımlı değildir.
  Android’de mevcut `invite_channel` kullanılır; yeni kategori yalnızca SQL/data tarafındadır.
  Kanal kapalıysa aşılmaz. TTL en fazla bir saat ve bugünkü 21:00 sınırına kadardır;
  cihazın bildirimi ne zaman göstereceği kesin olarak garanti edilemez.

## Kurulum — yalnızca ayrıca onaydan sonra

1. Önce staging/test projesinde çalışın. Bu dosya production çalıştırma onayı değildir.
2. Yalnızca `20261028000100_reengagement_notifications.sql` migration’ını uygulayın.
   Toplu `supabase db push` kullanmadan önce bekleyen diğer migration’ları inceleyin.
3. Ayrı bir rastgele en az 32 karakterlik `REENGAGEMENT_CRON_SECRET` oluşturun.
   Edge Function secret olarak kaydedin. Bu anahtarı Flutter/Web Admin’e koymayın.
   Mevcut Firebase secret’larını değiştirmeniz gerekmez.
4. Yalnızca yeni fonksiyonu deploy edin:

   ```sh
   supabase functions deploy process_reengagement_notifications --project-ref YOUR_PROJECT_REF
   ```

   Yeni fonksiyonun `verify_jwt=false` ayarı yalnızca bu endpoint içindir: kod her istekte
   `x-reengagement-secret` başlığını doğrular. Public API key veya kullanıcı JWT’si yetki sağlamaz.
5. Supabase Vault’ta iki secret oluşturun; değerleri SQL sonuçlarına/loglara basmayın:
   `okeyix_reengagement_project_url` = `https://YOUR_PROJECT_REF.supabase.co`,
   `okeyix_reengagement_cron_secret` = Edge’deki özel anahtarın aynısı.
6. `20261028000200_reengagement_cron.sql` migration’ını uygulayın. Mevcut pg_cron,
   pg_net ve Vault kullanılır. Job aynı transaction’da pasif hale getirilir; kurulumda HTTP çalışmaz.
7. Aşağıdaki kapalı durum kontrollerini yapın. Cron’u açmadan izin kaynağı ve test sonuçları onaylanmalı.

```sql
SELECT enabled,dry_run,thresholds_hours,cooldown_hours,batch_size,daily_limit
FROM okeyix_reengagement_private.settings;
SELECT jobname,schedule,active FROM cron.job WHERE jobname='okeyix-reengagement-hourly';
SELECT public.okeyix_reengagement_worker('preview'); -- SQL Editor / postgres
```

Cron açılırsa günde 11 zamanlanmış SQL kontrolü olur (30 günde 330).
Her kontrol Edge çağırmaz; uygun kullanıcı yoksa SQL’de sonlanır.
Proje planı ve diğer işlerin toplam kotası Dashboard’dan izlenmeli; bu çalışma planınızı değiştirmez.

## SQL Editor yönetimi

Önizleme ve nedenler (hiçbir gönderim yapmaz):

```sql
SELECT public.okeyix_reengagement_worker('preview');
SELECT reason,count(*) FROM okeyix_reengagement_private.candidates() GROUP BY reason;
```

Metin değiştirme / daha uzun eşikler (kısa eşikler ve 72 saat altı aralık kabul edilmez):

```sql
UPDATE okeyix_reengagement_private.settings
SET messages=jsonb_set(messages,'{0,body}',to_jsonb('Bir el Okeyix oynamaya ne dersin?'::text))
WHERE id;
-- Diğer aşama metin indeksleri: 1, 2, 3. Dört mesaj korunmalı.
-- UPDATE ... SET thresholds_hours=ARRAY[48,120,288,456] WHERE id;
```

İzin kaydı **yalnızca kullanıcı hatırlatmayı kabul etmiş ve o cihazın platform izni bağımsız
olarak doğrulanmışsa** eklenir. Aşağıdaki örnek herkesi izinli yapmaz; UUID değiştirilmezse hata verir.
Doğrulanmış bilgiyi en fazla 30 gün saklar; token yenilenirse tekrar doğrulama gerekir.
OS izin durumunu bu SQL ile tespit etmiş olmazsınız.

```sql
INSERT INTO okeyix_reengagement_private.permissions
 (user_id,device_id,token_hash,reminders_allowed,platform_permission,verified_at,expires_at,evidence)
SELECT user_id,id,encode(sha256(convert_to(btrim(push_token),'UTF8')),'hex'),
 true,'granted',statement_timestamp(),statement_timestamp()+interval '7 days',
 'GERCEK_DOGRULAMA_KAYNAGINI_BURAYA_YAZIN'
FROM public.user_devices
WHERE id='DOGRULANMIS_CIHAZ_SATIRI_UUID'::uuid
 AND user_id='DOGRULANMIS_KULLANICI_UUID'::uuid
 AND nullif(btrim(push_token),'') IS NOT NULL
ON CONFLICT(user_id,device_id) DO UPDATE SET token_hash=excluded.token_hash,
 reminders_allowed=excluded.reminders_allowed,platform_permission=excluded.platform_permission,
 verified_at=excluded.verified_at,expires_at=excluded.expires_at,evidence=excluded.evidence;
```

İzin iptali:

```sql
UPDATE okeyix_reengagement_private.permissions SET reminders_allowed=false WHERE user_id='KULLANICI_UUID'::uuid;
```

Sonuçlar ve hata kayıtları — token/FCM ham yanıtı saklanmaz:

```sql
SELECT id,user_id,stage,status,reserved_at,dispatched_at,finished_at,http_status,error_code
FROM okeyix_reengagement_private.deliveries ORDER BY reserved_at DESC LIMIT 100;
SELECT status,count(*) FROM okeyix_reengagement_private.deliveries GROUP BY status;
SELECT jobid,status,start_time,end_time,return_message FROM cron.job_run_details
WHERE jobid=(SELECT jobid FROM cron.job WHERE jobname='okeyix-reengagement-hourly')
ORDER BY start_time DESC LIMIT 20;
```

OAuth/secret/DB gibi rezervasyon öncesi hatalar Edge Logs/HTTP 503 üzerinden izlenir;
alıcıya ait FCM hataları `deliveries` içinde ayrı tutulur. Cron HTTP isteğini kuyruğa alır;
Cron SQL’inin başarılı olması Edge’in veya bildirimin başarılı olduğu anlamına gelmez.
`net._http_response` içindeki status/error kayıtları incelenebilir; gizli anahtar içeren
istek başlıkları veya Vault değerleri paylaşılmamalı.

## Açma / kapatma — ayrıca onay gerektirir

**Açma işlemi 28 Ekim 2026'da kullanıcının açık canlıya alma onayıyla uygulandı.** Gerçek gönderim ancak
izinli kullanıcı varsa, üç anahtar birlikte açıkken ve saat aralığında olur.

```sql
BEGIN;
UPDATE okeyix_reengagement_private.settings SET enabled=true,dry_run=false WHERE id;
SELECT cron.alter_job(jobid,active:=true) FROM cron.job WHERE jobname='okeyix-reengagement-hourly';
COMMIT;
```

Kapatma; işlemdeki son dış çağrı geri alınamaz, sonraki rezervasyon/yetkilendirme durur:

```sql
BEGIN;
UPDATE okeyix_reengagement_private.settings SET enabled=false,dry_run=true WHERE id;
SELECT cron.alter_job(jobid,active:=false) FROM cron.job WHERE jobname='okeyix-reengagement-hourly';
COMMIT;
```

Geçmişi silmeyin: tekillik, dört aşama ve cooldown koruması geçmişe dayanır.
Sistem kapatılıp açıldığında geçmiş korunur. Zamanlanmış iş silinse bile tabloları silmeyin.

## Test yöntemi ve yapılan kontroller

Hiç FCM erişimi olmadan:

```sh
node --test test/reengagement_notifications_test.mjs test/reengagement_endpoint_test.mjs
```

Yerel PostgreSQL’de `okeyix_reengagement_test` adında ayrı, boş test veritabanında sırasıyla:

```sh
psql -X -v ON_ERROR_STOP=1 -d okeyix_reengagement_test -f test/sql/reengagement_fixture.sql
psql -X -v ON_ERROR_STOP=1 -d okeyix_reengagement_test -f supabase/migrations/20261028000100_reengagement_notifications.sql
psql -X -v ON_ERROR_STOP=1 -d okeyix_reengagement_test -f test/sql/reengagement_regression.sql
```

Fixture ve regression başka veritabanı adında çalışmayı reddeder. Regression transaction’ı
geri alınır; yalnızca bu yerel transaction’da sunucu saati sabitlenir. Migration’a test saat parametresi eklenmez.
Fixture için postgres, anon, authenticated ve service_role test rolleri gerekir.

Yerel paralellik testi (PowerShell, localhost:55447):

```powershell
$env:REENGAGEMENT_LOCAL_PG='1'
node --test test/reengagement_concurrency_test.mjs
Remove-Item Env:REENGAGEMENT_LOCAL_PG
```

Bu test sekiz ayrı PostgreSQL oturumunun yalnızca bir rezervasyon ve bir gönderim
yetkilendirmesi alabildiğini kontrol eder. Hiçbir FCM çağrısı yapmaz.

Staging’de sonraki doğrulama: önce kapalı/önizleme, sonra yalnızca bağımsız onayı
doğrulanmış test hesabı/cihazı ile tek uygun alıcı ve `batch_size=1,daily_limit=1`.
Gerçek test bildirimi için ayrıca onay alınmalı. HTTP çağrısının gövdesi `{"mode":"preview"}`
veya gönderim için `{"mode":"process"}` olur; özel başlık gerekir. `process` uygun bütün
alıcıları tarar, alıcı filtresi varsaymayın. Production aktifliklerini/eski gönderimleri test için değiştirmeyin.

28 Ekim 2026'da gerçek Supabase üzerinde migration kurulumu, Vault/Edge secret eşleştirmesi,
Edge deploy, yetkili önizleme/çalışma çağrısı ve aktif Cron kaydı doğrulandı.
İlk zamanlanmış çalışma henüz gerçekleşmemişti; uygun alıcı 0 olduğu için gerçek FCM/APNs
teslimi veya telefon tıklama akışı doğrulanmadı. Başarılı deploy ayrı bir Deno type-check
çalıştırıldığı anlamına gelmez. Yerel testler/kurulum doğrulaması teslim garantisi değildir.

Yerel sonuçlar: **18 Node testi, 40 PostgreSQL kontrolü ve sekiz oturumlu 1 paralellik testi geçti.**
Endpoint testleri gerçek handler kaynağını Node ile TypeScript sözdiziminden arındırıp
yerel adapterlerle çalıştırır; Supabase SDK/Deno ağ entegrasyonunun yerini tutmaz.

Resmî kaynaklar:
[Supabase Cron + Edge + Vault](https://supabase.com/docs/guides/functions/schedule-functions),
[FCM hata kodları](https://firebase.google.com/docs/cloud-messaging/error-codes),
[token yönetimi](https://firebase.google.com/docs/cloud-messaging/manage-tokens).
