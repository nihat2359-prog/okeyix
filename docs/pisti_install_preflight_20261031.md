# Pişti canlı kurulum ön kontrolü — 31 Ekim 2026

**Güncelleme:** Aşağıdaki kaynak uyumsuzluğu sonraki kullanıcı onayıyla canlı
v13 esas alınarak giderildi. Migration, Edge/Vault ve cron kurulumu daha sonra
tamamlandı. Aşağıdaki durma kararı ilk ön kontrolün tarihsel kaydıdır.

Kullanıcı mevcut projeye kurulum ve etkinleştirme onayı verdi; Okey'i bozacak
somut uyumsuzlukta değişiklik yapılmadan durulmasını istedi.

## Doğrulanan hedef ve salt okunur kontroller

- Proje: `okeyix-prod`, ref `esqpgtedmojrzoftchis`, `ACTIVE_HEALTHY`.
- `docs/pisti_preflight.sql` canlıda salt okunur çalıştırıldı.
- Gereken kullanıcı/profil/cüzdan/arkadaş/hediye/masa alanları mevcut.
- pg_cron 1.6.4, pg_net 0.19.5, Vault 0.3.1; Storage ve Realtime mevcut.
- Mevcut Pişti tabloları yok. `supabase_migrations.schema_migrations` yok;
  bu projede toplu `db push` kullanılmamalı.
- Mevcut public fonksiyonlar, ilgili trigger/policy tanımları, cron kayıtları,
  Vault isimleri ve davet Edge kaynağı geri dönüş için git dışındaki
  `.dart_tool/pisti-install/` altında kaydedildi. Secret değerleri gösterilmedi.
- Vercel `okeyix-web` production ortamında `SUPABASE_URL`,
  `SUPABASE_SERVICE_ROLE_KEY` ve `ADMIN_SESSION_SECRET` zaten tanımlı.

## Kurulumu durduran somut uyumsuzluk

Canlı `send_table_invite_push` sürüm 13, ACTIVE, `verify_jwt=true`.
İndirilen canlı kaynak Okey davetlerini Google OAuth ve **FCM v1** üzerinden
gönderiyor; Legacy FCM uç noktasını kullanmıyor.

Hazırlanan yerel `supabase/functions/send_table_invite_push/index.ts` dosyası
Pişti için FCM v1 eklese de Okey dalında **FCM Legacy** uç noktasını ve
`FCM_SERVER_KEY` beklentisini koruyor. Canlı secret isimlerinde bu legacy
anahtar yok. Dosyayı yayınlamak mevcut çalışan Okey davetlerini bozabilir.

Kullanıcının durma koşulu nedeniyle migration, secret, Vault, Edge deploy,
cron, özellik açma veya admin ortam değişikliği **yapılmadı**. Maç testi de
henüz kurulmayan Pişti sunucusunda çalıştırılmadı. Çalışan canlı fonksiyon
yeniden yazılmadı. Kurulumdan önce bu kaynak/sürüm uyumsuzluğu çözülmelidir.
