# Güncel ürün kararı — Pişti Molası

31 Ekim 2026: Açılış doğrudan Okey lobisidir. Çok oyunlu ana ekran kaldırıldı. Pişti Molası botla veya mevcut arkadaşla ücretsiz özel maçtır; açık liste, rastgele eşleşme ve kariyer girişi gösterilmez. Oyun sahnesi, puanlar, kart animasyonları, tema, davet ve yeniden bağlanma korunur. Sunucuda casual maçlar coin/ledger/rating değiştirmez. [Güncel teknik rehber](pisti_release.md). Aşağıdaki notlar önceki teslimin tarihsel kaydıdır.

# Oyun merkezi ve Pişti arayüzü

Giriş ve açık oturumun başlangıç hedefi oyun merkezidir. Okey ve Pişti kendi
lobilerini açar; 51 / 81, Batak ve King açıkça Yakında olarak görünür ve masa
açmaz. Blöf ve 101 eklenmedi. Okey lobisinden menüdeki Oyun merkezi veya sistem
geri tuşuyla seçim ekranına dönülür. Okey masasından ayrılma yine Okey lobisini
açar; oradan oyun merkezine erişilebilir.

Mevcut lobi arka planı, Montserrat, saten metal çerçeveler ve yeşil keçe/altın
paleti kullanıldı. Oyun görselleri mevcut gerçek iskambil çizimleri ve farklı
taş/kart kompozisyonlarıdır. Yeni ortak bileşenlerin teması yalnızca oyun
merkezi ve Pişti uygulama katmanlarına uygulanır. Okey'in 2–2–1 lig düzeni ve
kullanılabilir yüksekliği korunur. Yeni görsellerde sürekli animasyon yoktur.

Pişti lobisi, masa listesi, giriş/özel masa seçenekleri, bekleme/hazır/bot,
davet kabul/ret, kurallar, kariyer/geçmiş, sohbet/hediye penceresi, bağlantı ve
bakiye hataları, ayrılma, kapalı masa ve sonuç/rövanş görünümü düzenlendi.
Arkadaş daveti mevcut ortak `GameInviteDialog` bileşenini kullanır; Pişti'de
Okey rating'i veya varsayılan sıfır bakiye gösterilmez. Bileşenin varsayılan
Okey davranışı korunur.

Mevcut tek lobi durumu hesap, coin, profil, arkadaşlar, mağaza, ayarlar,
davet dinleyicileri ve aktif maça dönüşü yönetmeye devam eder. Push dalları
oyun merkezinden geçmeden mevcut doğru oyun akışına gider. Pişti oyun masası,
kartları ve kart animasyonları değiştirilmedi. Backend, kurallar, ücret/ödül
hesapları, migration ve canlı yapılandırma bu çalışma kapsamında değişmedi.

## Doğrulama

- `test/game_world_design_test.dart`: 568×280, 844×390 ve %130 yazıyla 640×320.
  Oyun seçimi, Yakında seçeneklerinin kapalı oluşu, masa ayarı seçimi/vazgeçme,
  davet, hazır/bot, hata ve sonuç katmanları gerçek Flutter widget'larıyla
  görüntülendi; görüntüler açılıp incelendi. Küçük ekran taşmaları düzeltildi.
- `test/pisti_online_test.dart`: ilgili beş mevcut controller/landscape/
  seyirci kontrolü geçti. Yeni görsel testlerin verileri izole fixture'dır;
  bu çalışmada canlıya test hesabı veya maç eklenmedi.
- `test/game_invite_dialog_test.dart`: beş mevcut ortak davet kontrolü geçti.
  Yan menünün Pişti ve Oyun merkezi callback kontrolü geçti.
- Yeni Pişti/ortak arayüz dosyalarında analiz hatası yok. Mevcut ortak davet
  dosyasında önceden bulunan iki süslü parantez stil uyarısı sürer.
- Android debug APK: `build/app/outputs/flutter-apk/app-debug.apk`.

Görüntüler `test/goldens/game_world_*.png` altında bulunur. Örnekler:

