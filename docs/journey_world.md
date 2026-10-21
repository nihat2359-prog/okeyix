# Yolculuk — Türkiye / İstanbul / Mekân

Lobideki mevcut Yolculuk düğmesi değişmedi. Açılış artık Türkiye'dir.
İstanbul etiketi → şehirdeki altı mekân → seçilen yapının yakın görünümü.
Geri sırası: Mekân → İstanbul → Türkiye → lobi. Telefonun geri hareketi de
aynı sırayı izler; kamera geçişi sırasında üst üste navigasyon yapılmaz.
Türkiye başlığındaki kahve simgesi eski Boğaz Kahvesi demosunu açar.
`scene.js` değiştirilmedi, demo ayrı `demo.html` içinde korunur.

## Yapı

- `geography.js`: gerçek ülke sınırları, iki örneklenmiş DEM, 81 il etiketi.
- `places.js`: şehir kaydı, coğrafi köken, başlangıç kamerası ve altı mekânın
  konumu/modeli/yakın görünüm kamerası. Başka şehirler aynı şemayı kullanabilir;
  yalnız İstanbul'un sahne üreticisi bu prototipte uygulanmıştır.
- `models.js`: ortak PBR malzemeleri, altı özgün mimari model, gerektiğinde
  üretilen yakın detaylar. Yakın detay geometrisi uzaklaşınca serbest bırakılır.
- `world.js`: ortak sahne, dokunma/ray seçimi, üç kamera seviyesi, yumuşak
  yaklaşma ve sahne değişiminde kısa atmosferik örtüşme. 3D sprite etiketleri
  ekran boyutunu korur; çakışınca konumlarını çağrı çizgileriyle düzenler.
- `journey_screen.dart`: güvenli yerel mesaj sözleşmesi, bilgi paneli, geri
  navigasyonu, uygulama arka planında duraklatma ve eski demo geçişi.

Ülke sınırları/yükseltileri ve bütün modeller çevrimdışı paketlenir. SQL,
Supabase, coin, hediye, davet, istatistik ve mevcut masa koduna dokunulmadı.
Oyun başlatma/ödül/gerçek şampiyonluk yoktur. Panel bunu prototip olarak belirtir.

## Veri ve görsel sınırlar

Tam kaynak, lisans, türetme ve yaklaşık model bilgileri:
[`SOURCES.md`](../assets/journey/SOURCES.md). Aynı kaynak bilgisine uygulamada
“Veri kaynakları” ile erişilir.

Türkiye'de relief 12×, İstanbul arazisi 1.5× büyütülür. Harita sınırları gerçek
Natural Earth verisidir; İstanbul kıyısı 1:10m verinin sınırlarına sahiptir.
Haliç girintisi açıkça belirtilmiş elle yaklaşık çizimdir. İl konumları,
İstanbul hariç, il merkezlerini değil veri kümesindeki il etiketi konumlarını
temsil eder. Şehir binaları ölçülmüş bina ayak izleri değildir.

Kız Kulesi adası, surları, kare gövdesi, sekizgen feneri, kurşun külah profili,
galerisi, pencereleri, iskelesi ve ayrıntı katmanı özellikle geliştirildi.
Beş diğer yapı tanınabilir fakat hafif, yaklaşık modellerdir. Hiçbiri ölçülmüş
restorasyon modeli veya fotogrametri değildir; fotogerçekçi oldukları iddia
edilmez. Su prosedürel shader'dır; tam fiziksel yansıma/sıvı simülasyonu yoktur.

## Performans ve kontroller

Statik mimari malzemeye göre gruplanır; şehir dokusu instanced mesh kullanır.
Yalnız seçilen mekânın yakın detayları tutulur. Sahne değişirken geometri,
malzeme, doku, gölge ve çevre haritası render hedefleri temizlenir. DPR en çok
1.5'tir, uzun süre yavaş kareler görülürse 1'e indirilir. FPS hedefinin gerçek
cihazda sağlandığı iddia edilmez.

```text
flutter test --no-pub test/journey_screen_test.dart test/journey_bridge_test.dart test/lobby_presentation_test.dart
dart analyze lib/screens/journey_screen.dart test/journey_screen_test.dart test/journey_bridge_test.dart
node tool/journey_geography_test.cjs
node tool/journey_render_test.mjs --world
node tool/journey_render_test.mjs
```

WebGL testleri Chrome/Node22 kullanır. Ülke → şehir → altı mekân → geri,
480×270 ve 844×390 etiket düzeni, yakın detay, kamera, duraklatma ve render
kaynaklarının serbest bırakılmasını kontrol eder. Görseller
`.dart_tool/journey/` altına yazılır. Bu, fiziksel telefon testi değildir.
Flutter köprü testinde WebView platform arayüzü taklit edilir; gerçek
JavaScript/GL render ayrıca Chrome testiyle doğrulanır.

Mobilde tam derleme yapıp Yolculuk → İstanbul → Kız Kulesi yolunu, diğer
mekânları, iki parmak yakınlaştırmayı, geri hareketlerini ve arka plandan
dönüşü deneyin. Gerçek Android/iOS WebView performansı ve iOS derlemesi bu
Windows ortamında doğrulanmadı. Yeni migration veya tasarım programı gerekmez.
