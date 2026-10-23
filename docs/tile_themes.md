# Taş Temaları

## Kullanım ve kapsam

Lobi → Menü → Ayarlar → **Taş Temaları**. Altı kartta dört mantıksal rengin
gerçek taş PNG'siyle önizlemesi gösterilir. Dokunmak anında uygular ve yerel
olarak kaydeder. Seçim yalnızca bu uygulama kurulumunun ekranlarını etkiler;
rakibe veya Supabase'e gönderilmez. Varsayılan Klasik Porselen'dir.

Mevcut diğer ayarlar gibi `SharedPreferences` kullanılır:
`settings.tile_theme`. Bilinmeyen/eski bir değer klasik temaya döner.
Arka arkaya seçimlerin yazımı sıralıdır; en son seçim kalıcı olur.
Yazma başarısızsa seçim ekranı yeniden deneme mesajı gösterir.
Oyun içinden seçim yapıldığında kayıt başarılı olduktan sonra tema seçici ve
alttaki Ayarlar birlikte kapanır; masa görünür. Seçmeden kapatmak Ayarlar'a döner.
Eski Şampanya/Antrasit/Lavanta Gri kayıtları sırasıyla Zümrüt Yeşili/Koyu Sarı/Pembe'ye
eşlenir. Klasik, Gece Mavisi ve Bordo kayıtları değişmez.
Önceki Turkuaz/Bakır kayıtları da Koyu Sarı/Pembe'ye eşlenir.

## İncelenen mimari ve değişiklik

- Ön yüz `assets/images/tile_base.png`, arka yüz `tile_back.png`.
  Flame `Images` önbelleğinden mevcut yöntemle yüklenir.
- `TileComponent`: Montserrat rakamlar, ayrı parlama metni, `TileGemBadge`
  renk noktası, `TileSurfaceFx` yüzey cilası. Gerçek okeyin ters gösterimi korunur;
  arka yüz rengi de seçili temaya uyar.
  sahte okeyin mevcut altın madalyon/yıldızı korunur.
- `IndicatorComponent`: ayrı taban, rakam ve nokta. Klasik gösterge çizimi
  değişmez; diğer temalarda aynı merkezi paleti kullanır.
- `CachedDecoration`: boyut ve anahtara bağlı `ui.Picture` önbelleği.
  Dosya değiştirilmedi. Tema değişimi yüzey bileşenlerini veya önbelleklerini
  sökmez; yalnızca sprite filtresi ve metin/nokta boyalarını günceller.
- Mevcut Ayarlar (`GameSettingsScene`) ve profil düzenleyicinin koyu cam/metal,
  altın vurgu ve yatay yerleşimi incelendi. Ayarlar altına giriş eklendi;
  profil düzenleme işlevleri değiştirilmedi.

Klasik tema filtresizdir. Diğerlerinde aynı PNG'nin RGB parlaklığı renk matrisiyle
yeniden eşlenir; alfa, kabartma, çerçeve, gölge ve doku kaynak görselden gelir.
Yeni PNG varyasyonu, paket, veritabanı tablosu veya migration gerekmedi.
Altı ayrı bitmap/taş atlası oluşturulmaz. Matris yalnızca temayı uygularken
oluşturulur; her karede yeni resim veya `ui.Picture` üretilmez.

Rakam ve nokta her taşta aynı palet değerini kullanır. Renk körü modu da korunur:
sarı grup açık temalarda mevcut yeşil, koyu temalarda açık nane yeşili olur.

## Paletler

Değerler sırasıyla yüzey üst tonu ve kırmızı/mavi/siyah/sarı mürekkeptir.
Klasik yüzey tonu referanstır; klasik PNG'ye renk filtresi uygulanmaz.

| Tema | Yüzey | Kırmızı | Mavi | Siyah grubu | Sarı |
|---|---|---|---|---|---|
| Klasik Porselen | `#F4F0E5` | `#D12B3F` | `#1F5BFF` | `#1A1A1A` | `#AA7B12` |
| Zümrüt Yeşili | `#225124` | `#FFA1B0` | `#80D6FF` | `#F0F7F2` | `#FFE56E` |
| Gece Mavisi | `#243752` | `#FF9BAD` | `#70CFFF` | `#F0F3FF` | `#FFDF63` |
| Bordo | `#581F30` | `#FFA4B6` | `#80D6FF` | `#F6EDF3` | `#FFE16B` |
| Koyu Sarı | `#C69A24` | `#CE0038` | `#124BEB` | `#11120E` | `#FFEE49` |
| Pembe | `#E78FB5` | `#B90038` | `#063BBE` | `#16121A` | `#FFEE49` |

Koyu paletlerde mürekkep/yüzey temel kontrastı en az **4.5:1**; açık paletlerde
en az **3:1** test edilir. Sarı ve pembede canlı mürekkepler ince zıt renkli
konturla çizilir; bu iki palette dolgu/kontur kontrastı ölçülür. Bu, renk çiftlerinin sayısal kontrolüdür;
dokulu/cilalı taşın her pikseli veya gerçek cihaz ekranı için ölçüm değildir.
Ek test, yeni beş temada gerçek PNG + mevcut cila/gölge katmanını rasterize edip
rakam ve nokta konumlarındaki dört zemin örneğinde kontursuz temaların
zemin/mürekkep, konturlu sarı ve pembenin dolgu/kontur kontrastını en az **4.5:1**
olarak doğrular. Renk körü modunun yeşil mürekkebi de bu kontrole dahildir.
Sarı ve pembe zemin tonları değişmedi; testte eski yüzey/gölge değerleri sabitlendi.
Klasik tema, mevcut sarı konturu dahil korunur.

