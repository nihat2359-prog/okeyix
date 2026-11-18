# Hızlı Oyna: sunucuda en fazla 10 saniyelik insan eşleşmesi

Bu değişiklik canlıya uygulanmadı. `okeyix_quick_play` değiştirilmez; yeni
istemci `okeyix_quick_play_v2(uuid,text)` kullanır. Eski uygulamalar mevcut
anında eşleştirme akışını kullanmaya devam eder.

## Akış ve güvenlik

- Sunucunun mevcut coin/rating kurallarıyla tüm uygun liglerde açık insan masası
  aranır. Mevcut sorgunun koşulları ve `entry_coin,id` sırası korunur.
- Bulunmazsa özel şemada kullanıcı + istek UUID'siyle bir kuyruk kaydı oluşturulur.
  Beklerken masa, koltuk veya ücret yoktur. Bir kullanıcı için tek aktif kayıt vardır.
- Yeni istemciler yaklaşık saniyede bir `refresh` çağrısıyla 4 saniyelik canlılık
  süresini yeniler. İlk istekten itibaren 10 saniyelik son tarih yenilenmez.
  İkinci uygun insan, FIFO sırasındaki canlı kayıtla ortak erişilebilir bir ligde
  atomik olarak tek masaya atanır. Eski uygulamalar bu kuyruğa katılmaz.
- Her iki profilin coin/rating değerleri kilit altında yeniden okunur. Ortak lig,
  sunucudaki `min_coin`, `max_coin`, `min_rating` ve lig sıralamasından seçilir.
- Süre sonunda son insan masası ve kuyruk kontrolü yapılır. Kayıt eşleştirilemez
  duruma geçirilir, sonra mevcut RPC'nin bot yolu aynı transaction içinde kullanılır.
  Bot seçimi, oyun başlangıcı, taş dağıtımı, ücret/iade kodu değiştirilmez.
- `gold` ve `elite` bot yasağı yeni RPC'de de açıkça korunur; mevcut trigger'lar
  değiştirilmez veya devre dışı bırakılmaz. Bu liglerde insan bulunamazsa hata
  gösterilir, daha alt lige bot için sessiz geçiş yapılmaz.
- Kuyruk işlemleri kısa bir transaction advisory lock ile sıralanır. Kullanıcı/bot
  kilitleri eski RPC ile ortaktır. Ağ beklemesi veya 10 saniyelik sleep transaction
  içinde yapılmaz. Bu global kuyruk kilidi yüksek trafikte izlenmelidir.
- `cancel` eşleşmeden önce kazanırsa kalıcı iptal kaydı, geciken `start` isteğini
  de engeller. Eşleşme önce commit edilmişse `cancel` gerçek `ready/table_id`
  sonucunu döndürür; başlamış maçı/koltuğu silmez. İstemci bu sonucu tek kez açar;
  arka plandayken yönlendirme öne gelene kadar bekler.
- Pencere kapanırken/uygulama arka plana geçerken iptal gönderilir. Bağlantı
  kaybında veya zorla kapatmada iptal teslim edilemese de 4 saniye yenilenmeyen
  kayıt artık aday değildir. Son tarih geçmiş kayıt başka bir yeni isteğe rakip
  olamaz. Sonraki RPC `expire_waiters()` ile süresi dolan kayıtları iptal durumuna
  taşır; güvenlik için cron gerekmez. İptal/sonuç kayıtları, tekrar isteklerinin
  güvenliği için fiziksel olarak silinmez. Üretimde boyutları izlenmelidir.
- Commit anından önce uygulamanın öldürüldüğü anı sunucu anında bilemez: canlılık
  penceresinde eşleşme zaten commit edilmişse bu artık bekleyen kayıt değildir.
  İstek UUID'si istemcide oturuma bağlı saklanır; kayıp yanıtta aynı UUID sorgulanır.
  Mevcut lobi aktif oyuna dönüş akışı da commit edilmiş masayı geri açar.
- Kuyruk tablosunda RLS açık; schema/tablo/yardımcı fonksiyon erişimi istemciye
  kapalıdır. Yalnızca `authenticated` rolünün çağırabildiği RPC `auth.uid()` ile
  kullanıcının kendi isteğini işler. Başka kullanıcı ID'si kabul edilmez.

## Canlıya uygulama ve yayın sırası

1. Staging'de `20261022000100_quick_play.sql` ve
   `20261022000200_quick_play_instant.sql` temellerinin mevcut olduğunu doğrulayın.
   Zaten kurulu canlı projede bunları yeniden çalıştırmayın. Yeni migration,
   anında RPC gövdesini normalize edilmiş kaynak hash'iyle doğrular; farklıysa
   durur. Koruma kontrolünü kaldırıp bilinmeyen bir gövdeye kurmayın.
2. Üst lig yasağı için `20261026000100_upper_leagues_human_players_only.sql`
   trigger'larının kurulu ve etkin olduğunu kontrol edin. Kurulu değilse önce
   bu migration'ı uygulayın; kuruluysa yeniden çalıştırmayın. Önceki canlı dökümde
   bu trigger'lar doğrulanmış değildi. Yeni RPC bağımsız olarak aynı yasağı uygular.
3. Yeni `20261118000100_quick_play_queue.sql` migration'ını staging'e uygulayın.
   İki cihazla insan eşleşmesi, gerçek 10 saniye, iptal/ağ kaybı, ücret ve gerçek
   oyun başlangıcı trigger'larını test edin. SQL fixture testleri canlı trigger ve
   dağıtım motorunun yerine geçmez.
4. Staging doğrulamasından sonra aynı sırayla backend'i canlıya kurun. Eski RPC
   yerinde kalır; mevcut uygulama ve devam eden oyunlar yeni kuyruğa taşınmaz.
5. Yeni backend hazır olduktan sonra v2 RPC kullanan Flutter sürümünü yayınlayın.
   Yeni istemcide eski RPC'ye anında bot fallback'i yoktur; backend önce kurulmalıdır.
   Geri dönüşte eski uygulama/RPC çalışmaya devam eder; aktif kuyruk tablosunu
   yeni istemciler kullanımdayken kaldırmayın.

## Yerel doğrulama

```powershell
flutter test --no-pub test/quick_play_test.dart test/quick_play_backend_test.dart
powershell -NoProfile -File tool/test_quick_play.ps1
```

SQL aracı yalnızca yeni, geçici yerel PostgreSQL kümesinde çalışır. Hem eski
RPC testlerini hem v2 testlerini ve gerçek ayrı bağlantılardaki eşzamanlı
eşleşme/iptal testlerini çalıştırır. On saniye testi gerçek zamanla yapılır;
diğer sınır testleri yalnızca yerel fixture'da son tarihi değiştirir.
