# Kalıcı istatistik — uygulama paketi

Canlı Supabase üzerinde SQL çalıştırılmadı. İlk iki migration ve geri alma işlemi,
proje içinde oluşturulan izole PostgreSQL 16 kümesinde test edildi. Canlıya
uygulama kullanıcı onayından ve staging kabulünden sonra yapılmalı.

## Uygulama sırası

SQL Editor ile dosyaları ayrı ayrı, aşağıdaki sırayla çalıştır. Eski taslak
`01_functions.sql` ve `02_rollback_tests.sql` dosyalarını uygulama.

1. `supabase/migrations/20261020000100_stat_event_store.sql`
2. `supabase/migrations/20261020000200_stat_game_capture.sql`
3. `supabase/migrations/20261020000300_stat_scheduler.sql`

Bir adım hata verirse sonraki adıma geçme. Dosyalar kendi transaction sınırlarını
kullanır. Özellikle kaynak fonksiyonların hash kontrolü başarısızsa kontrolü
kaldırma; canlı gövde değişmiştir ve entegrasyon yeniden eşleştirilmelidir.
Bu dosyalar mevcut üç istatistik tablosunu gerektirir; yeniden oluşturmaz.
Tüm dosyalar tek seferlik migration'dır; topluca `db push` çalıştırmak yerine
projenin mevcut migration geçmişini ayrıca kontrol et.

Uygulamayı kısa bir bakım aralığında, yeni el dağıtımı durdurulmuşken yap.
Oynanmakta olan ele sonradan başlangıç kaydı uydurulmaz; veri toplama ilk yeni
başarılı dağıtımdan başlar. Kullanıcıların eski uygulama sürümleri aynı RPC
adlarını çağırmaya devam edebilir; Flutter değişikliği gerekmiyor.

## Çalışan akış

- `start_game`, `game_finish`, `leave_table`, `game_timeout_move`, `game_discard`
  adları/argümanları/sonuçları korunur. İncelenen orijinal gövdeler hash ile
  doğrulanıp özel şemadaki `source_*` fonksiyonlarına kopyalanır; ödeme ve oyun
  hesapları bu değişmemiş gövdelerde tam bir kez çalışır.
- Yeni public girişler oturan gerçek kullanıcıyı doğrular. Başka insan adına
  bitiş/hamle ve başka oyuncuyu çıkartma reddedilir. Bot adına bitiş için botun
  o masada ve sırası gelmiş olması gerekir. Timeout mevcut sunucu süre
  doğrulamasından geçer. Güvenilir service_role ve JWT taşımayan doğrudan
  postgres oturumları sunucu çağrısı yapabilir. Anon RPC erişimi kapalıdır;
  Supabase anonim oturum açmış misafirler authenticated rolünü kullanır.
- Orijinal `start_game` kopyası SECURITY INVOKER olarak kalır; dar yetkili public
  sarmalayıcı çağrısı içinde çalışır. İstemciye hiçbir özel istatistik fonksiyonu
  için EXECUTE/şema erişimi açılmaz. Sabit search_path ve public şemasında
  istemci CREATE yetkisi bulunmaması kontrolü uygulanır.
- Yeni kalıcı sonuç tablolarında service_role dahil API rollerine doğrudan DML
  verilmez; yazıcı yalnız postgres bağlamındaki özel işçidir.
- Kaynak masa -> oyuncular -> UUID sırasıyla profiller kilitlenir. Gerçek bakiye
  ve rating farkları aynı transaction içinde, ilgisiz ödeme araya giremeden
  yakalanır. Formül veya nominal wallet tutarı gerçek kesinti yerine kullanılmaz.
- Küçük, tipli `events` ve `event_players` makbuzları özel outbox şemasında
  tutulur. Kalıcı JSON, el dizilimi, hamleler, kullanıcı adı veya token yazılmaz.
  İki ve dört oyunculu mevcut masalar desteklenir.
- Dakikada bir pg_cron, `process_events(250)` çağırır. Her masa için olay sırası
  korunur; bir bozuk masanın olayı diğer masaları durdurmaz. İşçi kilidi oyun
  akışının aldığı kilitlerden ayrıdır. İstemciye yeni timer/poll eklenmez.
- Projeksiyon yalnız üç istatistik tablosuna yazar. Coin/rating veya users
  wins/losses güncellemez. Eski sayaçlarla yeni geçmiş toplanmaz.
- Oyuncu ayrılması ve masayı sıfırlayan timeout `aborted` üretir. Normal timeout
  hamlesi ve yalnız bağlantının kopması eli iptal etmez. Dört kişilik masada
  oyun devam ediyorsa ilk katılımcı kaydı korunur.
- Masa reset/silme trigger'ları ertelenmiştir: başarılı bitişte oyuncular önce
  silinse bile sonuç yanlışlıkla abort olmaz. Masa silinmesi session'ı kapatır;
  kalıcı kayıtların oyun tablolarına FK'si yoktur. Yeni gerçek dağıtım, sonuçsuz
  açık eski istatistik elini kapatır ve oyunu istatistik yüzünden bekletmez.

