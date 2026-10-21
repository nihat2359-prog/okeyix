# Okeyix bot motoru geliştirme raporu

> Bu rapor ilk sürümü belgeliyor. Güncel çekiş puanlama, yürütme bütçesi,
> tanılama ve 192 maç ölçümleri için `bot_draw_integration_audit.md` dosyasını
> okuyun; aşağıdaki sekiz tür örneklemesi ve 180 ms toplam çekiş bütçesi değişti.

## Kapsam ve dosyalar

- `lib/game/bot/bot_observation.dart`: normal/gerçek/sahte okey, fiziksel kimlik,
  yalnızca izinli gözlem, açık geçmiş projeksiyonu ve görünür kopya sayımı.
- `lib/game/bot/bot_engine.dart`: saf, sınırlandırılmış el optimizasyonu ve karar.
- `lib/game/bot/bot_runner.dart`: native isolate yürütmesi, deadline ve güvenli
  yedek karar, bitiş iş sonucu ve eski el/sıra kontrolleri.
- `lib/game/bot/okey_bot_turn.dart`: OkeyGame'in dar kapsamlı ağ adaptörü.
- `lib/game/okey_game.dart`: bot sırasını yeni adaptöre yönlendirme, bot test
  taşıması enjeksiyonu, eski 15/14 taş kontrolünün düzeltilmesi. İnsanların
  bitiş/dizme akışı, Flame kamera/animasyonları ve oyun kuralları değiştirilmedi.
- `supabase/migrations/20261021000300_bot_pairs_mode.sql`: uygulanmamış, sınırlı
  ve yetkilendirilmiş bot çiftli mod geçişi. Mevcut RPC'leri değiştirmez.
- `test/bot_engine_test.dart`, `test/bot_generated_test.dart`,
  `test/bot_turn_integration_test.dart`: karar, kurallar, güvenlik ve gerçek adaptör.
- `test/support/legacy_bot_policy.dart`: eski politikanın çevrimdışı test kopyası.
  Çekiş öncesi strateji, hazır grup koruması, 8/12 adımlık hafıza ve eski bitiş
  araması korunur. Ağ gecikmesi/hatası bu karşılaştırma politikasına dahil değildir.
- `tool/bot_benchmark.dart`: tohumlu, koltukları değiştirilmiş tarafsız maç düzeneği.
- `pubspec.yaml` / `pubspec.lock`: mevcut transitif `http 1.6.0` yalnızca testlerde
  doğrudan kullanıldığı için açık dev bağımlılığı yapıldı; yeni runtime paket yok.
- `docs/bot_benchmark_results.json`: iki ölçüm kümesinin gerçek çıktıları.

## Doğrulanan yerel kural sözleşmesi

Dayanaklar: `docs/supabase_game_rpc.sql`, `docs/supabase_game_finish_full.sql`,
`docs/supabase_game_finish_invalid_tiles_patch.sql` ve mevcut istemci doğrulaması.
Canlı fonksiyon gövdeleri veya canlı RLS bu görevde okunmadı/değiştirilmedi.

- 14 taş tutulur; çekişle/ilk dağıtımda 15 taş oluşur, bitişte bir taş ayrılır.
- Per aynı sayı ve farklı renklerden oluşur; uzunluğu 3 veya 4'tür.
- Seri aynı renk ve farklı sayılardan oluşur; gerçek okey boşluk doldurur.
- 1, yüksek uçta 14 olarak kullanılabilir: 12–13–1 geçerlidir; 13–1–2 değildir.
- Sahte okey serbest joker değildir; göstergeye bağlı sabit renk/sayıdır.
- Çiftli modda 14 taş yedi çift olarak doğrulanır. Gerçek okey tek taşı veya diğer
  gerçek okeyi eşleyebilir; sahte okey sabit renk/sayı olarak eşlenir.
- Yerel ödül SQL'inde okeyli VEYA çiftli bitiş potu kazandırır; iki bonus toplanmaz.
  Motor bu nedenle hayali bir ekstra çarpan üretmez.

