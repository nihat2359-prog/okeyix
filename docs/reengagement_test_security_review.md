# Tek cihaz test bildirimi — son güvenlik kontrolü

Durum: migration/Edge dosyaları düzeltildi ve yerelde sınandı.
**Production’a uygulanmadı; gerçek bildirim veya Cron çağrısı yapılmadı.**
Son SQL Editor dosyası: `supabase/migrations/20261028000300_reengagement_test_push.sql`.
SQL Editor’da dosyanın tamamı tek işlem olarak çalıştırılmalı; parçalar halinde çalıştırılmamalı.

## 1. SECURITY DEFINER ve çağrı yetkisi

Önceki sürümde yalnızca `service_role` EXECUTE yetkisi vardı. Bu rol tek bir Edge
Function’a özel değildir; dolayısıyla “sadece o fonksiyon çağırabilir” ifadesi doğru değildi.

Düzeltilen sürüm iki koşul gerektirir:

- `public.okeyix_reengagement_test_worker(text,uuid,uuid,uuid,text,jsonb)` için EXECUTE
  yetkisi (anon/authenticated/PUBLIC için kaldırıldı, service_role için var).
- Ayrı, 32–256 karakterlik **Edge-only RPC gizli anahtarı**. Private `authorization`
  tablosunda yalnızca SHA-256 özeti bulunur; başlangıçta NULL olduğu için tüm RPC çağrıları reddedilir.

Bu ek anahtarın adı `REENGAGEMENT_TEST_RPC_SECRET`; HTTP test anahtarı ile aynı olamaz.
SQL kontrolü kayıt okunmadan/kilitlenmeden önce yapılır. Eksik/yanlış anahtar SQLSTATE 42501 verir.
service_role, private şema/tablolara erişemez veya hash’i değiştiremez. BYPASSRLS,
şema USAGE / tablo yetkisi olmadan bu erişimi sağlamaz. Definer postgres, search_path boş,
tablo adları tam nitelikli; dinamik SQL yoktur. Function sahipliği kurulumdaki postgres’tur.

**Sınır:** Bu, program kimliği doğrulaması değildir. Hem service_role hem RPC anahtarına
sahip başka bir süreç çağırabilir. Veritabanı sahibi/proje yöneticisi de nesneleri değiştirebilir.
Bu yetkili aktörlere karşı mutlak izolasyon iddia edilmiyor. Ek anahtar başka işlerde kullanılmamalı.

## 2. Başka service_role süreci / yanlış tüketme

Sadece service_role anahtarına sahip bir süreç test kaydını tüketemez; RPC anahtarı da gerekir.
RPC dışında doğrudan private tabloları değiştirme yetkisi verilmez.
HTTP endpoint ayrıca hedef kullanıcı/cihazı ortam değişkenlerinden sabitler; istekle hedef
veya raw token seçilemez. SQL Editor operatörü yalnızca incelenen hedefi onaylamalıdır.

Onaylı kaydın kilidi alınır (`FOR UPDATE`), sahiplik ve token özeti yeniden kontrol edilir.
`approved → dispatching` geçişi bir kez olur. Tüketme, rastgele 64 hex karakterlik makbuz üretir;
DB yalnızca makbuzun SHA-256 özetini saklar. Ham makbuz sadece o tüketme cevabında Edge’e verilir.
Diğer çağrı aynı kaydı tüketemez ve makbuzu önizlemeden okuyamaz.

## 3. finish ve sonuç güvenilirliği

- Yalnızca `dispatching` durumunda çalışır; başka durumda `recorded=false` döner.
- RPC anahtarına ek olarak doğru tek kullanımlık makbuz gerekir.
- Durum/HTTP/hata kodu tutarlılığı kontrol edilir. Örneğin `accepted + HTTP 500` reddedilir.
- HTTP 2xx + `FCM_ACCEPTED`, HTTP 404 + `UNREGISTERED`, sınırlı hata kodları ve
  belirsiz ağ sonucu için ayrı kurallar vardır. Ham yanıt serbest metin olarak yazılamaz.
- Biten kayıt tekrar değiştirilemez; başarısız finish kaydı kısmen değiştirmez.
- API makbuzu veya raw token’ı kullanıcıya döndürmez.

**Sonuç kaynağı güven sınırı:** SQL, Google’a yapılan HTTP çağrısını bağımsız doğrulamaz.
FCM sonucu yetkilendirilmiş Edge’in TLS üzerinden aldığı cevaptan raporlanır.
Hem RPC anahtarını hem doğru makbuzu elinde tutan güvenilir/ele geçirilmiş gönderici yanlış
sonuç bildirebilir. Bu değişiklik doğrulanmış FCM teslim makbuzu veya telefon teslim kanıtı üretmez.
`accepted` hâlâ yalnızca FCM kabulü demektir.

## 4. Dış çağrılar ve HTTP test anahtarı

