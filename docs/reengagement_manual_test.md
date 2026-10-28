# Yalnızca kendi telefonuna test bildirimi

Durum: kod hazır, **production kurulumu/deploy ve canlı gönderim yapılmadı**.
Bu belge gönderim onayı değildir. Kurulum ile gerçek gönderim ayrı adımlardır.

Test, otomasyonun `enabled` veya `dry_run` değerlerini okumaz/değiştirmez, Cron çağırmaz.
48 saat pasiflik koşulu ve otomasyonun gönderim saatleri testte aranmaz.
Flutter, Web Admin, mevcut davet fonksiyonu, FCM/APNs kurulumu değişmez.

## Nasıl sınırlandırılıyor?

- Ayrı endpoint: `send_reengagement_test`.
- HTTP için ayrı en az 32 karakterlik gizli anahtar: `REENGAGEMENT_TEST_SECRET`.
- Edge → SQL için farklı `REENGAGEMENT_TEST_RPC_SECRET`; SQL’de yalnızca SHA-256 özeti
  saklanır. `service_role` tek başına test kaydını tüketemez.
- Hedef kullanıcı ve **tek cihaz satırı** sunucuda sabit: `REENGAGEMENT_TEST_USER_ID`,
  `REENGAGEMENT_TEST_DEVICE_ID`. İstekten alıcı/token değiştirmek mümkün değildir.
- SQL Editor’da hazırlanan kayıt önce `draft` olur; hiçbir gönderim izni içermez.
- **Ayrı gönderim onayından sonra** SQL Editor’da 15 dakikalık tek kullanımlık test onayı verilir.
- Token özeti ve cihazın hesap sahipliği gönderim anında yeniden kontrol edilir.
  Token/sahiplik değişirse gönderim yapılmaz. Başka cihaza otomatik geçilmez.
- Aynı kayıt bir kez tüketilir. İkinci HTTP çağrısı yeni bildirim oluşturmaz.
- Mevcut `allow_game_invites=false` engeli testte de korunur; test uğruna açılmaz.
  Bot/engelli/silinmiş hesap elenir. Platform izni bilinmiyorsa biliniyor gibi gösterilmez.
- Bildirim tek token’a gider; topic, toplu gönderim veya bütün kullanıcıları tarama yoktur.
- Sonuç yalnızca tüketme sırasında verilen tek kullanımlık makbuzla yazılır.
  Makbuz HTTP cevabına veya loglara konmaz; ayrı test geçmişi otomasyonu etkilemez.

## 1. Telefonu belirle — salt okunur

Önce kendi hesabının UUID’sini belirle. Şu dosyada `NULL::uuid` yerine kendi UUID’ni
yazıp Supabase SQL Editor’da çalıştır:

`docs/reengagement_test_devices.sql`

`device_row_id`, `platform`, `device_model`, son cihaz tarihi ve token varlığı görünür.
**En güncel cihaz her zaman senin elindeki telefon olmayabilir.** Birden fazla cihaz varsa
model/platform ile doğru satırı seç. `device_row_id`, `user_devices.id` değeridir;
`user_devices.device_id` metni değildir. Ham tokenı veya Firebase gizli anahtarını paylaşma.

## 2. Test altyapısını kur — yalnızca kurulum onayından sonra

Bu tek cihaz testi için otomasyonun 001/002 migration’larını kurmaya gerek yok.
**Yalnızca** `20261028000300_reengagement_test_push.sql` migration’ı uygulanır.
İki private tablo (`tickets`, `authorization`) ve service_role + ek RPC anahtarı gerektiren
`public.okeyix_reengagement_test_worker(...)` oluşturur. Cron oluşturmaz.
`authorization.rpc_secret_hash` başlangıçta NULL olduğundan SQL çağrıları da kapalı başlar.
Toplu `supabase db push` diğer bekleyen migration’ları da uygulayabileceği için kullanılmamalı.

Edge Function Secrets alanına şu değerleri ekle:

