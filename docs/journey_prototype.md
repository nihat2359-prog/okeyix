# Okeyix Yolculuk — çevrimdışı 3D prototip

Lobinin alt barındaki **Yolculuk**, ayrı bir Flutter rotasını açar. Android
WebView / iOS WKWebView içinde yerel Three.js r160, WebGL üzerinden gerçek
perspektifli geometri çizer. Flame oyun masası ve Supabase kullanılmaz.

`assets/journey/index.html` yalnızca paketlenmiş dosyaları yükler. Ağ isteği,
uzaktan script, kullanıcı kimliği, ödeme ve kalıcı oyun durumu yoktur.
Sahnenin bütün modelleri, malzemeleri ve dokuları kodla üretilmiştir.
Three.js MIT lisansı `assets/journey/vendor/THREE-LICENSE.txt` içindedir;
kaynak: https://github.com/mrdoob/three.js/tree/r160 . Motor yaklaşık 670 KB
ham JavaScript ekler; APK/IPA sıkıştırılmış boyut farkı ölçülmedi.

## Deneme

1. `flutter pub get` ardından uygulamayı **tamamen yeniden derleyin**; yalnızca
   hot reload yeni yerel WebView eklentisini kaydetmez.
2. Lobiden Yolculuk'u açın. Kamera girişini, sürüklemeyi ve iki parmakla
   yakınlaşmayı deneyin. Kafeye dokunmak kamerayı yaklaştırır; karaktere dokunmak
   şampiyon panelini açar. Meydan Oku yalnızca prototip bildirimi gösterir.
3. Pusula kamerayı sıfırlar; geri düğmesi lobiye döner. Arka plana alınca sahne
   durur, rota kapanınca GPU kaynakları serbest bırakılır.

Yerel kontroller:

```text
flutter test --no-pub test/journey_screen_test.dart test/lobby_presentation_test.dart
dart analyze lib/screens/journey_screen.dart test/journey_screen_test.dart
node tool/journey_render_test.mjs
```

Son komut Node 22 ve yerel Chrome kullanır (`CHROME` ortam değişkeniyle yol
verilebilir). 1000×560, 480×270 ve 844×390 WebGL görüntülerini
`.dart_tool/journey/` içine yazar. Gerçek üçgen çizimi, kamera, karaktere ray
ile tıklama, JS–Flutter mesaj sözleşmesi, duraklatma ve temizliği doğrular.
Bu test masaüstü yazılımsal WebGL kullanır; telefon FPS ölçümü değildir.
Flutter widget testi küçük yatay boyutlarda navigasyon/geri dönüşü doğrular;
yerel mobil platform görünümünün render testi değildir.

## Sınırlar

- Stilize prosedürel görsel prototip; fotogerçekçi veya hazır AAA varlıklar yok.
- DPR en çok 1.5, tek 1024² gölge haritası, statik geometri malzemeye göre
  gruplanır; pahalı postprocess/reflection pass kullanılmaz. Dalgalı su
  prosedürel shader kullanır, fiziksel yansıma değildir.
- Kamera belirlenmiş dış yörüngede tutulur; serbest yürüme/çarpışma motoru yok.
- Android/iOS sistem WebView sürümü ve GPU WebGL desteği gerektirir. Flutter
  web ve Windows için yanıltıcı 2D yedek sahne yerine açıklama gösterilir.
- Fiziksel Android cihaz testi ve iOS derleme/cihaz testi yapılmadı. iOS,
  macOS/Xcode üzerinde normal CocoaPods/Flutter derlemesiyle doğrulanmalı.
- Oyun, gerçek bot zekâsı, ödül, liderlik veya veritabanı eklenmedi.

Teknoloji belgeleri: https://pub.dev/packages/webview_flutter ve
https://threejs.org/docs/pages/WebGLRenderer.html .
