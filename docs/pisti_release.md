# Pişti Molası: kurulum, doğrulama ve geri dönüş

31 Ekim 2026 ürün kararı: Okeyix’in ana oyunu Okey’dir. Giriş ve açık oturum
doğrudan mevcut Okey lobisini açar. Oyun merkezi ve Yakında kartları kaldırıldı.
Okey lobisindeki **Pişti Molası** girişi yalnızca **Botla Oyna** ve
**Arkadaşımla Oyna** seçeneklerini açar. Herkese açık Pişti masa listesi,
rastgele eşleşme ve kariyer/rating girişi gösterilmez.

## Akış ve ekonomi

- Bot seçeneği tek istekle özel, seyircisiz ve ücretsiz masa açar; uygun bot
  aynı transaction içinde yerleşir. Bot yoksa yarım masa bırakılmaz.
- Arkadaş seçeneği ücretsiz özel masayı ve mevcut arkadaş davet penceresini
  açar. Liste yalnızca mevcut, uygun insan arkadaşları gösterir. Mevcut JWT,
  arkadaşlık, davet kabul/ret/expiry ve push altyapısı kullanılır.
- Hazırlık otomatik tamamlanır; kullanıcıdan hazır/bedel ayarı istenmez.
  Bot rakip BOT olarak işaretlenir. İki oyuncu yerleşince maç başlar.
- Yeni masalar sunucuda casual=true, entry_coin=0, private=true,
  spectators_enabled=false, break_kind=bot|friend olarak zorlanır.
  İstemcinin gönderdiği ücret veya açık masa tercihi bunu değiştiremez.
- Sıfır tutar cüzdan/ledger kaydı üretmez. Casual sonuç puanları ve geçmişi
  kaydedilir; ödül, iade ve kariyer/rating güncellemesi atlanır. Rövanş da ücretsizdir.
  Önceden kurulmuş ücretli masalar eski sözleşmeleriyle tamamlanır; kayıtlar silinmez.
- Oyun içi puan alanı snapshot `score` değerini gösterir: tamamlanan ellerin
  `total` toplamı + bu elde alınan kart puanları ve Pişti bonusları. Kart
  çoğunluğu bonusu yalnızca el sonunda eklenir. Sonuçta `score=total` olur;
  el devrinde puanlar iki kez sayılmaz. Eski snapshot’larda `total` kullanılır.
- Arkadaş rövanşında iki onay gerekir; bot rövanşı mevcut bot onayıyla başlar.
  Ayrılma devam eden maçı hükmen bitirir; çıkış Okey lobisine döner.
- Açılışta aktif Pişti üyeliği bulunursa mevcut maça dönüş korunur. Davet/push
  oyun seçimine zorlamadan ilgili davet veya aktif masayı açar.
- Bot sırası için Realtime’a ek olarak sunucunun deadline değerinde tek seferlik
  foreground yenilemesi yapılır; 15 saniyelik bağlantı kontrolü beklenmez.
  Sunucu yine hamlenin tek otoritesidir. Bu timer arka planda/çıkışta iptal edilir.
  Sayaç üst menüde değil, sırası gelen insan oyuncunun adının yanında gösterilir;
  bot sırasında “Bot düşünüyor” yazar. Aynı snapshot’ın tekrar bildirimi saat
  farkını yeniden hesaplayıp sayacı başa döndürmez.

## Mevcut kurulum ve migration sırası

Hedef mevcut Supabase projesi: esqpgtedmojrzoftchis. Yeni proje oluşturulmaz.
Mevcut migration geçmişini topluca yeniden oynatmayın:

1. 20261030000200_pisti.sql
2. 20261030000300_pisti_social_worker.sql
3. 20261030000400_pisti_admin.sql
4. 20261031000100_pisti_invitation_seating.sql
5. 20261031000200_pisti_break.sql

Son migration eklemelidir; Okey tablolarını, oyunu, eski finansal kayıtları veya
gizli kart protokolünü değiştirmez. Beklenen fonksiyon parçaları uyuşmazsa
transaction geri alınır. Önceki fonksiyonlar/constraint’ler git dışında
.dart_tool/pisti-install/break-before-20261031.json içinde saklandı.

Mevcut Pişti Edge, FCM v1 davet Edge’i, Vault/worker secret’ları ve aktif
okeyix-pisti-tick cron’u kullanılır; yeni secret veya Edge deploy gerekmez.
Özel şema PostgREST’e açılmaz. Admin service anahtarı tarayıcıya konmaz.
Admin giriş bedeli ayarı eski rekabet altyapısına aittir; yeni Molası masalarının
ücretsizliğini değiştiremez. Kullanılmayan altyapı yerinde korunur.

## Doğrulama

Yeni ekonomi regresyonu test/sql/pisti_break_flow.sql: sıfır bakiyeyle bot ve
arkadaş, zorunlu gizlilik, UUID tekrarı, normal sonuç puanları, rövanş,
hükmen sonuç/iptal ve sıfır ledger/rating etkisi. tool/test_pisti_break.ps1 yeni ücretsiz akışı ve eski ücretli masa sözleşmesinin korunmasını sınar.

İlgili Flutter kontrolleri: pisti_break_navigation_test.dart,
pisti_online_test.dart, pisti_preparation_test.dart,
pisti_online_motion_test.dart, game_world_design_test.dart.
Kısa landscape görüntüleri 568×280, 640×320 ve 844×390 üretilir.
Fiziksel iki cihazda push teslimatı ve arka plan davranışı ayrıca kontrol edilir.

## Geri dönüş

Önce admin Pişti özelliğini kapatın; aktif masaları admin ile kapatın ve cron’u
sonra durdurun. Casual masalar iade/ödül üretmez; eski ücretli masaların
tekil iade ve ledger sözleşmeleri korunur. Pişti tablolarını veya muhasebeyi silmeyin.
Ücretsiz masalar mevcutken yalnızca eski fonksiyon tanımlarını geri yüklemeyin;
önce bu masaları sonlandırın. Eski istemci de yeni sunucuda ücretsiz özel masa açar.
Mağaza yayını bu çalışmanın kapsamında değildir.