| Secret | Değer |
|---|---|
| `REENGAGEMENT_TEST_SECRET` | Yeni, rastgele, en az 32 karakter; Cron anahtarından farklı |
| `REENGAGEMENT_TEST_RPC_SECRET` | HTTP test anahtarından farklı, rastgele 32–256 karakter; sadece Edge kullanır |
| `REENGAGEMENT_TEST_USER_ID` | Yalnızca kendi hesap UUID’n |
| `REENGAGEMENT_TEST_DEVICE_ID` | Yalnızca seçtiğin `user_devices.id` UUID’si |

Mevcut `FIREBASE_SERVICE_ACCOUNT_JSON`, varsa `FIREBASE_PROJECT_ID`,
`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` kullanılır; değiştirilmez.

RPC anahtarını SQL Editor’a ham olarak yazma. Windows PowerShell’de aşağıdaki yerel
komut yeni anahtarı panoya koyar, terminale **yalnızca SHA-256 özetini** yazar:

```powershell
node -e "const c=require('node:crypto');const s=c.randomBytes(32).toString('hex');const r=require('node:child_process').spawnSync('clip.exe',[],{input:s});if(r.status!==0)process.exit(1);process.stdout.write(c.createHash('sha256').update(s).digest('hex')+'\n');"
```

Panodaki değeri yalnızca `REENGAGEMENT_TEST_RPC_SECRET` secret alanına yapıştır.
Ardından panoyu temizle. Terminalde çıkan 64 haneli özeti aşağıdaki yere yaz:

```sql
UPDATE okeyix_reengagement_test_private.authorization
SET rpc_secret_hash='URETILEN_64_HANELI_SHA256_OZETI'
WHERE id
RETURNING rpc_secret_hash IS NOT NULL AS configured;
```

Bu ayar bildirim göndermez ve taslak kayıtları onaylamaz. RPC anahtarı tarayıcıdaki
HTTP Test başlığına girilmez; Edge onu kendi ortamından SQL’e ekler.

Yalnızca yeni endpoint deploy edilir:

```sh
supabase functions deploy send_reengagement_test --project-ref YOUR_PROJECT_REF
```

`supabase/config.toml` içindeki `verify_jwt=false` bu endpoint için özel gizli anahtar
kontrolüne karşılık gelir. Genel API key veya kullanıcı JWT’si test yetkisi sağlamaz.
Ortak FCM yardımcı kodu bundle’a dahil edilir; otomasyon endpoint’ini deploy etmek gerekmez.

## 3. Test kaydını taslak oluştur — gönderim yapmaz

Aşağıdaki UUID yerlerini yalnızca seçtiğin kullanıcı/cihazla değiştir. Ham token gerekmez.

```sql
INSERT INTO okeyix_reengagement_test_private.tickets(user_id,device_id,token_hash)
SELECT user_id,id,encode(sha256(convert_to(btrim(push_token),'UTF8')),'hex')
FROM public.user_devices
WHERE user_id='KENDI_KULLANICI_UUID'::uuid
  AND id='KENDI_CIHAZ_SATIRI_UUID'::uuid
  AND lower(platform) IN ('ios','android')
  AND nullif(btrim(push_token),'') IS NOT NULL
RETURNING id AS ticket_id,user_id,device_id,status;
```

Sıfır satır dönerse dur; farklı kullanıcı veya token seçerek devam etme.

Supabase Dashboard → Edge Functions → `send_reengagement_test` → Test:

- Method `POST`
- Header `Content-Type: application/json`
- Header `x-reengagement-test-secret: <yalnızca test anahtarı>`
- Gövde:

```json
{"mode":"preview","ticket_id":"TASLAK_KAYDIN_UUID"}
```

Beklenen sonuç: `mode=no_send`, `ready=false`, `status=draft`.
`send` yazılsa bile taslak kayıt gönderim yapmaz. Önizleme Google/FCM çağırmaz.
Anahtar/token içeren ekran görüntülerini veya logları paylaşma.

## 4. GERÇEK GÖNDERİM — ayrıca kullanıcı onayı gelmeden ÇALIŞTIRMA