## Karar motoru

Her fiziksel taş bir bit ile temsil edilir. Geçerli per/seri alt kümeleri
üretilir; memoization aynı alt elin tekrar hesaplanmasını önler. Gruplar ve
tamamlanabilir ikililer ayrık maskelerle seçilir: aynı fiziksel taş iki yerde
kullanılamaz. Uzun yasal seriler 3–5 taşlık yasal alt serilere ayrılabildiği için
arama bu uzunluklarla sınırlıdır. Aynı renkte aynı sayının iki fiziksel kopyasını
tek seriye/per içine sokan dallar erkenden elenir.

Her yasal atış adayı değerlendirilir; hazır grupları koşulsuz koruyan filtre aktif
bot yolundan çıkarıldı. Tam gruplar, görünür kopyaları tükenmemiş tamamlayıcılar,
joker esnekliği ve çift potansiyeli birlikte değerlendirilir. Bu bir tamamlanma
potansiyeli yaklaşımıdır; **matematiksel olarak kesin minimum çekiş sayısı veya
kalibre edilmiş kazanma olasılığı değildir**.

Çekişte önce yerdeki taşla yasal bitiş aranır. Ardından aynı atış motoruyla en iyi
kalan el hesaplanır. Kapalı çekiş için gerçek deste okunmaz: bilinmeyen taş
türleri kalan kopyalarla ağırlıklandırılır. Hesaplama bütçesi nedeniyle bağlantısı
en güçlü sekiz çekiş türü ayrıntılı değerlendirilir; diğerleri mevcut eli koruma
taban değerini kullanır. Bu, kapalı çekişin sınırlı ve yaklaşık beklentisidir;
tam dağılım veya çok hamleli Monte Carlo araması değildir.

Bitiş araması stratejik atıştan önce yapılır. Gerçek okeyi atarak bitmek mümkünse
normal bitişe tercih edilir. Çiftli bitiş de aynı fiziksel taşlarla aranır.
Çift potansiyeli normal oyunla karşılaştırılır, fakat geri alınamaz mod geçişi
yalnızca yedi çift gerçekten hazırken sunucu tarafından onaylatılır.

## Açık geçmiş, savunma ve evre

`table_discards` üzerinden yalnızca `id,seat_index,tile,drawn_at,
drawn_by_user_id,created_at` okunur. Her bot sırası için bir kez okunur; ayrı
polling eklenmedi. Mevcut start/finish SQL sözleşmesi bu geçmişi her yeni elde
temizler. Yeniden bağlanmada elde kalan açık geçmiş tekrar projekte edilir;
istemciye özel eski hafıza taşınmaz. Ağ/RLS hatasında geçmiş boş kabul edilir.

Taş atılıp alınıp yeniden atılsa da fiziksel kimliğiyle bir kere sayılır. Kendi
eline geçen açık taş da geçmişle iki kez sayılmaz. Görünür kopyaları bitmiş
tamamlayıcılara umut puanı verilmez. Bilinmeyen havuzun rakipteki gizli taşları
da içermesi normaldir; bot bunların gerçekte nerede olduğunu bilmez.

Rakibin aldığı ve henüz yeniden atmadığı açık taşların yakın sayıları ve aynı
sayıdaki farklı renkler sınırlı risk puanı oluşturur. Bu kesin ihtiyaç bilgisi
sayılmaz. Savunma cezası sınırlandırılmıştır; bot kendi hazır elini yalnızca bir
tahmin için feda etmez. Deste azaldıkça esneklik ağırlığı azalır ve savunma artar;
sabit bir tur sayısı eşiği kullanılmaz. Bu hafif model, öğrenilmiş rakip modeli
veya profesyonel oyuncu stratejisinin tamamı değildir.

## İşlem güvenliği ve performans

