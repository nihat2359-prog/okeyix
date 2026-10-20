# Arkadaş daveti

Canlı Supabase'e hiçbir SQL uygulanmadı. Yeni migration:
`supabase/migrations/20261021000100_friend_referrals.sql`.

## Uygulama

1. Kalıcı istatistik tabloları, istatistik event store/capture/projector ve pg_cron
   kurulu olmalı (mevcut 001–003 istatistik migration'ları).
2. Yeni migration'ı önce staging SQL Editor'de postgres olarak tek sefer uygula.
   Yeni tablolar, üç authenticated API ve dakikalık cron işi oluşturur.
3. Staging'de iki insan hesabıyla kod kullanımı ve 10 tamamlanmış el testi yap.
   Ardından aynı migration üretime uygulanabilir; Flutter sürümünü bundan sonra yayınla.
   Native WhatsApp köprüsü nedeniyle uygulamayı yeniden derlemek gerekir.

## İşleyiş

- Kalıcı 12 karakterli kod, hesabın davet ekranını ilk açışında oluşturulur.
- JWT'deki oyuncu yalnız kendi kodunu ve kendi davet listesini okuyabilir.
- Tek kullanımlık kod kabulü oyuncu satırı kilidi ve unique invitee ile korunur.
- Cron yalnız kalıcı, tamamlanmış, tüm katılımcıları insan olan elleri sayar.
  Bitiş zamanı kod kabulünden sonra olmalı. Önceden bitmiş bir el sonradan
  istatistiğe yansıtılsa bile sayılmaz. 2 ve 4 katılımcılı eller desteklenir.
- İlerleme/ödül istemciden alınmaz. İstatistik projector'ünün ardından davet cron'u
  çalışır; ilerleme ve ödeme anlık değildir. Ekran açılışı, uygulamaya dönüş ve
  Yenile ile güncellenir; mobil polling yoktur.
- Her cron turu 100 bekleyen daveti adil `checked_at` sırasıyla kontrol eder.
  Yük arttığında cron kapasitesi/işlem süresi izlenmeli; gecikme bu kuyruğa da bağlıdır.
- Aynı davet satırı kilitlenir; iki profil UUID sırasıyla kilitlenir. İki adet
  1.000.000 coin bakiyesi, iki `friend_referral` / `credit` / `system` wallet
  kaydı, iki unique ödeme makbuzu ve tamamlandı işareti tek transaction içindedir.
  Hata halinde iki ödeme de geri alınır; davet hata koduyla tekrar denenebilir.
  NULL bakiye veya integer taşmasında kısmi/varsayımsal ödeme yapılmaz.
- Mevcut oyun, sayaçlar, mağaza ve istatistik yazıcı RPC'leri değiştirilmez.
  Davet kayıtları oyun masasına bağlı FK içermez; masa temizliği bunları silemez.
- WhatsApp/WhatsApp Business Android'de, WhatsApp iOS'ta mevcut native paylaşım
  kanalından açılır. Yüklü değilse kodu kopyalama seçeneği korunur.
  Mesajda kullanıcı tarafından sağlanan Google Play ve App Store bağlantıları,
  kod, iki tarafın ödülü ve 10 insanlı el koşulu bulunur. Alıcı cihazına uygun
  mağazayı seçer; otomatik yönlendirme veya link üzerinden davet takibi yoktur.
- Projede ortak çok dil kataloğu bulunmuyor. Bu özelliğin metinleri
  `InviteStrings` içinde, cihaz diline göre Türkçe/İngilizce ve diğer dillerde
  İngilizce fallback ile tutulur. Mevcut diğer ekranların dili değiştirilmez.

## Salt okunur kurulum kontrolü (SQL Editor)

```sql
SELECT jsonb_build_object(
  'cron', (SELECT jsonb_agg(jsonb_build_object('name',jobname,'active',active,'schedule',schedule))
    FROM cron.job WHERE jobname='okeyix-friend-referrals'),
  'invitations',(SELECT count(*) FROM okeyix_referral_private.invitations),
  'rewarded',(SELECT count(*) FROM okeyix_referral_private.invitations WHERE rewarded_at IS NOT NULL),
  'retrying',(SELECT count(*) FROM okeyix_referral_private.invitations WHERE rewarded_at IS NULL AND error_code IS NOT NULL),
  'payment_receipts',(SELECT count(*) FROM okeyix_referral_private.payments)
);
```

## Yerel doğrulama

- `test/friend_invite_test.dart`: landscape, klavye, kod kilidi, hata/yeniden dene,
  ödül, WhatsApp mesajı ve dar lobi menüsü.
- `test/statistics/friend_referrals.sql`: localhost test DB korumalı, sonunda
  ROLLBACK; kabul, filtreleme, iki ödeme atomikliği, retry ve yetki testleri.
- `test/statistics/friend_referrals_concurrency.ps1`: yalnız `127.0.0.1:55439`,
  `okeyix_stat_test_*` isimli boş test DB; committed sentetik fixture kullanır.
  Tek seferlik çalıştırılır; üretimde kullanılmaz.
- Windows yerel PostgreSQL testinde mevcut canlı envanterden üretilmiş
  `statistics_fixture.sql` kullanıldı. pg_cron Windows test sunucusunda bulunmadığı
  için sadece extension kontrolü ve cron.schedule satırı yerel kopyada çıkarıldı;
  migration'ın uygulama fonksiyonları PostgreSQL'de derlendi ve çalıştırıldı.
  Gerçek pg_cron kurulumu ve cihazdaki WhatsApp teslimi staging/device testidir.
  iOS derlemesi bu Windows ortamında yapılamaz.