## Doğruluk ve hata politikası

Kaynak kimlik `table_id:round_count:shuffle_seed`dir. Başlangıç makbuzunda
oyuncu, koltuk, bot ve kesinti birlikte karşılaştırılır. Tekrarlanan bitişte
kazanan, zaman, iki bitiş bayrağı ve bütün mali alanlar aynı olmalı; NULL ile 0
aynı kabul edilmez. Mevcut unique ve deferred winner FK korunur. İşçi yalnız
bu FK'yi kendi hata yakalama sınırında doğrular.

Bu idempotency sınırı istatistik olayları içindir. Eski oyun RPC argümanları
istemcinin beklediği seed'i taşımıyor; daha sonraki yeni bir ele ulaşan eski
istemci isteğini kesin tanıyan yeni bir oyun protokolü eklenmedi. Kaynak oyun
doğrulayıcısı başarılı bir sonuç döndürürse o andaki gerçek kaynak kimliği
kaydedilir; bu paket genel oyun doğrulama sorunlarını çözdüğünü iddia etmez.

Bilinmeyen başlangıç/bitiş bakiyesi ve rating farkı NULL kalır. `coin_net`
generated kolona doğrudan yazılmaz. Eksik bileşen varsa net NULL'dır. İptal
edilmiş ellerde kanıtlanmayan ödül/iade/ceza alanları doldurulmaz.
`game_discard(p_finish=true)` eski ayrı ödeme yoludur; onun gerçekleşen farkı
kaydedilir, game_finish ödül formülü uygulanmaz. Bu yoldaki bayraklar kaynak
eldeki gerçek okey ve sunucudaki çift modu bilgisinden alınır; mevcut eski
solver veya ödeme davranışı değiştirilmez.

Projeksiyon hatası ödemeyi/oyunu geri almaz: makbuz kuyrukta kalır, SQLSTATE
saklanır, 5–300 saniye arası geri çekilerek sonraki dakika tekrar denenir.
Oyun transaction'ı ile makbuzun kendisini yazmak atomiktir: outbox'a yazılamazsa
oyun işlemi de geri alınır. Bu küçük fail-closed sınırı özellikle korunur;
makbuz kaybını sessizce yutup tam istatistik garantisi verilemez.

Kaynak tabloların çoğunda envantere göre RLS kapalı ve istemci DML izinleri
çok geniş. Bu paket o mevcut genel yetki problemini değiştirmez. Doğrudan
kaynak veri manipülasyonuna karşı bütün oyunun güvenli olduğunu iddia etmez;
sonuç üreten RPC yollarını korur, istatistik tablolarını istemciye yazdırmaz.

Mevcut ses silme trigger tanımında gömülü service_role anahtarı bulundu.
Anahtar yeni dosyalara kopyalanmadı. Anahtarı Supabase üzerinden yenilemek ve
mevcut ses temizleme yetkilendirmesini buna göre güncellemek ayrı bir canlı
operasyon gerektirir; bu görev sırasında uygulanmadı.

## Yerel testler

`test/statistics/prepare_fixture.ps1`, kullanıcının envanter dosyasından
`.dart_tool/statistics_fixture.sql` oluşturur. Yalnız beş oyun fonksiyonunu ve
oyuncu sayısı trigger'ını alır; ses/ağ trigger'larını ve anahtarları kopyalamaz.
Kaynak auth/lig FK bağımlılıkları fixture'da çıkarılmıştır. Üç kalıcı tablonun
check/unique/partial-index ve tüm FK'leri korunmuştur. Bitiş solver'ları
entegrasyon için deterministik stub'dır; gerçek taş doğrulaması test edilmez.

