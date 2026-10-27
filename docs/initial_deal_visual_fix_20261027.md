# İlk dağıtımda taşların slot dışında kalması — 27 Ekim 2026

Kullanıcı Chrome/web üzerinde bazı taşların görünmediğini, taş hareketi veya
Seri diz sonrasında yeniden göründüğünü bildirdi.

## Testte doğrulanan hata

İlk dağıtım `MoveEffect.to` ile yapılıyordu. Projedeki Flame 1.35.1 uygulaması
bu efekti başlangıçta hesaplanan farkın her karede konuma eklenmesiyle çalıştırır.
Dağıtımın ortasında eşitleme veya sıralama taşı slot merkezine taşısa bile efekt
kalan farkı eklemeye devam eder. Böylece taşın slot kaydı doğru olduğu halde
görseli slot dışına çıkabilir. Bu kayıt/konum ayrışması önceki slot kaybından
farklıdır ve taş sayısı kontrolüyle tek başına yakalanmaz.

İki regresyon testi önce mevcut kodda başarısız oldu:

- Dağıtımdan 100 ms sonra 15 taşlık elin 14 taşlık ilk atış görüntüsüyle eşitlenmesi.
- Dağıtımdan 100 ms sonra Seri diz çalıştırılması.

Her iki örnekte bir taşın atanmış slotundan uzaklığı yaklaşık 111,88 oyun
birimiydi. Bu, bütün Chrome görünmezlik vakalarının aynı neden olduğunu
kanıtlamaz; canlı ekran görüntüsündeki bileşen konumları ölçülmedi.

## Düzeltme

İlk dağıtım, mevcut mutlak rak hareketiyle aynı iptal edilebilir konum mekanizmasını
kullanır. 220 ms süre, taş başına 25 ms gecikme ve easeOutCubic korunur.
Sıralama veya kullanıcı hareketi başladığında eski dağıtım devam edip yeni
konuma fark ekleyemez. Eşitleme slota sabitlediğinde de kalan hareket durur.

Sunucu, Coin, taş dağıtma kuralları ve ağ sorguları değiştirilmedi.

## Doğrulama

`game_latency_regression_test`, `rack_draw_insertion_test`,
`tile_visual_identity_test`, `game_lifecycle_regression_test` birlikte 54 test geçti.
İki yeni test düzeltme öncesinde başarısız, düzeltme sonrasında başarılıdır.
Canlı Chrome oturumu ve gerçek cihazda uçtan uca doğrulama ayrıca gerekir.
