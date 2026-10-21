# Lobi — yeni referans: koyu cam / mat metal

Önceki süslü görünüm iptal edildi. Geçerli referans kullanıcının ikinci
görselidir: antrasit yüzey, yumuşak pah, ince titanyum kenar, kontrollü altın.
Köşe işlemeleri, çift kalın parlak çerçeveler, sürekli renkli glow ve Masa Aç
madalyonunun tırtıkları kaldırıldı. Basış/seçim geri bildirimi korunur.

## Dosyalar

- `lib/ui/lobby/lobby_metal_surface.dart`: sade metal/cam yüzey çizimi,
  doğal gölge, yerel softbox yansıması; desen yalnız masa kartlarında hafif.
- `lib/ui/lobby/lobby_league_list.dart`: yeni kupa atlası ve oranları.
- `lib/ui/lobby/lobby_table_listing_card.dart`: ince titanyum yüzey ve sade
  İzle/Katıl düğmeleri. İşlem callback'leri ve uygunluk koşulları aynı.
- `lib/ui/lobby/lobby_bottom_dock.dart`: mat gövde, ince metal üst kenar ve
  sadeleştirilmiş Masa Aç çemberi. Navigasyon seçenekleri aynı.
- `test/goldens/lobby_640x360.png`, `lobby_932x430.png`: yeni tasarım çıktısı.
- `docs/previews/lobby_after_640x360.png`, `lobby_after_932x430.png`: aynı
  yeni renderların inceleme kopyaları.

2–2–1 düzeni, lig erişim kuralları, gerçek sayılar, masa verileri/yenileme ve
Supabase işlemleri değiştirilmedi. Küçük telefonda minimum 52px masa kartı ve
mevcut liste kaydırması korunur. Yeni paket yok; Yolculuk geri eklenmedi.

## Yeni varlık ve temizlik

`assets/images/lobby/leagues/trophy_atlas_v2.png`: bu görev için built-in
image_gen ile üretilmiş, 2172×724 şeffaf PNG. Beş sade kupa tek atlas ve ortak
1536px decode ile gösterilir. Önceki görevde üretilen, artık kullanılmayan
`trophy_atlas.png` projeden kaldırıldı. Daha eskiden bulunan ortak görsellere
dokunulmadı. Üçüncü taraf stok model/görsel indirilmedi.

Üretim istemi (built-in tool, transparent_background=true):

> Production sprite texture atlas for a refined modern luxury mobile game UI. Genuine transparent background. Very wide landscape 3:1 image, EXACTLY FIVE separate upright trophy cups in one row in equal-width cells, identical size, baseline and camera perspective. Do NOT make a full interface. No labels, text, glow, jewels, filigree, decorative scrolls, baroque handles or background. Each cup is elegant and restrained: classic rounded tapered bowl with a small embossed star badge, two slim smooth loop handles, narrow stem, solid stepped circular base. Only the fifth cup may have two small tasteful laurel sprigs near the stem. From left to right: warm copper bronze, brushed silver with cool blue reflections, satin yellow gold, dark amethyst purple metal, dark emerald teal metal. Photorealistic three dimensional product render, subtle real metal reflections with broad soft studio light upper left and natural deep occlusion in the bowl; avoid white-hot sparkles, neon and excess contrast. Premium understated black-glass casino game aesthetic. All five trophies fully visible and isolated with at least 10% transparent horizontal margins within EACH cell and 8% top/bottom padding. Match a simple, dignified modern trophy silhouette; no ornate decoration. Crisp small-size readability. Original reusable game art.

## Kontrol ve görüntü sınırı

Chrome geçirgenlik düzeltmesi: opak dolgu + fark kırpması yerine yalnız kenar
çizgileri kullanılır; merkez yüzeyin opaklığı yaklaşık %32–40'tır.
`tool/lobby_glass_probe.dart` gerçek üretim bileşenlerini backend olmadan açar.
`tool/lobby_glass_chrome_test.mjs`, derlenen Web sayfasını gerçek headless
Chrome/CanvasKit içinde açıp iç içe panelleri, alt barı ve gerçek showDialog
yolundaki masa kurma penceresini arka plan pikselleriyle kontrol eder. Geçti.
Bu tarayıcı testi canlı hesap oturumunun ekran görüntüsü değildir.

Yeniden çalıştırma: `flutter build web --no-pub --no-web-resources-cdn --target=tool/lobby_glass_probe.dart --output=.dart_tool/lobby_glass_web`,
ardından `node tool/lobby_glass_chrome_test.mjs`.

Gerçek Flutter bileşenlerinin golden görüntüleri yeni referansla karşılaştırıldı;
bunlar test oyuncu/masa verileri içerir, canlı hesaptan cihaz ekran görüntüsü
değildir. `adb devices` ve emülatör listesi boş olduğundan gerçek cihazda
uygulama ekranı, GPU/FPS ve bellek ölçümü bu ortamda alınamadı.

`flutter test --no-pub test/lobby_presentation_test.dart`: 29 test; 480×270,
568×320 ve büyük yatay ölçüler, 1×/2× yazı ölçeği, 2–2–1, kaydırma,
İzle/Katıl/profil/menü işlemleri ve golden karşılaştırmaları.

Önceki iki giriş ekranı golden uyuşmazlığı lobi görevinden bağımsızdır;
onların referansları güncellenmedi.
