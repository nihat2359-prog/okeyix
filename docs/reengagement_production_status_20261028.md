# Geri kazanım otomasyonu — canlı kurulum kaydı

**Sonraki değişiklik:** [30 Ekim 2026](reengagement_production_status_20261030.md)
güncellemesi günlük kotayı kaldırdı ve dakikalık zamanlama getirdi. Bu belgedeki
100/gün ve saat başı bilgileri 28 Ekim kurulumunun tarihsel durumudur.

## Güncel politika — 28 Ekim 2026, 04:15 Türkiye saati

Kullanıcının açık talebiyle `20261028000400_reengagement_token_delivery.sql` production'a uygulandı.
SHA-256: `2ade3a1057aafd73e2555fe638b41e0667d08632aca0f9b26150990eb420f37a`.
Doğrulanmış hatırlatma/cihaz izin kaydı zorunluluğu hem aday seçiminden hem gönderim öncesi
kontrolden kaldırıldı. Hiçbir kullanıcıya sahte `granted` kaydı yazılmadı; mevcut izin tablosu silinmedi.
Token izin kanıtı sayılmıyor; bildirim gösterimini telefonun kendi izin/kanal ayarları belirliyor.

Canlı uygun kullanıcı sayısı **2.247**. Otomasyon `enabled=true`, `dry_run=false`; mevcut Cron
korunuyor. 48 saat / 5 / 12 / 19 gün, dört aşama sınırı, 72 saat aralık, tek cihaz,
bot/ban/silinme kontrolleri ve `allow_game_invites=false` engeli değiştirilmedi.
Çalışma başına 10 ve günlük 100 rezervasyon sınırı da korunuyor; tüm uygun kullanıcılar
aynı anda gönderim almaz. Değişiklik sırasında saat aralığı dışında olunduğundan bildirim gönderilmedi.
Flutter, Web Admin, mevcut davet ve test fonksiyonlarına dokunulmadı; Edge yeniden deploy gerekmedi.

**Aşağıdaki bölümler ilk kurulum anının tarihsel kaydıdır; oradaki 0 uygun kullanıcı ve
izin zorunluluğu bilgisi bu yeni politika öncesine aittir.**

Kullanıcının açık canlıya alma talebiyle `okeyix-prod` / `esqpgtedmojrzoftchis`
projesinde uygulandı. Son veritabanı doğrulaması: **28 Ekim 2026 04:04:10 Türkiye saati**
(`2026-10-28 01:04:10 UTC`).

## Uygulanan production migration'ları

| Dosya | Durum | Uygulanan dosyanın SHA-256 özeti |
|---|---|---|
| `20261028000100_reengagement_notifications.sql` | Başarılı | `65a188b04359a8e4dc14a4e55e73fc067f89d1bdaf9f8bf6435b58e37eb22ed2` |
| `20261028000200_reengagement_cron.sql` | Başarılı | `873f3020fd3a7c207ff1fdba6104462d0f06011a2be8036d106dd961317de749` |

SQL, kayıtlı Supabase CLI oturumuyla yetkilendirilen Management API üzerinden uygulandı.
Projede `supabase_migrations.schema_migrations` tablosu yoktu; yalnızca bu dosyaları uygulamak
için başka migration'lar push edilmedi veya yeni CLI geçmiş tablosu oluşturulmadı.
Migration dosyalarındaki `NOT APPLIED` başlıkları hazırlık anındaki yorumlardır;
gerçek uygulama durumu ve uygulanan byte'ların özeti bu kayıttadır.

Cron migration'ının ilk denemesi Supabase postgres rolünün `cron.job` tablosuna doğrudan
UPDATE yetkisi olmadığı için geri alındı. Yalnızca job yönetimi `cron.alter_job` ile
düzeltildi; sonraki uygulama başarılı oldu. Diğer migration'lara veya mevcut job'lara müdahale edilmedi.

Test migration'ı/fonksiyonu bu canlıya alma sırasında uygulanmadı veya deploy edilmedi;
önceden var olan test fonksiyonuna da dokunulmadı.

