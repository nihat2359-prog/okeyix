# Masa hediyeleri

Canlı Supabase'e uygulanmadı. Tek yeni migration:
`supabase/migrations/20261021000200_table_gifts.sql`.
Mevcut `gifts`/`gift_types` profil hediyesi sistemi değiştirilmez.

## Dosyalar

- `lib/models/table_gift.dart`, `lib/services/table_gift_service.dart`: katalog,
  doğrulanmış olaylar, cursor, tekrar koruması ve reconnect.
- `lib/game/table_gift_flight.dart`, `lib/ui/table_gift_layer.dart`: Flame uçuşu,
  avatar yanındaki son hediye ve sağ katalog paneli.
- `lib/ui/avatar_card.dart`, `lib/ui/game_avatar_overlay.dart`: gerçek avatar
  konumu, iki alıcının butonları ve bakiye yenilemesi.
- `lib/screens/spectator_screen.dart`, `lib/services/game_view_data_source.dart`:
  seyirci son durumu ve oyuncu katılım kimliği.
- `pubspec.yaml`: mevcut hediye asset klasörünün kaydı.
- `test/table_gifts_test.dart`, `test/statistics/table_gifts.sql`,
  `test/statistics/table_gifts_concurrency.ps1`: yerel testler.

## Uygulama sırası

1. Mevcut oyun tabloları / profiles / wallet_transactions kurulu staging ortamında
   yeni migration'ı postgres olarak tek sefer çalıştır.
2. Flutter uygulamasını yeni asset kaydıyla yeniden derle.
3. İki ayrı insan hesabıyla aynı iki kişilik, playing durumundaki masaya katıl.
   Rakibe, ters yönde ve kendine gönderimi; yetersiz coin; reconnect ve seyirciyi
   gerçek cihazlarda doğrula. Kabul sonrası aynı SQL üretime uygulanabilir.
   Bu iş için referral migration'ı zorunlu değildir.

## Sözleşme

- 14 PNG doğrudan `assets/images/hediyeler/` altından kullanılır; kopya asset yok.
- Fiyat/ad/etkinlik merkezi `okeyix_gift_catalog` tablosundan gelir. Flutter fiyat
  göndermez; bilinmeyen asset kimliklerini kabul etmez.
- `okeyix_buy_table_gift(table,recipient,gift,request)` göndereni auth.uid() ile
  belirler. Masa playing ve iki ayrı katılımcılı olmalı; alıcı kendisi olabilir.
  İnsan oyuncu yalnızca kendi bakiyesinden satın alabilir.
- İstek UUID'si gönderenle birlikte unique. Aynı istek için advisory kilit,
  ardından masa ve profil kilidi kullanılır. Fiyat doğrulaması, bir debit wallet
  kaydı, bir satın alma kaydı ve son hediye güncellemesi tek transaction'dır.
  `wallet_transactions.amount=-price`, reason=`table_gift`, type=`debit`,
  store=`system`. Alıcıya coin yazılmaz. Başarısız işlem tamamen rollback olur.
- İstemci ağ hatasında aynı request UUID'sini saklar; başka hediyeye geçmeden
  önce belirsiz işlemi aynı hediye üzerinden doğrular. Kesin SQL reddinde yeni
  seçim yapılabilir. Çift dokunma ve aynı olayın yeniden gelmesi tekrar sayılmaz.
- Satın alma geçmişi masa silinince korunur. Görsel son hediye durumu masa UUID'si
  ve alıcının `table_players.id` katılımına bağlıdır. Katılım veya masa silinince
  CASCADE ile temizlenir; el değişimi ve reconnect'te kaybolmaz. Eski bir
  katılıma ait hediye aynı kullanıcının yeniden katılımına taşınmaz.
- Realtime yalnız sunucunun satın alma INSERT'lerini haber verir. İstemci payload'ı
  doğrudan animasyon olarak kullanmaz: RLS ile korunan sıralı `seq` sorgusunu okur.
  Tek masa satırı kilidi o masadaki commit sırasını korur; sequence boşlukları
  güvenlidir. Aynı seq tekrar oynatılmaz. Snapshot, cursor ve son hediyeleri tek
  SQL snapshot'ından döndürür. Reconnect geçmiş uçuşları oynatmadan son durumu alır.
- Seyirci, izlemeye açık masada son durumu okuyabilir; katılımcı kapalı masada da
  okuyabilir. Seyirci satın alamaz. Katalog/olay/durum tablolarına istemci DML
  izni yoktur; tüm RPC'ler auth denetimli ve sabit search_path kullanır.
- Oyuncu uçuşları, gerçek avatar ve kart RenderBox konumlarını kullanan ayrı
  şeffaf Flame katmanında gerçekleşir. Döndürme/partikül yoktur. PNG oranı korunur.
  Flame katmanı boşta duraklatılır ve dokunmaları engellemez. Seyircide Flame
  uçuş katmanı veya gönder butonları oluşturulmaz.
- Yeni polling yoktur. Oyuncu katılımı, mevcut oyuncu yenilemesiyle izlenir;
  mevcut sorguya yalnız `table_players.id` eklenmiştir. Bakiye sunucu cevabından
  alınır ve mevcut avatar veri kaynağı yeniden yüklenir.
- Metinler cihaz diline göre TR/EN fallback kullanır; PNG'ler her yerde aynıdır.

## Testler

- `test/table_gifts_test.dart`: PNG manifesti, iki istemcinin yön/sıra/tekrar
  kontrolü, self gift, yetersiz coin, kayıp cevapta idempotency, reconnect,
  eski masa cevabı, seyircide animasyonsuz görünüm; 480×270 ve 844×390 panel,
  gerçek Flame SpriteComponent uçuşu ve son hediyenin zamanla kaybolmaması.
- `test/statistics/table_gifts.sql`: sentetik, localhost korumalı ve ROLLBACK;
  fiyat, atomiklik, idempotency, kendine/ters yöne satın alma, RLS ve temizleme.
- `test/statistics/table_gifts_concurrency.ps1`: localhost test DB'de aynı isteğe
  iki bağlantı, ardından iki farklı isteğin yetersiz bakiye yarışı. Tek seferlik
  sentetik fixture bırakır; üretimde çalıştırılmaz.
- Yerel PostgreSQL 16'da mevcut envanter fixture'ı üzerinde migration derlenip
  çalıştırıldı. Yerel sunucunun wal_level ayarı logical olmadığından gerçek
  Supabase Realtime teslimi yerelde doğrulanmadı. Gerçek iki cihaz / Supabase
  Realtime / seyirci uçtan uca kabul testi staging'de yapılmalıdır.
