# 30 Ekim 2026 — kotasız otomasyon ve yenilenme duyurusu

Kullanıcı, günlük 100 sınırının kaldırılmasını ve tüm uygun cihazlara şimdi bir
defalık yenilenme duyurusu gönderilmesini açıkça istedi.

Mesaj:

> **Okeyix yenilendi! 🀄**
>
> Yeni Okeyix seni bekliyor! Uygulamayı güncelle, masaya katıl ve okey keyfine yeniden başla.

## Uygulanan değişiklik

- `20261030000100_reengagement_unlimited_campaign.sql` production'a uygulandı.
  SHA-256: `72d9918f9ec1e44fbebfab8481062c57a58088b047d01f44a38cd2d9a0d0f301`.
- `settings.daily_limit` kaldırıldı; günlük kullanıcı/deneme sayısı sınırı yok.
- Job 18 (`okeyix-reengagement-hourly`) adı ve kimliği korundu; takvim artık
  `* 7-17 * * *` GMT: İstanbul 10:00–20:59 arasında **her dakika**.
- Normal hatırlatmalar 48 / 120 / 288 / 456 saat pasiflik eşiklerini, 72 saat
  aralığı ve hesap başına dönem/aşama tekilliğini korur. Normal akış son geçerli
  cihazı seçer. Bir istekte 25 deneme yapılır; sonraki dakika devam eder.
- `process_reengagement_notifications` güncellendi; mevcut `verify_jwt=false`
  ayarı ve zorunlu özel `x-reengagement-secret` kontrolü korundu.
  Canlı sürüm **3**, durum **ACTIVE**; kaynak paket SHA-256:
  `c13a1e25868b1612ec906b72e3de6269a3411ce3e9b977bfeacaf9f52ed56c89`.
  Mevcut davet fonksiyonunun kaynak özeti aynı kaldı:
  `5bf8a3bd31cb1dac82c87a4fb560cef591e08db0fa9a3f43856895b21779eae4`.
- Yenilenme duyurusu `okeyix-renewal-20261030` anahtarlı ayrı kampanyadır.
  Aktif/pasif tüm uygun hesapların bütün iOS/Android cihazları kapsanır.
  En son token sahibinin tercihi esas alınır; aynı token kampanyada tekilleştirilir.
- Bildirim tercihi kapalı, bot, engelli, askıya alınmış, silinmiş/eksik hesaplar
  ve önceden `UNREGISTERED` olduğu doğrulanmış tokenlar hariçtir.
- Hazırlanan ilk liste: **2.090 oyuncu, 2.097 benzersiz cihaz tokenı**; Admin'in
  iPad'i de listede. Gönderim anında uygunluğu değişen satırlar iptal edilir.
- Ham token kampanya tablosuna kopyalanmaz; cihaz satırı ve SHA-256 özeti tutulur.
- Beş cihazlık gruplar tek işlemle ayrılır, FCM'e paralel gönderilir ve sonuçlar
  grupla kaydedilir. Bir Edge isteğinde en fazla 20 grup/100 cihaz ve 45 saniye
  bütçesi vardır. **Bu günlük kota değildir**; sonraki istek kaldığı yerden devam eder.
- Ağ sonucu belirsiz gönderimler otomatik tekrarlanmaz. Yarım kalan gruplar beş
  dakika sonra `unknown` olur; kampanya tekrar açılınca gönderilmiş cihazlar yenilenmez.
- Kampanya sırasında normal akış bekler. Duyuru denemesi yapılan hesaba 72 saat
  boyunca normal hatırlatma gitmez. Süre sonunda pasiflik eşikleri tekrar değerlendirilir.
- Kampanya TTL'si 24 saat, normal hatırlatmanın TTL/saat penceresi mevcut davranıştır.
- Kampanya 48 saat sonra durur; normal otomasyon devam eder. Biten kampanyanın
  gönderim geçmişi silinmez ve aynı anahtarla yeni kampanya oluşturulamaz.

## İzleme

