# Oyuncu karşılaştırması ve hikâye paylaşımı

## Uygulama

Mevcut istatistik altyapısı kurulduktan sonra SQL Editor'de yalnız
`supabase/migrations/20261020001000_comparison_mutual_only.sql` dosyasının tamamını
bir kez çalıştırın (009 kurulu olmalı). Önceki migration'ları tekrar çalıştırmayın. Ajan bu dosyayı
canlıya uygulamadı. Yeni Flutter sürümünü RPC kurulduktan sonra dağıtın.

Paylaşım için iOS/Android yerel kod eklendi. Hot reload yeterli değildir; uygulamayı
tam derleyip yeniden kurun. Yeni paket veya kullanıcıdan galeri/depolama izni yoktur.

## Veri sözleşmesi

`okeyix_compare_player(p_opponent_id uuid)` oturum sahibini `auth.uid()` ile
belirler. İstemci iki rastgele oyuncu seçemez. Kendi kendini karşılaştırma,
eksik oyuncu ve anonim erişim reddedilir. Dönen kimlikler istemcide de doğrulanır.
RLS değiştirilmez; private kuyruk için yeni istemci izni verilmez. Fonksiyon
postgres sahibi, SECURITY DEFINER, sabit search_path ile çalışır.

Ekrandaki BÜTÜN sayılar yalnızca bu iki oyuncunun birbirlerine karşı kayıtlı
tamamlanmış elleridir. Genel performans ve `users.wins/losses` dahil değildir.
Henüz projekte edilmemiş sunucu complete olayları aynı snapshot'ta
okunur; kalıcı terminal kaydı bulunan olay tekrar eklenmez. Böylece cron
gecikmesi ve iki kez sayım önlenir. Oyuncu/eldeki mevcut unique kısıtlar korunur.

Skor ve alt detaylar aynı kaynak el kimliğinde iki oyuncunun birbirine karşı
win/loss sonuçlarından gelir. Üçüncü kişilere karşı sonuçlar tüm alanlardan
dışlanır. Started/aborted/draw sayılmaz. Normal bitiş iki bayrak false; okeyli/çiftli
ilgili bayrak true. İki bayrak da true ise iki kategoriye dahildir; tekil el ve
ikili skor yine bir kez sayılır. Boş ikili geçmişte skor ve bütün detaylar sıfırdır;
“Aranızda kayıtlı el yok” gösterilir. Eşit skor beraberliktir. Yanıtın
scope=head_to_head olması ve alt wins/losses değerlerinin üst skorla tam eşleşmesi
istemcide doğrulanır; eski genel sonuçlu 009 yanıtı gösterilmez.

Lig, lobinin kullandığı profiles.rating ve leagues min_rating/max_rating
aralıklarından bulunur. Açık üst sınır yoksa sonraki minimum kullanılır. Profil
rating'i/aralık eşleşmesi yoksa lig uydurulmaz. Avatar mevcut LobbyAvatar
çözümleyicisiyle gerçek kayıtlı avatar veya mevcut kullanıcı başlangıç harfi
görünümüdür.

## Paylaşım

Paylaş düğmesi ayrı 360×640 mantıksal piksel kart önizlemesi açar. Ekran rastgele
yakalanmaz; yalnız kart RepaintBoundary'si 3× oranla 1080×1920 PNG olur. Marka,
isim, avatar, lig ve gerçek ikili skor vardır; UUID, e-posta, coin, token veya
gizli alan yoktur. Avatar/görseller hazır olmadan dışa aktarılmaz; indirme hatası
paylaşımı durdurur. Paylaşım kartına fake veri yerleştirilmez.

