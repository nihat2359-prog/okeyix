# Kız Kulesi — ayrı görsel kalite prototipi

Lobide Yolculuk doğrudan `maiden.html` açar. Üstteki kahve düğmesi önceki
Boğaz Kahvesi'ni açar; geri ile Kız Kulesi'ne dönülür. Türkiye/İstanbul harita
dosyaları silinmedi, ancak bu girişte kullanılmaz. Oyun, ekonomi ve DB değişmedi.

## Varlık ve lisans

This work is based on "Maiden's Tower"
(https://sketchfab.com/3d-models/maidens-tower-398a52c016914328bf88e273823db6c1)
by oblo.3d (https://sketchfab.com/oblo.3d), licensed under CC-BY-4.0
(https://creativecommons.org/licenses/by/4.0/).

Kullanıcının sağladığı `maidens_tower.zip` içindeki lisans doğrulandı. Ticari
kullanım atıfla mümkün; uygulama içindeki Kaynaklar ve MAIDEN-LICENSE.txt atfı
korur. Model statik materyal gruplarına birleştirildi, Y-up dönüşümleri işlendi,
yükseklik yaklaşık 30 metreye ölçeklendi. Kaynak modelin mimari yorumu korunur;
günümüzdeki restorasyonun ölçülmüş dijital ikizi olduğu iddia edilmez.

Three.js r160 ve GLTFLoader: MIT, `vendor/THREE-LICENSE.txt`. Resmi loader
modül importları mevcut offline UMD Three bağlamına uyarlandı; yalnız ihtiyaç
duyduğu toTrianglesDrawMode yardımcı fonksiyonu aynı sürümden alındı.

## Yeniden üretim

ZIP'i `.dart_tool/maiden_source` içine aç (scene.gltf, scene.bin, textures/,
license.txt). Aynı dizine Three.js 0.160.0 paketindeki resmi
`examples/jsm/loaders/GLTFLoader.js` dosyasını `GLTFLoader.source.js`,
`examples/jsm/utils/BufferGeometryUtils.js` dosyasını
`BufferGeometryUtils.source.js` adıyla koy. Sonra:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/prepare_maiden_textures.ps1
node tool/build_maiden_asset.cjs
```

Windows System.Drawing yalnız hazırlama aşamasında kullanılır. Runtime'da ağ,
harici CDN, kullanıcı oturumu veya 3D program gerekmez. PBR taban renk, normal,
metal/roughness ve occlusion kanalları korunur; JPEG 90 ve çoğunlukla 512px,
ana kule duvarlarında 1024px kullanılır. Camın saydamlığı materyal faktöründedir.
UV1 kaynakta olsa da materyaller UV0 kullandığı için çıktı yalnız UV0 taşır;
tangent çerçevesi Three tarafından normal haritasının türevlerinden hesaplanır.

## Bütçe ve sınırlar

- Kaynak 1.933 mesh → 31 mimari çizim grubu. Deniz düzlemi çıkarıldı;
  mimari 265.598 üçgen. Ayrıntı geometri sadeleştirmesi yapılmadı.
- Orijinal PNG dokular yaklaşık 78,6 MiB; optimize GLB, dokular dahil
  yaklaşık 19,5 MiB. Offline WebView file-fetch kısıtları için GLB base64
  JS olarak paketlenir (~26 MiB). İlk yüklemede geçici bellek maliyeti vardır.
- DPR en fazla 1,5; gölge haritası 1024; küçük PMREM ortam haritası;
  uzak binalar tek InstancedMesh. Mimari gölge alır/verir.
- Deniz shader'ı animasyonlu normal ve güneş yansıması kullanır; gerçek
  planar reflection/SSR ve dalga geometrisi yoktur. Uzak kıyı, cami siluetleri
  ve tekneler temsili yardımcı çevredir; fotogerçekçi İstanbul modeli değildir.
- Kamera yarıçapı 48–160m, açı .08–.77 radyan; ada sınırının dışında kalır.
  Reset ve üç saniyelik hafif açılış hareketi, pinch/drag/wheel desteklenir.
- Pause arka planda RAF'ı durdurur; dispose texture/geometry/context bırakır.
  Yükleme mesajları aşama/texture ilerlemesidir, byte transfer yüzdesi değildir.

## Doğrulama

```powershell
node tool/journey_render_test.mjs --maiden
node tool/journey_render_test.mjs
flutter analyze --no-pub lib/screens/journey_screen.dart test/journey_bridge_test.dart test/journey_screen_test.dart
flutter test --no-pub test/journey_bridge_test.dart test/journey_screen_test.dart test/lobby_presentation_test.dart
```

Chrome yazılım WebGL render testi gerçek dokulu GLB'yi açar; 1000×560,
480×270, 844×390 görüntülerini `.dart_tool/journey/premium_maiden_*.png`
olarak kaydeder. Yükleme, çizim bütçesi, kamera sınırı, pause/reset/exit/dispose
denetlenir. Yazılım render süresi mobil FPS olarak raporlanamaz. Android/iOS
fiziksel cihazda FPS, bellek tepe değeri ve WebView yükleme süresi ayrıca
ölçülmelidir. Yakın doku çözünürlüğü ve temsili uzak çevre kalite sınırlarıdır;
premium nihai kalite kabulü yalnız teknik testlerin geçmesiyle verilmez.