- Hesaplamadan sonra yerel el dönemi, sıra ve başlangıç zamanı kontrol edilir.
- Çekiş/atış/bitiş öncesinde sunucudaki sıra ve el tekrar doğrulanır.
- `game_finish` için exception kadar `ok:false` da başarısız sayılır.
- Çekiş/bitiş yanıtı kaybolduğunda ikinci işlemden önce durum okunur. Tamamlanmış
  çekiş için ikinci çekiş; tamamlanmış bitiş için fazladan atış gönderilmez.
- Native Flutter'da hesaplama `compute` ile isolate içinde yapılır. Motorun
  60.000 düğüm / yaklaşık 180 ms bütçesi ve taşımanın 750 ms deadline'ı vardır.
  Kontroller aralıklıdır; bunlar gerçek zamanlı işletim sistemi garantisi değildir.
- Web `compute` paralel isolate sağlamadığı için 12.000 düğüm / yaklaşık 12 ms
  arama kullanır. Ağır ellerde web daha sık güvenli yedek karara dönebilir.
- Arama tükenince elde bulunan gerçek bir taş seçilir; kazanma sonucu uydurulmaz.
  Kısmen tamamlanan çekiş karşılaştırması en son güvenli adayını korur.
- Tercih eşitlikleri fiziksel kimlikle belirlenir; normal bütçe içinde aynı gözlem
  aynı sonucu verir. İşletim sistemi deadline'ına düşme güçlü karar yerine yedek
  karara yol açabilir. `seed` alanı ayrılmıştır; motor şu an rastgelelik kullanmaz.

## Adalet sınırı ve devam eden sunucu riski

Saf motorda Supabase, Flutter, OkeyGame veya tam masa durumuna bağımlılık yoktur.
`BotObservation` rakip eli, gizli deste sırası veya RNG alanı barındırmaz. Taşıma
adaptörü desteden yalnızca açık gösterge ve taş sayısını aktarır. Gizli el/deste
değişmezlik testleri ile açık sütun projeksiyonu testleri bulunur.

**Bununla beraber bot hâlâ insan istemcisinde yürütülüyor.** Mevcut mimarinin bot
elini ve kapalı deste kimliklerini insan istemcisine verebilme riski bu değişiklikle
tamamen kapanmaz. Canlı RLS ve mevcut RPC yetkileri doğrulanmadan tablo erişimini
kapatmak çalışan oyunu bozabilir. Üretim güvenliği için ayrı güvenilir bot işçisi,
bot elini yalnızca bu işçiye veren sözleşme, sunucu tarafı hamle sahipliği ve normal
istemcilere yalnızca gösterge/deste sayısı veren veri sözleşmesi gereklidir.
Bu geçiş bu görevde üretime uygulanmadı. “İstemcide gizli bilgi sızıntısı artık
imkânsız” veya “mutlak hile garantisi” iddiası yoktur.

## SQL uygulama ve staging adımları

1. Yerel kural dosyalarıyla canlı/staging bitiş ve çiftli doğrulayıcının uyumunu
   yetkili ortamda doğrulayın. Fonksiyon gövdelerini veya oyuncu ellerini paylaşmayın.
2. `20261021000300_bot_pairs_mode.sql` dosyasını **önce staging'de** postgres ile
   uygulayın. Migration mevcut `_okey_is_pairs_finish(jsonb)` olmadan durur.
3. Authenticated, masaya oturmuş insanın yalnızca sırası gelen bot adına ve
   sunucunun gerçek 15 taşından yedi çift elde edilebiliyorsa mod açabildiğini
   sınayın. Anonim, masaya oturmamış, insan hedefli, eski el ve geçersiz çift
   çağrıları reddedilmeli. Aynı masa→oyuncu kilit sırası kullanılır.
4. Endpoint kurulmamışsa istemci normal oyuna döner; botun çiftli moda geçişi
   kullanılamaz. Yeni RPC masa/ekonomi/bitiş fonksiyonlarını değiştirmez.
