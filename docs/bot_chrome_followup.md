# Chrome gerçek maç geri bildirimi

## Gerçek kayıtla doğrulanan takip düzeltmesi

Kullanıcının `strategic-live-2` kayıtlarında üst atık mevcut, kapalı çekiş ve
atış RPC'leri başarılı; çok sayıda çekiş `expectation_incomplete`, `limited:true`
ve yaklaşık 650 ms ile bitiyor. Bu, tamamlanmamış olasılık hesabının kapalıya
dönüşünü doğrular. `would_return_top` ise farklıdır: değerlendirme tamamlanmış,
üst atığı geri atmak en iyi aday bulunmuştur. Taş içerikleri olmadığı için
kaç yararlı taşın kaçtığı ve oyunların neden kaybedildiği bu loglardan ölçülemez.
`superseded` kayıtları eski sıra için hamle yapılmadığını gösterir; tek başına
başka bir sunucu hatasının kanıtı değildir.

`strategic-live-3` değişiklikleri:

- Her kapalı çekiş türü için taş çiftlerinin geçerli tamamlama türlerini
  yeniden üretmek yerine karar içinde paylaşılır. Görünen kopya adetleri
  her varsayımsal el için yeniden hesaplanır. Cache karar dışına taşınmaz.
- Her ucuz tür hesabından sonra sıfır süreli browser timer'ı açılmaz;
  yaklaşık 8 ms hesap aralıkları arasında event loop'a dönülür. Chrome'un
  nested timer beklemeleri böylece gereksiz yere birikmez. Tek bir türün
  hesaplaması sırasında yield yoktur; kesin 8 ms kare süresi garantisi değildir.
- Web çekiş hesabı 1800 ms, dış runner 2100 ms sınırı kullanır; native
  650/750 ms kalır. Tamamlanmamış karşılaştırma hâlâ kesin sonuç diye
  kullanılmaz. Puanlama ve bilinmeyen türlerin ağırlıkları değiştirilmez.
- Güvenli debug kayıtlarına değerlendirilen/toplam tür sayısı eklenir.

Doğrulama: 49 test geçti (bağımsız tür hesaplarıyla cache eşitliği, generated
eller, adapter/RPC ve runner testleri dahil). Ayrı headless Chrome'da dart2js
ile derlenmiş sentetik yararlı üst atık senaryosu üç çalıştırmada da
`take:true`, `limited:false` verdi. Virtual-time kullanan bu kontrolün süreleri
performans ölçümü sayılmaz; Flutter DDC/debug gerçek maç testi değildir.
Önceki 192 maçlık benchmark bu sürüm için yeniden çalıştırılmadı.

## Önceki takip notu (strategic-live-2)

Kullanıcı, hot reload sonrasında iki maçta botun hiç yerden almadığını bildirdi.
Bu maçlara ait karar/RPC kayıtları yok; gerçek neden henüz doğrulanmış değildir.

Kod incelemesinde Chrome için iki risk giderildi:

- Web'in 12 ms / 12.000 düğüm sınırı, tek bir tam değerlendirme bitmeden
  aramayı kesebiliyordu. Çekişte türler arasında yield, toplam 650 ms ve
  runner 750 ms sınırı korunur. 15 taş için native ile aynı 180 ms / 300.000
  düğüm sınırı kullanılır. Gerçek tarayıcıda kare süreleri ayrıca ölçülmelidir.
- Taş atma adaylarının bir kısmı değerlendirilmişken limit dolarsa artık
  tamamlanmış en iyi aday korunur. Çekiş olasılığı hesabı eksik maksimumları
  kullanmaz; tamamlanmamış karşılaştırma hâlâ güvenli biçimde kapalıya döner.

Debug konsolunda `[BOT_RUNTIME]` / `strategic-live-2` çıktısı otomatik vardır.
İzinli alanlar: karar nedeni, süre, limit, üst atık var/yok, elin taş sayısı,
RPC başarı/hata kodu, sıra doğrulama ve timeout recovery. Taş değerleri,
oyuncu/masa kimlikleri, rakip eli veya deste içerikleri yazılmaz. Release'de
bu kayıtlar kapalıdır. Ayrıntılı el trace'inin staging/debug kısıtları korunur.

Doğrulama: uygulamayı tamamen durdurup yeniden çalıştır, yeni masa aç.
Sorun sürerse bir bot sırasının `[BOT_RUNTIME]` satırlarıyla üst atığın
okunamaması, arama sınırı, RPC reddi ve timeout motoruna geçiş ayrıştırılabilir.
Hot reload eski maç durumunu temizlemez.

Yeni web uyumlu test: `test/bot_browser_runner_test.dart`.
Bu ortamda Chrome testi loading aşamasında ilerlemedi ve durduruldu;
Chrome gerçek maç başarısı olarak raporlanmaz. VM testleri ayrı doğrulanır.
Önceki 192 maçlık rapor bu değişikliğin Chrome ölçümü değildir.

Yerel sonuç: dört bot test dosyasında 45 test geçti. Değişen bot modüllerinin
hedefli analizinde sorun yok. Proje genelinde `flutter analyze --no-pub`
463 uyarı/bilgi bildirdi; error seviyesinde bulgu yok. Bu nedenle proje geneli
analiz temiz olarak raporlanmaz.

Oyun RPC'leri, dağıtım, ekonomi ve SQL migration'ları değiştirilmedi.