İzole küme yolu `.dart_tool/statistics_pg`, adres `127.0.0.1:55439`; veritabanı
adı `okeyix_stat_test_` ile başlamalıdır. Test SQL'ini canlı SQL Editor'e yapıştırma.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File test/statistics/prepare_fixture.ps1 -InventoryPath '<yerel envanter dosyası>' -OutputPath '<proje>/.dart_tool/statistics_fixture.sql'
# Yeni, boş yerel test veritabanında; bağlantı argümanlarını daima açıkça ver:
psql -X -h 127.0.0.1 -p 55439 -U postgres -d okeyix_stat_test_YENI -v ON_ERROR_STOP=1 -f .dart_tool/statistics_fixture.sql -f supabase/migrations/20261020000100_stat_event_store.sql -f supabase/migrations/20261020000200_stat_game_capture.sql -f test/statistics/integration.sql
powershell -NoProfile -ExecutionPolicy Bypass -File test/statistics/concurrency.ps1 -Database okeyix_stat_test_YENI
```

Entegrasyon testi sonunda ROLLBACK yapar. Eşzamanlılık testi yalnız yerel
fixture kayıtlarını COMMIT eder ve aynı boş veritabanında bir kez çalıştırılır.
Normal, yalnız okey, yalnız çift, ikisi birlikte, bot, dört kişi, düşük bakiyeli
oyuncu çıkarılması, NULL/eksik profil, invalid finish, replay çelişkisi,
normal/üçüncü timeout, leave, masa silme, eski elin yenilenmesi, kayıt hatası,
projeksiyon retry, gerçek authenticated rolü ve RLS sınamaları bulunur.
İki bağlantıda start/finish/worker yarışları ayrıca test edilir.

Geri alma `04_pause_and_restore.sql` ile yerelde test edildi: beş orijinal
fonksiyon gövdesi ve SECURITY INVOKER/DEFINER nitelikleri hash'leriyle birebir
geri geldi. Yeni tarihçe/makbuzlar silinmez. Canlıda pg_cron zamanlayıcısının
çalışması, gerçek solver'lar ve ses/storage trigger etkileşimi staging kabul
kapsamındadır; Windows yerel PostgreSQL'de pg_cron kurulu değildir.

## Uygulama sonrası kontrol ve geri alma

`05_read_only_health.sql` yalnız SELECT içerir. Kuyruk büyüklüğü/yaşı,
başarısız olaylar, isimli cron görevi ve üç tablonun sayısal tutarlılık
özetlerini gösterir. Yaklaşık bir dakika projeksiyon gecikmesi normaldir;
kuyruk birikiyorsa kullanıcı sayaçlarına ekleme veya sahte sonuç üretme.

Geri alma gerekirse yeni RPC trafiğini durdurup `04_pause_and_restore.sql`
dosyasını uygula. Bu dosya otomatik migration değildir; izin verilen bakım
operasyonudur. Cron işini durdurur, yeni trigger'ları kaldırır, orijinal RPC
kodlarını ve execute izinlerini geri getirir. Kalıcı geçmişi/makbuzları silmez.
Geri alınmış kurulumu tekrar açmak ayrıca gözden geçirilmiş bir ileri migration
ister; ilk iki dosyayı körlemesine tekrar çalıştırma.

## Masa skorunun gecikmesiz okunması

Masa göstergesi için `20261020000400_my_table_score.sql` okuma RPC'sini oluşturur.
Ardından `20261020000500_my_table_score_live.sql` aynı endpoint'i günceller.
004 zaten uygulanmışsa yalnız 005 çalıştırılır; bu dosya canlıya ajan tarafından
uygulanmadı. Flutter çağrısı ve mevcut 2 saniyelik masa yenilemesi değişmez.

005 yalnız oturum açmış kullanıcının bu masadaki tamamlanmış sonuçlarını okur.
Kalıcı geçmişe henüz aktarılmamış, sunucunun kesinleştirdiği `complete` olayları
da sayılır. Kaynak anahtarı kalıcı terminal kayıtta varsa kuyruk kopyası sayılmaz.
Okuma tek statement/snapshot kullanır; cron'un aktarımı çift sayım oluşturmaz.
Başlangıç/iptal olayları sayılmaz, kariyer toplamı okunmaz ve skor RPC'si hiçbir
yazıcı çağırmaz. Özel outbox erişimi sadece postgres sahibi SECURITY DEFINER
fonksiyonunun içindedir; istemciye özel şema/tablo erişimi açılmaz. Kimlik
auth.uid() üzerinden alınır; başka kullanıcı kimliği argümanı kabul edilmez.

Yerel PostgreSQL testleri: `test/statistics/my_table_score_live.sql` ve
`test/statistics/my_table_score.sql`. Kuyruk öncesi/sonrası skor, aktarımda
mükerrer saymama, yeni sonuç + eski geçmiş, başka kullanıcı/masa ayrımı ve
yetki sınırları doğrulandı. Her iki test fixture verilerini ROLLBACK eder.

## Seyirci göstergesi

`20261020000600_spectator_table_scores.sql`, masanın kayıtlı seyircisine veya
oturan oyuncusuna yalnız mevcut 0/1 koltuklarının bu oturumdaki skorlarını verir.
Seyirci için spectators_enabled açık olmalıdır. Kalıcı sonuçlar ve henüz
aktarılmamış kesinleşmiş bitişler, 005'teki aynı kaynak anahtarıyla tek sayılır.
İstemci özel tablolara erişemez. Bu migration canlıya ajan tarafından uygulanmadı.

Seyirci ekranı skorları ilk yükleme/üyelik, mevcut masa Realtime güncellemeleri,
oyuncu giriş/çıkışı ve yeniden bağlantıda okur; yeni periyodik sorgu eklenmedi.
Lobi arka planı ekranı dolduran Flutter katmanındadır. Flame saydamdır; mevcut
16:9 kamera ve taş/animasyon koordinatları korunmuştur.
Testler: `test/spectator_table_scores_test.dart`,
`test/statistics/spectator_table_scores.sql` ve mevcut oyun lifecycle testleri.

Teknik başvurular: [PostgreSQL SECURITY DEFINER](https://www.postgresql.org/docs/16/sql-createfunction.html),
[pg_cron](https://github.com/citusdata/pg_cron).