`ComparisonImageShare` PNG'yi sadece uygulamanın cache/okeyix_comparisons
dizinine yazar. Android FileProvider yalnız bu dizini geçici okuma izniyle açar;
ACTION_SEND chooser kullanılır. iOS path_provider'ın kullandığı NSCachesDirectory
doğrulanır ve UIActivityViewController açılır; iPad popover için kaynak rect
verilir. Yerel köprü farklı dizinden dosya kabul etmez. Eski kartlar sonraki
paylaşımda temizlenir; zamanlayıcı yoktur. Kullanıcı platform paylaşım panelinden
hedefi kendisi seçer; Instagram'ın her cihaz/sürümde aynı hedefi sunması garanti
edilemez. Otomatik sosyal medya gönderimi yoktur.

## Dosyalar

- lib/services/profile_service.dart: kendi/rakip ayrımı, Karşılaştır aksiyonu.
- lib/models/player_comparison.dart: kimlik, skor ve kayıtlı istatistik modeli.
- lib/services/player_comparison_service.dart: tek okuma isteği, hesap değişimi kontrolü.
- lib/screens/player_comparison_screen.dart: yükleme/hata/yeniden deneme ve rekabet ekranı.
- lib/ui/comparison_arena.dart: avatar/VS/skor, oran şeridi, genel sonuçlar.
- lib/ui/comparison_share_dialog.dart: bağımsız hikâye tasarımı, önizleme, görsel hazırlığı.
- lib/services/comparison_image_share.dart: PNG üretimi ve yerel paylaşım çağrısı.
- android/app/src/main/kotlin/com/okeyix/game/MainActivity.kt: paylaşım kanalı/provider.
- android/app/src/main/AndroidManifest.xml ve res/xml/comparison_share_paths.xml: dar dosya erişimi.
- ios/Runner/AppDelegate.swift: mevcut implicit engine'e bağlı paylaşım kanalı.
- supabase/migrations/20261020000900_player_comparison.sql: güvenli okuma endpoint'i.
- supabase/migrations/20261020001000_comparison_mutual_only.sql: bütün sonuçları ikili ellere sınırlar.
- test/player_comparison_test.dart, test/profile_comparison_integration_test.dart,
  test/statistics/player_comparison.sql: UI, gerçek profil entegrasyonu, PNG/kanal ve SQL regresyonları.
- docs/player_comparison.md ve docs/profile_statistics.md: kurulum ve güncel profil davranışı.

## Kontroller ve cihaz kabulü

Yerel SQL testleri sadece localhost izole fixture veritabanında çalışır ve ROLLBACK
ile biter. Gerçek profili yerel fake HTTP taşıyıcısıyla açan testlerde kendi
kartında düğmenin yokluğu ve doğru rakibe gezinme kontrol edilir. Flutter testleri
küçük yatay ekranlar/güvenli alan/%130 yazı, boş/eşit sonuç, gecikmiş eski istek,
hata/tekrar deneme, 1080×1920 PNG ve paylaşım çağrısını kontrol eder.

Profil/karşılaştırma/oyun/seyirci regresyonları, yeni Dart dosyalarının analizi ve
yerel SQL testleri çalıştırılır. İkili kapsam testi ayrıca üçüncü rakibe karşı
sonuçların hiçbir alt toplamı etkilemediğini doğrular.
Android `:app:compileDebugKotlin` derlemesi doğrulandı. Windows ortamında iOS
derlenemedi. Fiziksel cihazda sistem paylaşım paneli/Instagram hedefleri test
edilmedi; yayın öncesi iPhone yatay, iPad popover ve Android paylaş/iptal akışını
doğrulayın. Avatar internetten yüklenemediğinde tekrar deneme akışını da kontrol
edin. Oyun RPC'leri, mali hesaplar ve istatistik yazıcıları değiştirilmedi.

Yerel platform uygulaması için başvurular:
[Flutter platform channels](https://docs.flutter.dev/platform-integration/platform-channels),
[Android FileProvider](https://developer.android.com/reference/androidx/core/content/FileProvider),
[Apple popover sourceRect](https://developer.apple.com/documentation/uikit/uipopoverpresentationcontroller/sourcerect).