5. Gerçek Android/iPhone'da normal, sahte okeyli, okeyli, çiftli ve yeniden
   bağlanmalı bot maçları oynayın; native karar süresi ve kare sürelerini ölçün.

## Ölçüm ve testlerin anlamı

`dart run tool/bot_benchmark.dart 64` ilk 128 maçı;
`dart run tool/bot_benchmark.dart 32 81000` ayrı 64 maçı çalıştırır. Her destede
başlayan koltuk değiştirilir. Gizli deste yalnızca tarafsız düzeneğe aittir.
Belirsiz sahte-gösterge kuralı uydurulmadığından bu ölçümler normal gösterge
kohortudur. Çiftli mod onayı simülasyonda ideal ve anlıktır. Ağ/RLS/coin işlemleri,
animasyonlar ve kullanıcı davranışları simüle edilmez.

Bitirme fırsatı sayımı yeni motorun geniş bütçeli bitiş denetimiyle yapılır;
ayrıca grup kuralları bağımsız seri şablonlarıyla sınanır. Kazanma oranı usta insan
seviyesi veya istatistiksel olarak bütün oyunlar için garanti değildir. Karar
süreleri Windows Dart JIT çekirdek ölçümüdür; worker başlatma, yapay bekleme ve
ağ gecikmesi dahil değildir. RSS iki politika ve düzeneğin toplam süreç tepesidir;
tek botun ek bellek maliyeti veya mobil CPU profili olarak yorumlanmamalıdır.

İlk nihai 128 maçta yeni motor 80, eski motor 48 maç kazandı; yeni motorun geçersiz
hamlesi ve kaçırılmış bitişi 0, eskisinin geçersiz hamlesi 0 ve kaçırılmış bitişi
12 oldu. Yeni motor ortalama 14,27 ms, p95 43,75 ms ve en kötü 99,62 ms çekirdek
süresine sahipti. 3.038 karardan 4'ünde hesap bütçesi sınırlaması görüldü.
Diğer kümenin ve eski politikanın ham sonuçları JSON dosyasındadır.

Ayrı 64 maçlık kümede yeni motor 44, eski motor 20 maç kazandı. Birleştirilmiş
192 maçta skor 124–68; yeni motorun 4.530 kararında ortalama çekirdek süre
15,67 ms, en kötü süre 134,12 ms oldu. İki kümede toplam 4 bütçe sınırlaması,
0 geçersiz hamle ve 0 kaçırılmış bitiş görüldü. Eski politikada toplam 14
kaçırılmış bitiş sayıldı. Bitirilen maçlardaki ortalama kendi hamle sayısı yenide
ilk kümede 12,43 / ikinci kümede 12,25; eskide 12,13 / 11,65 oldu. Bu koşullu
ortalamalar yeni motorun daha hızlı bitirdiği iddiasını desteklemiyor; farklı
kazandıkları ellerin dağılımı da değişiyor.

Son ilgili test koşusunda 60 test geçti; bunlar 17 saf motor senaryosu, 3 üretilmiş
kural/maç testi, 11 gerçek taşıma adaptörü testi ve 29 mevcut oyun regresyonudur.
Üretilmiş testlerin içinde 2.000 grup ve 128 fiziksel el bulunur. Yeni dosyaların
hedefli Flutter analizi temizdir. Tüm proje analizinde hata yok, uyarı/bilgi
tanıları devam ediyor. Tüm test paketi koşusunda 430 başarılı ve 2 giriş ekranı
golden başarısızlığı vardı; bundan sonra eklenen görünür taş tükenmesi testi de
son 60 testlik koşuda başarıyla doğrulandı.

Canlı Supabase, migration yürütmesi ve gerçek iOS/Android cihaz performansı bu
ortamda test edilmedi. Android debug APK derlendi. Tüm proje testlerinde iki
önceden görülen `login_start_scene_test.dart` golden farkı mevcut; ilgili giriş
ekranı görselleri bu görevde değiştirilmedi.