## Canlı durum

- `process_reengagement_notifications`: **ACTIVE**, sürüm **1**.
- Kaynak paket SHA-256: `3fcf7a28dd5a15c51a47743ce8a7df465c1281c7f405d245cc7d56f457807248`.
- `verify_jwt=false`; özel `x-reengagement-secret` kontrolü kodda uygulanıyor.
- Yeni `REENGAGEMENT_CRON_SECRET` Edge secret'ı ile Vault'taki
  `okeyix_reengagement_cron_secret` eşleşecek şekilde yapılandırıldı.
- Vault proje URL kaydı: `okeyix_reengagement_project_url`.
- Mevcut Firebase secret'ları değiştirilmedi. Gizli değerler rapora/loglara yazılmadı.
- `enabled=true`, `dry_run=false`.
- Eşikler: **48 / 120 / 288 / 456 saat** (48 saat / 5 / 12 / 19 gün).
- Cooldown: **72 saat**; dönem başına en fazla 4 farklı aşama.
- Çalışma başına en fazla 10, günde en fazla 100 rezervasyon sınırı korunuyor.
- Cron: **jobid 18**, `okeyix-reengagement-hourly`, **active=true**, sahibi `postgres`.
- Zamanlama: **`0 7-17 * * *`**, Cron timezone **GMT**; İstanbul **10:00–20:00 saat başları**.
  SQL ve Edge akışı ayrıca 21:00 sınırını kontrol eder.

## Gerçekten bildirim alabilecek kullanıcı sayısı

**0.** Doğrulanmış izin tablosu **0 kayıt** içeriyor. Token'lardan veya oyun daveti
tercihinden onay üretilmedi. İzni bilinmeyen kullanıcılar hariç tutuluyor.

Canlı uygunluk nedenleri (bir kullanıcı için ilk engelleme nedeni):

| Neden | Kullanıcı |
|---|---:|
| Geçerli token var, izin bilinmiyor | 2.247 |
| Geçerli cihaz/token yok | 802 |
| Aktif | 53 |
| Aktiflik tarihi yok | 46 |
| Silinmiş veya eksik hesap | 69 |
| Mevcut davet tercihi kapalı | 11 |

Otomasyon aktiftir fakat mevcut izin verisiyle bildirim göndermez. İzin kaynağı sonradan
doğrulanırsa mevcut kontrollerden geçen kayıtlar uygun olabilir; izin kontrolünü kaldırmak
veya topluca `granted` yazmak bu kurulum kapsamında yapılmadı.

## Çalışma doğrulaması ve sınırı

Özel anahtarlı canlı `preview` başarılı: `enabled=true`, `dry_run=false` ve yukarıdaki
hariç tutulma nedenleri döndü. Canlı `process` çağrısı da başarılı döndü:
`mode=no_send`, `within_send_window=false`. Kontrol anı Türkiye saatiyle 04:04 olduğundan
gönderim penceresi dışındaydı; ayrıca uygun alıcı da yoktu.

Gönderim/rezervasyon geçmişi: **0 kayıt**. İlk zamanlanmış çalışma henüz gerçekleşmedi:
`scheduled_runs=0`. Kurulan takvime göre ilk saat **28 Ekim 2026 10:00 Türkiye saati**.
Cron aktifliği doğrulandı; gelecekteki bir çalışmanın veya gerçek telefon tesliminin başarılı
olduğu iddia edilmiyor.

Mevcut `send_table_invite_push` kaynak paket özeti kurulum öncesi ve sonrası aynı:
`5bf8a3bd31cb1dac82c87a4fb560cef591e08db0fa9a3f43856895b21779eae4`.
Listeleme sürüm sayacı önce 11, son kontrolde 12 görünse de kaynak hash'i ve `updated_at`
değişmedi. Davet fonksiyonuna kod değişikliği/deploy yapılmadı.
Flutter ve Web Admin kodu değiştirilmedi.

Kapatma ve sonuçları izleme komutları için [işletim kılavuzu](reengagement_notifications.md).