- [Oyun merkezi](../test/goldens/game_world_hub_844.png)
- [Pişti masaları](../test/goldens/game_world_tables_844.png)
- [Kısa ekranda masa oluşturma](../test/goldens/game_world_create_568.png)
- [Davet](../test/goldens/game_world_lobby_invite_568.png)
- [Ortak arkadaş seçicisi](../test/goldens/game_world_friend_picker_568.png)
- [Bakiye hatası ve görünür aksiyonlar](../test/goldens/game_world_waiting_error_568.png)
- [Sonuç / rövanş](../test/goldens/game_world_finished_568.png)
- [Kariyer](../test/goldens/game_world_career_568.png)

Görüntüler fiziksel telefon görüntüsü değildir. Cihazda oturum açılışı,
Okey/Pişti arasında geri dönüş, bildirimden doğru oyuna geçiş, aktif maça
yeniden bağlanma ve sohbet klavyesi/mikrofonu ayrıca denenmelidir. Mağazaya
gönderim yapılmadı.

## Masa hazırlığı kararlılık düzeltmesi

Başarılı `leave` sonrası snapshot isteği oyuncuyu artık seyirci olarak görüp
hata veriyordu; ekran bu okuma hatasını ayrılma başarısızlığı sayarak çıkışı
engelliyordu. Başarılı ayrılma artık kesindir; üyelik bitişi ayrıca izlenir ve
eski koltuk için yeniden komut gönderilmez. Üyeliği biten ekranda doğrudan
Lobiye dön düğmesi vardır. Oyun sürerken onaylı hükmen ayrılma korunur.

Hazırlık yönergesi kısa ekranlarda aksiyonların üzerinde sabit görünür.
Ağ istekleri 15 saniyeyle sınırlıdır; belirsiz sonuçlarda aynı request UUID ile
yeniden deneme korunur. `test/pisti_preparation_test.dart` bu hata ve bot/çıkış
akışlarını yeniden üretir. Canlıda yalnızca salt okunur worker/özellik sağlık
kontrolü yapıldı; bu ilk düzeltmede backend veya ekonomi değiştirilmedi.

## Okey tarzı davet ve yeşil masa düzeltmesi

Masa akışı daha sonra kullanıcı talebine göre değiştirildi: coin seçilip masa
açılır ve ikinci oyuncu beklenir. Ayrı Hazırım / Hazır değilim / Botla oyna
düğmeleri kaldırıldı. Oyuncu davet et, ortak Okeyix davet penceresinde uygun
oyuncuları ve botları gösterir. İkinci koltuk dolunca maç otomatik başlar.
Özel masalar normal oyuncular için mevcut arkadaş kısıtını korur.

`20261031000100_pisti_invitation_seating.sql` mevcut canlı projeye uygulandı.
Yalnızca seçilen botu çağırma, açık masaya oyuncu daveti ve üyelik denetimli
davet listesi eklendi. Mevcut komut tanımı `.dart_tool/pisti-install/` altında
saklandı. JWT, kart gizliliği, ücret/ödül hesapları ve Okey akışları değişmedi.
Yerel SQL testleri ve canlı erişim kontrolleri geçti.

Oyun zemini yeşile çevrildi. Çevrimiçi kartın yerel hareketi bırakıldığı/seçili
olduğu yerden başlar; kart sunucu onayına kadar ortada durur ve onayda elden
yeniden uçurulmaz. Kesin ret halinde ele dönüş, belirsiz ağ sonucunda aynı
request UUID ile yeniden deneme korunur. `pisti_online_motion_test.dart`
sürükleme ve iki dokunuşu gecikmeli sunucu onayıyla doğrular.

Güncel APK açık `emulator-5554` emülatörüne yüklendi. Gerçek oturumla coin
seçerek masa oluşturma, hazır düğmeleri olmadan bekleme, canlı davet listesini
açma ve lobiye dönüş görüldü; emülatör görüntüleri de incelendi. Bu kontrolde
ikinci oyuncu davet edilmedi ve maç başlatılmadı. Son sürümde listedeki botlar
BOT etiketiyle ayrılır. Mağazaya gönderim yapılmadı.
