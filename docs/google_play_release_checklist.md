# Google Play Yayın Hazırlığı (Android)

Bu proje için temel release altyapısı hazırlandı:
- `pubspec.yaml` mevcut: `[/pubspec.yaml](c:/Users/nihat/okeyix/pubspec.yaml)`
- Android release signing desteği eklendi: `[/android/app/build.gradle.kts](c:/Users/nihat/okeyix/android/app/build.gradle.kts)`
- Örnek key dosyası eklendi: `[/android/key.properties.example](c:/Users/nihat/okeyix/android/key.properties.example)`

## 1) Uygulama kimliği (zorunlu)
- Şu an `applicationId`: `com.example.okeyix`
- Play'e çıkmadan önce benzersiz bir kimlik verin (ör: `com.okeyix.game`)
- Dosya: `[/android/app/build.gradle.kts](c:/Users/nihat/okeyix/android/app/build.gradle.kts)`

## 2) Release imza anahtarı
PowerShell:

```powershell
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Sonra:
1. `android/key.properties.example` dosyasını `android/key.properties` olarak kopyalayın
2. Şifre/alias değerlerini doldurun
3. `storeFile` yolunu kontrol edin (`../upload-keystore.jks`)

## 3) Uygulama ikonları
Bu proje `flutter_launcher_icons` ile ayarlı:
- kaynak: `assets/images/app_icon.png`

Komut:

```powershell
flutter pub get
dart run flutter_launcher_icons
```

## 4) Sürümleme
Play yüklemesi öncesi sürümü artırın:
- Dosya: `pubspec.yaml`
- Örnek: `version: 1.0.1+2`

## 5) App Bundle üretimi (Play için)
```powershell
flutter clean
flutter pub get
flutter build appbundle --release
```

Çıktı:
- `build/app/outputs/bundle/release/app-release.aab`

## 6) Play Console zorunlu içerikler
- Uygulama adı / kısa açıklama / tam açıklama
- Gizlilik Politikası URL
- İletişim e-posta
- Veri güvenliği (Data Safety) formu
- İçerik derecelendirme (Content Rating)
- Hedef kitle / reklam beyanı

## 7) Görsel varlıklar (minimum)
- Uygulama simgesi: 512x512 (PNG)
- Feature graphic: 1024x500
- Telefon ekran görüntüleri: en az 2 adet
- (Opsiyonel) 7"/10" tablet ekran görüntüleri

## 8) Test önerisi
- Internal testing ile ilk yükleme
- Giriş, masa açma, masa katılma, oyun turu, sohbet ve satın alma akışlarını test edin
- ANR/Crash kontrolü için Android Vitals izleyin
