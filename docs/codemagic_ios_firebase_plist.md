# Codemagic Workflow Editor — iOS Firebase plist

## Proje değişikliği

`ios/Runner.xcodeproj/project.pbxproj` içinde tek plist dosya referansı,
Runner grubuna bağlantı ve Runner Copy Bundle Resources girdisi eklendi.
Kaynak aşaması tüm yapılandırmalarda kullanılır; deployment-only değildir.
Release, Profile ve Archive için ayrı bir plist üretme/kopyalama yolu yoktur.
Signing, entitlements, Podfile, SDK, Android veya uygulama kodu değiştirilmedi.

## Workflow Editor Pre-build

Bu dosyalar ve `tool/codemagic_ios_firebase.sh` aynı commit ile Codemagic'in
derlediği dala gönderilmiş olmalı. `codemagic.yaml` gerekmez.

Environment Variables içindeki `IOS_GOOGLE_SERVICE_INFO_PLIST_B64` ilgili
workflow'a açık olmalı; Secret seçeneğini kullanın. Değeri burada paylaşmayın.
Mevcut entitlements/signing kontrollerini koruyun ve **sonlarına** şunu ekleyin:

```bash
# Firebase plist: keep the existing entitlements/signing checks above.
set +x
bash "${CM_BUILD_DIR:?CM_BUILD_DIR is missing}/tool/codemagic_ios_firebase.sh" prepare || exit 1
```

Script Base64'ü katı biçimde kontrol eder (satır sonlarına izin verir), macOS
base64 ile geçici dosyaya çözer, plutil/PlistBuddy ile geçerli sözlük alanlarını
ve Xcode proje sözdizimini doğrular. Ancak başarılıysa dosyayı atomik olarak
`ios/Runner/GoogleService-Info.plist` konumuna taşır. Eski Git dosyasına fallback
yapmaz. Eksik/değersiz değişken, bozuk Base64/plist, yanlış kimlik veya dosya
yazma hatası derlemeyi durdurur. İçerik ve API anahtarı loglanmaz; tracing kapalıdır.

Kontrol edilen kimlikler mevcut `firebase_options.dart` ile aynıdır:

- BUNDLE_ID: `com.okeyix.game`
- GOOGLE_APP_ID: `1:445431980577:ios:488f00b9d026798bc3f960`
- PROJECT_ID: `okeyix-cf7b4`
- GCM_SENDER_ID: `445431980577`

API_KEY yapısı da kontrol edilir. Plist içindeki hiçbir değer yeniden yazılmaz;
Analytics/Ads bayrakları dahil environment değişkeninin çözülen içeriği korunur.
Firebase projesi ileride bilinçli değiştirilirse script'in kimlik korumaları da
gözden geçirilmelidir.

## Workflow Editor Post-build — yayınlamadan önce doğrulama

Yeni bir Post-build adımına ekleyin (signing işlemini değiştirmez):

```bash
set +x
bash "${CM_BUILD_DIR:?CM_BUILD_DIR is missing}/tool/codemagic_ios_firebase.sh" verify \
  "$CM_BUILD_DIR/build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app" || exit 1
```

Workflow arşivi farklı konuma yazıyorsa ikinci argümanı gerçek Runner.app yolu
ile değiştirin. Bilerek yanlış yolda da başarılı sayılmaz; açık hata verir.
Bu kontrol plist varlığını, formatını, Firebase kimliklerini, uygulamanın gerçek
CFBundleIdentifier değerini ve kaynak dosyayla kritik değerlerin eşitliğini
doğrular. XML/binary plist kabul edilir; uygulama paketini değiştirmez.

Başarılı loglar:

```text
[ios-firebase] Validated Firebase plist prepared for Runner resources.
[ios-firebase] Runner.app contains the expected valid Firebase plist.
```

İndirilen Runner.app.zip içindeki Runner.app kökünde dosyayı ayrıca kontrol edin.
Bir Mac üzerinde açılmış paket de aynı script'in `verify /gercek/yol/Runner.app`
komutuyla doğrulanabilir. Windows'ta binary plist düz metin görünmeyebilir;
bu, dosyanın geçersiz olduğu anlamına gelmez. IPA inceleniyorsa konum
`Payload/Runner.app/GoogleService-Info.plist` olur.

## Git durumu

İnceleme anında plist Git tarafından **takip ediliyordu**. Dosya silinmedi,
indeksten çıkarılmadı ve geçmiş değiştirilmedi. `.gitignore` kuralı eklendi;
ancak ignore kuralı takipteki bir dosyayı takipten çıkarmaz. Dolayısıyla mevcut
dosyanın gelecekteki değişiklikleri hâlâ commit'e girebilir.

Environment tabanlı yapı yeni Codemagic build'inde doğrulandıktan sonra, takipten
çıkarmayı ayrıca seçerseniz şu komut dosyayı diskte tutar:

```bash
git rm --cached -- ios/Runner/GoogleService-Info.plist
```

Bu komut otomatik çalıştırılmadı. Sonraki commit önceki Git geçmişini temizlemez.
Base64 içeriğini veya çözülmüş dosyayı artifact olarak ayrıca yayınlamayın;
uygulama paketindeki Firebase client konfigürasyonu ise doğal olarak pakettedir.

## Yerel doğrulama

```bash
node --test test/ios_firebase_packaging_test.mjs
```

Windows'ta 7 kontrol geçti; macOS araçları gerektiren entegrasyon testi atlandı.
Mac testi geçici bir fixture üzerinde pozitif hazırlamayı, yanlış plist/kimlik
reddini, mevcut dosyanın hata sırasında korunmasını ve XML/binary uygulama
paketi doğrulamasını kapsar. Gerçek Xcode Archive/Codemagic build'i bu ortamda
çalıştırılmadı. Bu düzenleme paketleme sorununu hedefler; tek başına Google Ads
kampanyasının dağıtım/dönüşüm sorunlarının tamamını çözdüğü anlamına gelmez.