```sql
SELECT c.campaign_key,c.status,d.status,count(*)
FROM okeyix_reengagement_private.campaigns c
JOIN okeyix_reengagement_private.campaign_deliveries d ON d.campaign_id=c.id
WHERE c.campaign_key='okeyix-renewal-20261030'
GROUP BY c.campaign_key,c.status,d.status;

SELECT error_code,http_status,count(*)
FROM okeyix_reengagement_private.campaign_deliveries
WHERE campaign_id=(SELECT id FROM okeyix_reengagement_private.campaigns
  WHERE campaign_key='okeyix-renewal-20261030')
GROUP BY error_code,http_status;
```

`accepted`, Firebase'in kabulüdür; cihazda gösterim veya okunma kanıtı değildir.
`invalid_token/UNREGISTERED` cihazın bu kayıt adresinin artık geçersiz olduğunu
gösterir. Cihaz uygulamayı açıp yeni token kaydederse yeni token kullanılabilir.
OS/kanal izinleri bu çalışma ile değiştirilmez.

Yalnızca kampanyayı durdurmak (işlemdeki FCM çağrıları geri alınamaz):

```sql
UPDATE okeyix_reengagement_private.campaigns SET status='paused'
WHERE campaign_key='okeyix-renewal-20261030' AND status='running';
```

Tüm otomasyonu durdurmak için ayrıca mevcut settings enabled/dry_run anahtarlarını
kapatıp job 18'i `cron.alter_job` ile devre dışı bırakın. Duyuru geçmişini silmeyin.

## Doğrulama

- 45 çevrimdışı Node kontrolü geçti: gerçek endpoint, kampanya gönderim grupları,
  normal akış ve bağımsız manuel testin mevcut davranışı.
- İzole yerel PostgreSQL'de 23 regression kontrolü geçti: günde 105 rezervasyon,
  iki cihaz, token tekilliği/sahipliği, tercihler, token değişimi, kampanya bitişi,
  cooldown, sunucu dışı erişim engelleri.
- Sekiz eşzamanlı yerel işçiyle her tokenın yalnızca bir kez ayrıldığı ve
  sonuçların yalnızca bir kez kaydedildiği doğrulandı.
- Yerel PostgreSQL testindeki Cron/HTTP fonksiyonları ağ erişimi yapmayan mock'lardır.
- Ayrı `deno check` çalıştırılmadı; Edge deploy ve canlı HTTP/FCM sonuçları ayrıca izlenir.

Komutlar:

```sh
node --test test/reengagement_notifications_test.mjs test/reengagement_endpoint_test.mjs test/reengagement_campaign_test.mjs test/reengagement_manual_test.mjs
```

```powershell
./tool/test_reengagement_campaign.ps1
```

Kaynaklar: [Supabase zamanlanmış Edge fonksiyonları](https://supabase.com/docs/guides/functions/schedule-functions),
[Firebase gönderim API'si](https://firebase.google.com/docs/cloud-messaging/send/admin-sdk).

## Canlı sonuç

Kampanya **30 Ekim 2026, 13:45:51 Türkiye saati** itibarıyla `completed`.
Son doğrulama: **13:46:36 Türkiye saati**.

| Sonuç | Cihaz/token |
|---|---:|
| Firebase kabul etti (`accepted`) | 276 |
| Geçersiz kayıt (`UNREGISTERED`) | 1.800 |
| Gönderim öncesi uygunluk değişti (`cancelled`) | 21 |
| Bekleyen / işlemde / belirsiz / diğer reddetme | 0 |
| Toplam hazırlanan liste | 2.097 |

276 kabul **275 farklı oyuncuya** aittir. Kampanyada mükerrer token **0**.
Admin hesabındaki `iPad15,7` için Firebase kabul zamanı **13:44:03 Türkiye saati**.
Bu kabul cihazın bildirimi gösterdiği/okunduğu anlamına gelmez.

Normal worker'ın canlı `preview` sonucu `enabled=true`, `dry_run=false`;
Cron job 18 aktif ve dakikalık. Son önizlemede 1.966 hesap kampanya nedeniyle
72 saatlik aralık içindeydi; aktiflik ve geçmiş aşama kontrolleri ayrıca korunuyor.
Kampanyaya özgü kuyruk tamamlandıktan sonra yapılan çağrı yeni kampanya gönderimi
oluşturmaz; geçmiş saklanır. Normal akışta günlük limit alanı veya kontrolü yoktur.