Endpoint yalnızca POST kabul eder. Veritabanı istemcisi oluşturulmadan önce
`x-reengagement-test-secret` ile `REENGAGEMENT_TEST_SECRET` karşılaştırılır:
iki değerin SHA-256 özetleri Web Crypto ile hesaplanır, sabit uzunluklu byte karşılaştırması yapılır.
Eksik/kısa/yanlış anahtar 401 verir. API key, service_role veya RPC anahtarı bu HTTP
başlığının yerini tutmaz. Yalnızca `mode` ve `ticket_id` alanları kabul edilir.

Supabase `verify_jwt=false` yalnızca bu endpoint içindir; gerçek yetkilendirme özel anahtar
kontrolüdür. Gizli anahtar olmadan CORS veya kullanıcı oturumu üzerinden çağrı yetkisi yoktur.
Ortamda hedef UUID’ler veya ayrı RPC anahtarı eksikse 503 ile kapanır. Uygulama kodu
token, makbuz, Google yanıtı veya gizli anahtarı loglamaz; bunları elle loglara eklemeyin.

## 5. Şema uyumu

Paylaşılan 28 Ekim canlı şema çıktısına göre sorgunun kullandığı **16 kolon ve veri tipi**
uyumludur. `users.ban_until` ve `suspension_until` timestamp, auth tarafındaki tarihler
timestamptz olarak kontrol edilir; public alanların karşılaştırması UTC yorumu kullanır.
`users.auth_user_id` varsa auth hesabı o alanla, yoksa public kullanıcı id’si ile eşleştirilir.
Silinmiş/eksik auth hesabı, bot, ban/askı ve `allow_game_invites=false` elenir.

Migration bu 16 kolonu/tipi kurulumdan önce tekrar kontrol eder. Eksik/değişik kolon varsa
`TEST_PUSH_SCHEMA_MISMATCH` ile transaction durur; tablo oluşturulmaz.
Test aynı kolon tipleriyle yerel PostgreSQL’de yapıldı. Sonradan değişmiş canlı şemaya
bağlanıp yeniden sorgu yapılmadı; paylaşılmış şema kanıtı ile kurulum guard’ı birlikte kullanılıyor.
Mevcut tablolara kolon, policy veya trigger eklenmez.

## 6. Tekrar çalıştırma ve geri alma

Migration bilerek mevcut nesneleri `IF NOT EXISTS` ile sessizce kabul etmez.
Şema veya eski/yeni RPC imzası varsa `TEST_PUSH_ALREADY_INSTALLED_REVIEW_REQUIRED_NO_CHANGES`
ile durur. Transaction rollback olur; önceki kayıtlar/yetkiler sıfırlanmaz.
**Bu dosya eski kurulmuş sürüm için upgrade migration değildir.** Önceki sürüm kurulduysa
yeniden çalıştırıp nesne silmeyin; ayrı yükseltme incelemesi gerekir.

Kurulum sırasında bir hata olursa BEGIN/COMMIT nedeniyle bu çalıştırmadaki nesneler
geri alınır. SQL Editor açık failed transaction bildirirse `ROLLBACK;` çalıştırıp hatayı inceleyin.

Kurulumdan sonraki güvenli operasyonel geri alma için
`docs/reengagement_test_rollback.sql` hazırlandı:

1. HTTP test anahtarını kaldırıp yeni Edge çağrılarını durdurun.
2. Devam eden gönderimlerin sonucunu inceleyin; `dispatching` varsa script durur.
3. Script özel test tablosunu kilitler, test RPC yetkisini kaldırıp **yalnızca yeni RPC’yi** siler.
4. Test geçmişi/config tabloları korunur; CASCADE kullanılmaz. Ana oyun tabloları,
   mevcut davet fonksiyonu, otomasyon ayarları ve Cron etkilenmez.

Bu operasyonel geri alma sonrasında özel test Edge Function silinebilir. Tüm private şemayı
silmek geçmişi kaybettirir; bu nedenle otomatik geri alma scripti bunu yapmaz. Silinmiş RPC’yi
yeniden kurmak ayrı inceleme gerektirir; eski ticket’ları tekrar onaylamayın.
Gönderilmiş/in-flight FCM mesajı SQL rollback ile geri alınamaz.

## Yapılan kontroller

- 16 Node manual test kontrolü: dış anahtar, sabit hedef, makbuz, replay, ağ hatası, sonuç kaydı.
- 28 PostgreSQL kontrolü: gerçek service_role ile ek anahtar olmadan ret, private hash erişim
  reddi, yanlış/eksik makbuz reddi, yanlış HTTP/sonuç reddi ve kayıt durum geçişleri.
- 4 yerel integration testi: tekrar kurulumda değişiklik yok; beklenmeyen kolon tipinde durma;
  devam eden gönderimde rollback reddi ve boşta yalnızca RPC’nin kaldırılması;
  sekiz eşzamanlı tüketme/sonuç çağrısında yalnızca bir başarılı işlem.
- Production kurulumu, gerçek Google/FCM isteği, Deno deploy ve Cron çalıştırması yapılmadı.