Önce hedef UUID, cihaz modeli ve tek bildirim metni gözden geçirilir:
başlık **Okeyix test bildirimi**, içerik **Bu bildirim yalnızca onayladığın cihaz için gönderildi.**
Telefonun bildirim ayarında Okeyix’e izin verildiğini sen kontrol edebilirsin;
sunucu bunu otomatik doğrulayamaz. Bu özel test onayı genel hatırlatma onayı sayılmaz.

Onay geldikten sonra yalnızca ilgili taslağı etkinleştir:

```sql
UPDATE okeyix_reengagement_test_private.tickets
SET status='approved',test_consent_confirmed=true,
    approved_at=statement_timestamp(),expires_at=statement_timestamp()+interval '15 minutes'
WHERE id='ONAYLANAN_TICKET_UUID'::uuid
  AND user_id='KENDI_KULLANICI_UUID'::uuid
  AND device_id='KENDI_CIHAZ_SATIRI_UUID'::uuid
  AND status='draft'
RETURNING id,status,expires_at;
```

Bu UPDATE tek başına gönderim yapmaz. 15 dakika içinde aynı endpoint’e şu gövdeyle
**bir** POST yapılır (aynı özel test başlığıyla):

```json
{"mode":"send","ticket_id":"ONAYLANAN_TICKET_UUID"}
```

Tek token’a en fazla bir FCM isteği gönderilir. Otomatik tekrar deneme yoktur.
Normal `notification` payload’u ve mevcut `invite_channel` kullanılır; yeni mobil rota,
`table_id`, yeni kanal veya mobil güncelleme gerekmez. TTL beş dakikadır.
Bildirim tıklanınca uygulama normal açılır. İşletim sistemindeki izin/kanal sessizliği aşılmaz.
İlk teslim testi için uygulamayı arka plana al; ön planda uygulamanın mevcut sunum davranışı geçerlidir.

## 5. Sonuç raporu

Endpoint HTTP 200 dönmesi tek başına FCM kabulü değildir. JSON `status`, `code`,
`http_status`, `result_persisted` alanlarına bakılır:

| Sonuç | Yorum / sonraki kontrol |
|---|---|
| `accepted / FCM_ACCEPTED / 200` | FCM isteği kabul etti; telefonun gösterdiği ayrıca doğrulanır |
| `invalid_token / UNREGISTERED` | Token artık kayıtlı değil; mevcut uygulamadan yeniden kayıt sonrası yeni test onayı gerekir |
| `INVALID_ARGUMENT` veya HTTP 400 | İstek/payload geçersiz; tokenı otomatik silme |
| `SENDER_ID_MISMATCH` | Token ile Firebase projesi farklı olabilir |
| `THIRD_PARTY_AUTH_ERROR` | APNs gibi üçüncü taraf kimlik doğrulamasını incele; otomatik kurulum değişikliği yapılmaz |
| HTTP 401 / 403 | Google yetkisi, service account ve Firebase projesini kontrol et |
| HTTP 429 / 5xx | Kota/servis sorunu; bu kayıt otomatik tekrar gönderilmez |
| `unknown / NETWORK_OUTCOME_UNKNOWN` | FCM kabulünden sonra ağ kopmuş olabilir; tekrar gönderme |
| `result_persisted=false` | FCM sonucu biliniyor fakat SQL’e yazılamadı; aynı kaydı tekrar gönderme |
| `TICKET_TARGET_MISMATCH` | Kayıt, sunucuda sabitlenen kullanıcı/cihazla eşleşmiyor |
| `TOKEN_CHANGED / DEVICE_UNAVAILABLE` | Token veya cihaz sahipliği değişti; yeni hedef kontrolü/onayı gerekir |
| `EXISTING_PREFERENCE_DISABLED` | Mevcut davet tercihi kapalı; otomatik açılmaz |
| `GOOGLE_AUTH_OR_FIREBASE_CONFIGURATION_FAILED` | Google OAuth/Firebase secret yapılandırması başarısız; FCM çağrısına geçilmedi |

Geçmiş:

```sql
SELECT id,user_id,device_id,status,created_at,approved_at,expires_at,
       dispatched_at,finished_at,http_status,error_code
FROM okeyix_reengagement_test_private.tickets
WHERE id='TEST_TICKET_UUID'::uuid;
```

