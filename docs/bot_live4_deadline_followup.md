# strategic-live-4: gerçek maçta tekrar eden deadline

Kullanıcının son loglarında `expectation_incomplete` kararları yaklaşık
1800 ms'de yalnızca 13–20 / 44–51 tür değerlendirilerek kapanıyor. Üst atık
mevcut, kapalı çekiş ve atış RPC'leri başarılı. Dolayısıyla 1800 ms'ye çıkarmak
tek başına yeterli olmamış. Loglar kaç yararlı taşın kaçırıldığını veya neden
bitiş bulunmadığını göstermez; gizli el kayıtları istenmedi/eklenmedi.

## Değişiklik

- Geçerli perler ve kısmi çiftler, en küçük fiziksel taş bitine göre indekslenir.
  DP ve bitiş araması sadece ilgili grupları tarar. Grup üretiminde geçici
  liste/set/string koleksiyonları azaltıldı; geçerlilik ve puanlar korunur.
- Önceki motorun yerel kopyasına karşı sabit seed'li 64 örnekte hamle, puan,
  yerden alma ve bitiş varlığı aynı bulundu. Tek yerel VM ölçümü: önce
  2.034.665 us, sonra 909.261 us (2,24 kat). Chrome hızı iddiası değildir.
- Tam çekiş karşılaştırması yine yetişmezse ve açık taşın değerlendirmesi
  tamamlanmışsa otomatik kapalı seçmek yerine `botDeadlineDrawComparison`
  kullanılır. Açık ve kapalı seçenekleri AYNI basit bağlantı puanıyla tüm
  bilinmeyen türlerin kalan adetleri üzerinden karşılaştırılır. Eksik örneklem,
  zorunlu alma yüzdesi veya rastgelelik yoktur.
- Bu fallback tam per DP'si değildir: yerel renk/sayı bağlantılarını yaklaşık
  değerlendirir. Bütün türlerin ortalaması tam olsa da puanı yaklaşık bir
  modeldir; ana DP puanıyla karıştırılmaz. `limited:true` ve `fast_*` nedeni
  kayıtta bu ayrımı gösterir. Çiftli ilan edilmiş ellerde kullanılmaz.
- Web tam arama 1400 ms; kalan dış 2100 ms bütçesinde fallback'a pay bırakılır.
  Native tam arama 650 ms kalır. Süre garantisi değil, sonlu hesap sınırıdır.
  İki gerçek okeyle okey atma tercihi korunur; bu tercih normal bitişi erteleyebilir.

## Doğrulama

55 bot testi geçti. Deadline fallback'ın yararlı taşı alması, yararsız taşı
reddetmesi ve OkeyGame adaptöründen `game_draw(source:discard)` akışına
ulaşması dahil. Generated el ve mevcut RPC testleri de geçti.
Hedefli analiz temiz. Ayrı headless Chrome/dart2js sentetik kontrolünde hızlı
karşılaştırma üç kez de 52/52 türü hesaplayıp yararlı üst atığı aldı.
Virtual-time süreleri performans ölçümü sayılmadı.
Gerçek Flutter DDC/Chrome maçı bu ortamda yeniden oynanmadı; yeni kullanıcı
logunda sürüm `strategic-live-4` olmalıdır. Yeni 192 maç sonucu üretilmedi.

Değişen kaynaklar: bot_engine.dart, bot_runner.dart, bot_diagnostics.dart;
testler: bot_engine_test.dart, bot_draw_live_path_test.dart.
Oyun RPC'leri, Supabase migration'ları ve ekonomi değiştirilmedi.
