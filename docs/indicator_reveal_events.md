# Karşı oyuncuda gösterge animasyonu

Kurulum: `supabase/migrations/20261027000600_indicator_reveal_events.sql`
SQL Editor'da postgres olarak çalıştırılmalı ve iki oyuncu da güncel uygulamayı
yeniden açmalı. Henüz canlıya uygulanmadı. 005 sohbet kurulumuna bağımlı değildir.

Başarılı `indicator_bonus` cüzdan kaydı aynı veritabanı işlemi içinde bir
`table_indicator_events` olayı üretir. Oyuncu hâlâ o masada olmalı; masa playing
durumunda olmalı. Eski kayıtlar geriye dönük yayınlanmaz. Normal ödül, bozuk note,
masada olmayan kullanıcı ve yinelenen aynı oyuncu/raund kaydı olay üretmez.
Yeni tablo yalnız masa oyuncularınca okunabilir; istemci olay yazamaz.

Oyun ayrı Realtime kanalında olayı dinler. Mevcut match_moves kanalı değişmez.
Karşı oyuncunun tarafından göstergenin aynısı olan geçici taş gelir, gösterge
üzerinde döner ve geldiği yere geri gider. Bu taş kilitlidir ve rak/slot/eldeki
taş listesine eklenmez. Olay kimliğiyle tekrar oynatma engellenir; başka masa,
başka raund, bilinmeyen oyuncu, kendi oyuncusu veya aktif olmayan el reddedilir.
Yeni el kurulurken devam eden geçici animasyon temizlenir.

Bağlantı açılışında/yeniden bağlanmada yalnız son 5 saniyenin mevcut raund
olayları bir kere sorgulanır. Sürekli sorgu eklenmez. Daha uzun bağlantı
kesintisinde eski animasyonlar sonradan oynatılmaz. Yerel gösterge animasyonu
anında başlar; karşıdaki, başarı kaydı ulaştığında başlar, tam eşzamanlı değildir.

Bu değişiklik gösterge ödülünün mevcut hesaplamasını veya taş doğrulamasını
yeniden yazmaz. Ödülün istemcideki mevcut çok adımlı işlemi aynı kalır; yeni
olay, cüzdan kaydı eklenmeden oluşmaz. Canlı Supabase dağıtımı doğrulanmadı.

Testler: geçici taşın hareket/dönüş/geri dönüşü, aynı olayın tekrarı, masa/raund
ve oyuncu filtreleri, rakın değişmemesi; ilgili toplam 35 Flutter testi geçti.
Yerel PostgreSQL 16'da ilk/tekrar kurulum, makbuz filtreleme, raund değişimi,
olay tekrarının engellenmesi ve authenticated okuma/yazma erişimleri geçti.
PostgreSQL fixture mantığı sınar; gerçek Supabase Realtime ile iki cihaz testi
kurulumdan sonra yapılmalıdır.