`dispatching` durumunda worker kesilmişse sonuç bilinmiyor sayılır. Aynı kayıt bir daha
tüketilemez; teslim durumu araştırılmadan yeni kayıt açıp tekrar göndermeyin.
FCM ham yanıtı, token ve Google JWT loglara/sonuca yazılmaz. FCM kabulü telefonun teslim/okuma
kanıtı değildir. Kurulum veya gerçek gönderim yapılmadığından henüz gerçek FCM sonucu yoktur.

Test bitince `REENGAGEMENT_TEST_SECRET` değerini kaldırarak endpoint’i erişime kapatabilirsin.
Gönderilmemiş onayı geri çekmek için yalnızca ilgili `approved` kaydın `expires_at` değerini
`approved_at+interval '1 second'` yap; onay zamanından bir saniye geçtikten sonra geçersiz olur.
Gönderilmiş veya ağda bekleyen bir FCM isteği geri alınamaz. Test endpoint’ini silebilirsin;
eski kayıtların yeniden onaylanmaması ve tekrar engeli için geçmişi koru.

Son güvenlik raporu ve güvenli operasyonel geri alma:
[reengagement_test_security_review.md](reengagement_test_security_review.md),
[reengagement_test_rollback.sql](reengagement_test_rollback.sql).

## Davet bildirimi çalışan cihazlara otomatik hatırlatma mümkün mü?

**Teknik olarak evet:** aynı FCM HTTP v1 altyapısıyla normal title/body bildirimi,
mobil kod değiştirilmeden mevcut token’a gönderilebilir. Yeni deep link gerekmiyor.

**Mevcut kayıtlar tek başına kullanıcı tercihine uygun genel gönderimi kanıtlamıyor:**

1. `user_devices.push_token` adresleme bilgisidir. `last_seen` cihaz kaydının güncelliğidir;
   ikisi de OS izni veya hatırlatma onayı değildir.
2. `profiles.last_seen_at` pasifliği belirler. Cihazın token güncelleme zamanı pasiflik yerine kullanılmaz.
3. `allow_game_invites=false` gönderimi engellemek için korunabilir. `true`, yalnızca oyun daveti
   tercihidir; kendiliğinden pazarlama/geri kazanım onayına dönüştürülmez.
4. Davet bildiriminin geçmişte görünmüş olması o anda teknik teslimin çalıştığını gösterir;
   bugünkü izin durumunu veya başka amaçlı bildirim tercihini kanıtlamaz.
5. Bağımsız ve kullanıcıya açık bir kanaldan hatırlatma onayı alınmışsa bunu Supabase’de
   kaydetmek mobil güncelleme gerektirmez. İzin bilinmiyorsa otomatik hatırlatma gönderilmez.
   Mevcut verilerden toplu izinli kayıt üretmek güvenli çözüm değildir.
6. OS izninin sonradan değiştiğini sunucudan anında öğrenmek mümkün değildir; cihazın kendi
   izinleri ayrıca uygulanır. Genel otomasyon için bu veri sınırlaması açıkça kabul edilmeli;
   yalnızca token var diye `granted` yazılmamalı.

Bu manuel test, senin belirlediğin telefona açık onayınla tek bildirim gönderilmesini sağlar;
diğer oyuncuların izin durumuna ilişkin bir varsayım yapmaz.

Kaynaklar: [FCM token yönetimi](https://firebase.google.com/docs/cloud-messaging/manage-tokens),
[FCM hata kodları](https://firebase.google.com/docs/cloud-messaging/error-codes).

## Yerel doğrulama

```sh
node --test test/reengagement_manual_test.mjs
```

`test/sql/reengagement_manual_test.sql`, yalnızca `okeyix_reengagement_test` yerel veritabanında,
fixture + test migration kurulduktan sonra çalışır ve transaction’ı geri alır.
**16 Node testi, 28 PostgreSQL kontrolü ve 4 migration/geri alma/paralellik testi geçti.** Ağ istekleri sahte adapterlerle sınandı;
gerçek FCM çağrısı yapılmadı. Supabase deploy/Deno ve telefon teslimi henüz sınanmadı.
