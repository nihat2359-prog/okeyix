# Diskarttan alma animasyonu — 27 Ekim 2026

İstenen sıra: alma olayı işlendiğinde kaynak taşın yüzü hemen gizlenir,
diskart referansları temizlenir ve ardından hareket eden taş eklenir.

İki açık kapatıldı:

- Rakibin alma animasyonu yalnız `_discardTopTilesBySeat` referansını
  kaldırıyordu. Taş yalnız `DiscardSlotComponent.currentTile` üzerinden
  görünüyorsa kaldırılmıyordu. Yerel ve uzak alma artık aynı temizliği kullanır.
- Otomatik atış animasyonu bitince gerçek el bileşeni diskart konumundadır.
  `_serverDiscard` ayrıca diskart için bir görsel oluşturur; asıl bileşen
  RPC cevabına kadar kaldırılmazdı. Cevap gecikirse rakibin alması yalnız
  üstteki görseli kaldırıp altında asıl taşı bırakabilirdi. Artık onay bekleyen
  asıl bileşenin çizimi gizlenir; reddedilen işlemde çizim geri açılır.

`TileComponent.hideTileVisual`, Flame'in ertelenmiş kaldırma işlemi
tamamlanmadan önce çizimi durdurur. Alınan taş kimliği eski sunucu sonuçlarına
karşı korunur. Gecikmiş bir alma olayı farklı kimlikli daha yeni taşı kaldırmaz.
İzleme ekranındaki alma işleminde de kaynak yüz aynı şekilde hemen gizlenir.

Testler (`test/game_latency_regression_test.dart`):

- Hem harita hem yalnız slot referansı bulunan kaynak, sonraki kareden önce gizlenir.
- Eski `table_discard_tops` verisi alınan taşı yeniden göstermez.
- Gecikmiş eski alma olayı yeni diskartı korur.
- Yavaş atış cevabı beklenirken rakip alırsa asıl el bileşeni görünmez kalır.
- Reddedilen atışta asıl taşın görünürlüğü geri gelir.

Gerçek cihaz ve canlı Realtime gecikmesiyle uçtan uca doğrulama henüz yapılmadı.
Sunucu oyun kuralları, ödeme veya SQL değişikliği yoktur.