## Dosyalar

Yeni kaynaklar:

- `lib/game/tile_theme.dart`: altı palet, renk eşlemesi ve yüzey filtreleri.
- `lib/services/tile_theme_service.dart`: yerel kayıt ve değişim bildirimi.
- `lib/ui/tile_themes_dialog.dart`: yatay seçim ekranı ve dört renkli önizlemeler.

Entegrasyon:

- `lib/main.dart`: kayıtlı tercihi ilk ekran öncesinde yükler.
- `lib/game/rack/tile_component.dart`: canlı boya güncellemesi ve listener temizliği.
- `lib/game/components/indicator_component.dart`: gösterge teması.
- `lib/ui/lobby/lobby_utility_scenes.dart`: Ayarlar girişi.
- `lib/ui/game_settings_dialog.dart`: aynı Ayarlar ekranının oyun içi kullanımı.
- `lib/screens/okey_game_screen.dart`: solda eski mikrofon yerinde Ayarlar;
  mikrofon sağ barın en sağında, bar ölçüleri korunur.
- `lib/game/components/closed_pile_component.dart`: üst üste deste ve sayının
  tema/kontrast güncellemesi; mevcut `ui.Picture` anahtarıyla yenileme.
  Sayı plakası/çerçevesi kaldırıldı; 48 punto sayı üstteki taşın merkezindedir.
- `lib/game/components/themed_tile_back.dart`: seyirci destesi ve rakibin çekiş
  animasyonunda kullanılan, gizli taş kimliği taşımayan ortak arka yüz çizimi.
- `lib/game/okey_game.dart` ve `lib/game/spectator_game.dart`: bu ortak çizime geçiş.

Test ve görseller:

- `test/tile_themes_test.dart`: palet/kontrast, varsayılan ve kalıcılık,
  hızlı seçim, ayarlardan açılış, 480×270 / 568×320 / 844×390 güvenli alanlı
  önizlemeler, gerçek Flame taşları/gösterge/okey, nokta-rakam eşleşmesi,
  hareket efekti ve slot korunması, yüzey bileşeninin korunması.
- `test/goldens/tile_themes_844x390.png`: altı temanın görsel referansı.
- `test/goldens/settings_640x360.png`: yeni giriş eklenmiş Ayarlar referansı.
- `test/deck_theme_settings_test.dart`: kapalı deste/çekiş önizlemesi ve sayı
  renkleri, önbelleğin yalnızca tema değişiminde yeniden kaydedilmesi,
  küçük yatay ekranda oyun içi ayarlar → tema seçimi ve renk körü tercihi.

Oyun kuralları, dağıtım, RPC/senkronizasyon, ekonomi, taş ölçüsü (90×118),
ıstaka slotları ve animasyon hesapları değiştirilmedi.

## Doğrulama ve sınırlar

İlgili tema, taş kimliği/hareket, bitiş ıstakası ve ayarlar testleri normal
modda çalıştırıldı: kapalı deste/oyun içi ayarlar ve gerçek PNG kontrast kontrolleriyle birlikte **48/48 başarılı**.
Klasik bitiş görsel referansları değiştirilmedi.
Web üretim derlemesi ve Android debug APK derlemesi başarılı. Analizde derleme hatası yok; mevcut
kullanılmayan kod/deprecation uyarıları ayrı tutuldu.

Çalıştırma çıktıları `.dart_tool/tile_theme_*` dosyalarındadır. Tam test
paketinde tema kapsamı dışında kalan lobi/giriş/masa açma görsel referansları
ve `game_ui_pulse_test.dart` avatar taşmaları ayrıca raporlanır;
bu dosyaların davranışı bu görev kapsamında değiştirilmedi.

Son tam paket çalışması: **493 başarılı / 8 başarısız**. Kalan 8 hata:
`create_table_scene_test.dart`, `login_start_scene_test.dart` ve
`lobby_presentation_test.dart` içinde ikişer eski görsel referans farkı;
`game_ui_pulse_test.dart` içinde iki avatar yatay taşma hatası.
Bu hatalar taş teması/gösterge/önbellek testlerinden gelmiyor.

Kontrol komutları:

```text
flutter test --no-pub test/tile_themes_test.dart test/tile_visual_identity_test.dart test/finish_rack_alignment_test.dart test/lobby_utility_scenes_test.dart
flutter test --no-pub
flutter build web --no-pub
flutter build apk --debug --no-pub
```

Gerçek Android/iOS cihazında FPS, sürükleme sırasında tema değişimi, renk
algısı ve GPU filtre davranışı ayrıca kontrol edilmelidir. Windows üzerinde
iOS derlemesi/simülatörü çalıştırılmadı. Widget/Flame testleri gerçek cihaz
performans ölçümü yerine geçmez.
