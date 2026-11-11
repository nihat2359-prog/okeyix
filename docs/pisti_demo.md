# İki kişilik Pişti geliştirme demosu

Debug uygulamada lobi menüsü → **Pişti • geliştirme demosu**. Release/profile
sürümlerinde giriş yok; demo ekranı ayrıca `kDebugMode` ile korunur.
Servis başlatmadan bağımsız çalıştırma:

```sh
flutter run -t lib/main_pisti_demo.dart -d emulator-5554
```

Chrome da desteklenir: `flutter run -t lib/main_pisti_demo.dart -d chrome`.
Demo menüsü normal oyun, kart toplama, Pişti anı ve el sonunu yeniden başlatır.
Örnekler ekranda **ÖRNEK** olarak etiketlenir. Normal oyun karıştırılmış 52 karttır.

Kartı seç; tekrar dokun veya merkeze sürükle. Rakip yerel basit bir bottur.
Dağıtım, rakip kartının açılması, kart toplama, Pişti vurgusu, sonuç ve yeniden
dağıtma çalışır. Hatalı yere sürüklenen/iptal edilen kart ele döner. Hamle kilidi
ve parmak sahipliği çift hamleyi önler. Arka planda ve kapatılan rotada
animasyonlar durur; çıkışta kaynaklar temizlenir. Ses/titreşim eklenmedi.

## Kurallar

Başlangıçta ortada dört kart (üç kapalı, biri açık), her oyuncuda dört kart vardır.
Açık başlangıç kartı vale olmaz. Oyuncu başlar; sırayla bir kart oynanır. Eller
bitince dörder yeni kart dağıtılır; toplam altı dağıtım vardır. Üsttekiyle aynı
değer veya vale masayı alır. Tek kartı aynı değerle almak 10 Pişti puanı;
tek valeyi başka valeyle almak 20 puandır. Vale ile farklı tek kartı almak
Pişti değildir. Aslar/valeler 1, sinek 2 iki, karo 10 üç puandır. Fazla kartı
toplayan 3 puan alır; eşitlikte bu bonus verilmez. Son masa son toplayana,
hiç toplama olmadıysa dağıtan rakibe gider; son süpürme Pişti sayılmaz.

## Kapsam ve dosyalar

- `lib/dev/pisti/`: bağımsız model, responsive yerleşim, vektör kartlar, oyun sahnesi.
- `lib/main_pisti_demo.dart`: bağımsız debug başlangıcı.
- `lib/ui/lobby/lobby_side_menu.dart`: yalnızca debug giriş ve test için görünürlük seçeneği.
- `test/pisti_*_test.dart`: 17 kart/kural/etkileşim/lifecycle/landscape testi geçti.
- Mevcut menü testine debug giriş/geri dönüş testi eklendi; üretim görünümü
  `showDevelopmentDemos:false` ile test edilir. Eski 640×360 golden, değiştirilmemiş
  Git HEAD'de de tam test sırasıyla aynı arka plan yükleme farkını üretir;
  mevcut golden görseller güncellenmedi.
- `tool/pisti_capture.mjs`: gerçek Flutter Web/Chrome ekran görüntülerini üretir.

Yeni bağımlılık yok. Sayısal kartlar ve yüzey kodla çizilir; J/Q/K için ücretsiz,
LGPL-2.1 SVG-cards figürleri kullanılır. [Kaynak ve lisans kaydı](pisti_card_assets.md).
Mevcut Montserrat ve avatar2/avatar6 varlıkları kullanılır. Okey, ana başlangıç,
Supabase, kimlik doğrulama, ekonomi, ortak tema ve üretim navigasyonu değişmedi.

Görüntüler `build/pisti_demo_captures/` altında. Android debug APK:
`build/app/outputs/flutter-apk/app-debug.apk` (Pişti başlangıcıyla derlendi).
Android emülatörü ve Chrome çalıştırıldı. iOS/fiziksel cihaz performansı doğrulanmadı.
