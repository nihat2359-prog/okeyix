# Gerçek maçta yerden taş alma incelemesi ve düzeltmesi

Güncel Chrome takip bulguları ve `strategic-live-3` düzeltmesi:
[bot_chrome_followup.md](bot_chrome_followup.md). Aşağıdaki 192 maçlık ölçüm
önceki sürüme aittir; güncel web bütçesi takip raporunda belirtilmiştir.

## Bulgular: doğrulananlar ve doğrulanamayanlar

Kullanıcının iki gerçek maçının el/karar kaydı bulunmadığından bu maçlarda neden
hiç yerden alınmadığını kesin olarak belirlemek mümkün değil. İki mağlubiyet de
tek başına zayıflık veya entegrasyon hatası kanıtı değil. Buna rağmen aşağıdaki
somut sorunlar kodda bulundu ve testlerle düzeltildi:

1. **Puan ölçeği hatası:** normal kalan el yaklaşık 0–1400 puanken, bir kapalı
   çekişin bitiş getirmesi 100.000 puanla beklentiye giriyordu. Az olasılıklı bir
   bitiş bile kapalı beklentiyi binlerce puan yükselterek yararlı atığı reddettirebilirdi.
2. **Eksik ve yanlı beklenti:** sadece bağlantılı sekiz tür ayrıntılı inceleniyor,
   diğerleri mevcut elle temsil ediliyordu. Çift potansiyeli ve atış savunma
   maliyeti de başlangıç puanıyla tam aynı şekilde ele alınmıyordu.
3. **Açık bilginin kaybı:** `withHand` varsayılan olarak üst atığı düşürüyordu.
   Özellikle geçmiş eksikse kapalı çekiş karşılaştırması açık atığı bilinmeyen
   havuzda yeniden sayabiliyordu. Üst atık artık fiziksel kimliğiyle korunuyor.
4. **Gerçek yürütme bütçesi farkı:** browser'ın önceki tek parça 12 ms bütçesi ve
   native toplam 180 ms bütçesi çekiş karşılaştırmasını yarıda bırakabiliyordu.
   Testlerde ve ara benchmark'ta bu durum doğrudan yeniden üretildi.
5. **Sessiz bilgi eksikliği:** `table_discard_tops` okumasındaki her hata boş atık
   gibi ele alınıyordu. Bu görünümün canlıda hatalı olduğu kanıtlanmadı. Bot için
   görünüm bağımlılığı kaldırıldı; gerçek `table_discards` tablosunda doğru koltuk,
   `drawn_at IS NULL`, azalan `created_at/id`, `LIMIT 1` kullanılıyor. Hata ve boş
   sonuç güvenli debug tanılamasında ayrı gösteriliyor; bot kimlik/sıra tahmini yapmıyor.

Normal durumda yerden alma kararı zaten doğru `game_draw` RPC'sine `p_source=
'discard'` ve önceki koltuğun `p_from_seat` değeriyle gidiyordu. Burada ters kaynak
veya yanlış parametre hatası bulunmadı. RPC hatasında kapalıya dönüş vardı; artık
bu dönüş gözlenebilir. Önce el tekrar okunuyor: çekiş tamamlanmışsa ikinci çekiş
yok, el hâlâ 14 ve sıra aynıysa kapalı çekiş deneniyor. `ok:false` ve exception
sonuçları ile yedek RPC sonucu da tanılamada ayrılıyor.

## Yeni karşılaştırmanın matematiksel anlamı

Çakışmayan per/seri motoru yeniden yazılmadı. Aynı el değerlendirme ve bitiş
kuralları korunarak çekiş karşılaştırması düzeltildi:

- Normal kalan el faydası en çok 1400; yasal normal bitiş 1600, okeyli/çiftli
  bitiş 1640 kullanır. Bunlar ekonomik tutar veya kalibre kazanma olasılığı değil,
  ortak sınırlı stratejik fayda ölçeğidir.
- Kapalı beklenti: `sum(kalan_kopya[tür] * en_iyi_yasal_sonuç[tür]) /
  sum(kalan_kopya[tür])`. Gerçek kapalı deste sırası veya rakip eli okunmaz.
- Sadece sekiz tür seçmek yerine bütün bilinmeyen türler kapsanır. Aynı
  `handValue` normal/çiftli potansiyelini değerlendirir; yasal atıştan sonraki risk
  ve okey atış maliyeti hem açık hem kapalı sonuçlara aynı şekilde uygulanır.
- Her yasal atış sonucu en az -102,5; bütün sonuçlar bitiş dahil en çok 1640'tır.
  Henüz incelenmeyen olasılık kütlesi için güvenli alt/üst sınır hesaplanır. Açık
  taşın puanı kapalı beklentinin üst sınırını geçiyorsa almak kesinleşir; alt
  sınırın altında kalıyorsa kapalı çekiş kesinleşir. Bu durumda kalan aramaya
  gerek yoktur. Aksi halde türlerin tamamı hesaplanır.
- Loglarda tam beklenti ile sınır aralığı ayrılır: `closed_exact`,
  `closed_expected`, `closed_lower`, `closed_upper`. Eksik toplam tam beklenti
  diye sunulmaz. Yüzdelik alım hedefi veya yapay rastgelelik eklenmedi.

Bu matematik, mevcut el faydası ve bilinmeyen havuz modeli için tutarlıdır;
kusursuz Okey stratejisi veya gerçek kazanma olasılığı hesabı olduğu iddia edilmez.

## Yürütme ve bütçe

Native `compute` ve web artık aynı parçalı çekiş algoritmasını kullanır. Her taş
türünden sonra olay döngüsüne dönülür. Native hesap hâlâ worker isolate içindedir;
web tek ana iş parçacığında uzun bir toplam aramaya zorlanmaz. Native parça başına
180 ms/300.000 düğüm kullanılır. Chrome'daki gerçek maç geri bildiriminin ardından
web'in 12 ms/12.000 düğüm sınırı kaldırıldı; web de aynı stratejik düğüm bütçesini
kullanır. Çekişte her taş türü arasında event loop'a dönülür; bir türün hesabı
12 ms sürdü diye bütün çekiş kapalıya zorlanmaz.
Çekiş toplam bütçesi 650 ms; runner dış deadline'ı 750 ms'dir. Kontroller aralıklı
olduğu için gerçek zamanlı süre garantisi değildir. Atış araması da sınırlandırılır.

Eksik beklenti veya deadline durumunda hamle yasal yedeğe döner; tam beklenti
hesaplanmış gibi yararlı taş kabul edilmez. `limited` ve tamamlanan tür sayısı
loglanır. Benchmark aynı parçalı çekiş yoluna geçirildi; sadece saf senkron motoru
ölçüp gerçek runtime bütçe farkını saklamıyor. Worker başlatma ve ağ gecikmesi
benchmark çekirdek sürelerine dahil değildir.

## Güvenli geliştirme tanılaması

Varsayılan kapalıdır. Aşağıdaki şartların **hepsi** gerekir:

- Debug build; profile/release build'de açılmaz.
- `OKEYIX_BOT_TRACE=true`.
- `OKEYIX_BOT_TRACE_ENV=local` veya `staging`.
- Açıkça tanımlanmış `SUPABASE_URL`; boş değerle seçilen üretim varsayılanı ve
  uygulamanın mevcut üretim proje host'u engellenir.

Örnek, gerçek staging URL/anon yapılandırmasını içeren yerel dosyayla:

```text
flutter run --debug --dart-define-from-file=<yerel-staging-config.json> --dart-define=OKEYIX_BOT_TRACE=true --dart-define=OKEYIX_BOT_TRACE_ENV=staging
```

`[BOT_TRACE]` kayıtları kendi bot eli, açık üst atık, puan/beklenti veya sınırlar,
seçim ve gerekçe, hesap süresi, yedek durum, tür sayısı ve RPC sonucu içerir.
Kapalı destenin kimlikleri/sırası veya rakibin gizli eli loglanmaz. Ham RPC yanıtı
ve hata metni yazılmaz; yalnızca izinli sonuç alanları/hata tipi/kodu kullanılır.
Tanılama dış servise gönderilmez. Üretim ortamını staging diye etiketleyerek test
etmeyin; gerçek staging bağlantısı kullanın. Üretim host'u değişirse denylist de
ana uygulama yapılandırmasıyla birlikte güncellenmelidir.

## 192 maçlık yeniden ölçüm

Eski tohumlar aynen kullanıldı: 74219–74282 ve 81000–81031; her destede başlangıç
koltuğu değiştirildi. Eski politika değiştirilmedi. Deste yalnızca tarafsız test
düzeneğine aittir. Normal gösterge kohortu, ideal çiftli onayı ve çevrimdışı yerel
kural sınırlamaları önceki rapordaki gibi devam eder.

| Ölçüt | Yeni | Eski |
|---|---:|---:|
| Galibiyet | 126 | 65 |
| Deste bitmesiyle sonuçsuz maç | 1 ortak | 1 ortak |
| Üst atık fırsatı | 2130 | 2100 |
| Yerden alınan | 452 (%21,22) | 650 (%30,95) |
| Anlık el puanını artıran üst atık | 682 | 949 |
| Bunlardan alınan | 452 (%66,28) | 487 (%51,32) |
| Bunlardan reddedilen | 230 (%33,72) | 462 (%48,68) |
| Anlık el puanını artırmayan alım | 0 | 163 |
| Geniş bütçeli aynı-EV denetimine göre üstünken reddedilen | 0 | 175 |
| Kaçırılmış doğrudan bitiş | 0 | 7 |
| Geçersiz hamle | 0 | 0 |
| Yarım kalan çekiş hesabı / çekiş deadline | 0 | 0 |
| Kazandığı maçlarda ortalama kendi hamle sayısı | 11,63 | 11,60 |
| Karar ortalama / en kötü | 30,01 / 404,98 ms | 1,24 / 28,01 ms |

Yeni motor daha sık yerden almıyor; **daha seçici**. Reddedilen 230 taş mevcut el
puanını artırıyordu, ancak aynı fayda modelinde kapalı çekiş daha avantajlıydı.
Bunları yok sayıp "hiç yararlı taş reddetmedi" demek yanlış olur. Üstünken
reddedilen 0 sayısı geniş bütçeli **aynı modelin** denetimine göredir; bağımsız
usta oyuncu doğrusu değildir. "Anlık puanı artırmayan" da bütün uzun vadeli
savunma hamlelerinin gereksiz olduğuna dair bir ispat değildir.

Galibiyet oranı tüm maçlarda %65,625 oldu. Bir önceki 124–68 sonucu farklı motor
sürümüne aittir; doğrudan insan seviyesine ilişkin istatistiksel garanti vermez.
Yeni motorun CPU maliyeti eskisinden yüksektir. Windows Dart ölçümüdür; gerçek
iPhone/Android CPU, FPS, ağ ve isolate başlatma maliyetleri ayrıca ölçülmelidir.
Ham ölçümler `bot_draw_benchmark_results.json` dosyasında bulunur.

## Doğrulama ve kalan saha işi

Gerçek `OkeyGame → BotObservation → BotRunner → RPC` testleri normal seri/per
tamamlama, yararlı gerçek/sahte okey, doğrudan bitiş, işe yaramayan atığı reddetme,
yasal RPC parametreleri, yerden çekiş hatası, tamamlanmış çekişte yanıt kaybı,
runner timeout, üst atık okuma izni hatası ve tam el aktarımını kapsar. Ayrı bir
senaryo enjekte edilmiş karar işçisi kullanmadan gerçek compute runner'ını sınar.
Sahte HTTP taşıması kullanılır; canlı Supabase'e bağlanılmaz.

Puan ölçeği regresyonu, senkron/parçalı beklenti eşitliği, log güvenlik kapıları,
gizli bilgi sınırı, eski el/sıra, kural ve Flame yaşam döngüsü testleri de çalışır.
Son ilgili koşuda 61 test geçti. Yeni dosyaların analizi ve Android APK derlemesi
kontrol edildi. Chrome test başlatıcısı bu Windows ortamında yükleme aşamasını
tamamlamadı; gerçek browser uçtan uca testi başarılı diye sunulmuyor. Parçalı
algoritma ve native compute yolu yerel otomatik testlerden geçti.

Canlı masanın `table_discards` okuma yetkisi, gerçek cihazdaki mevcut build,
eşzamanlı RPC'ler, FPS ve düşük cihazda deadline oranı hâlâ saha doğrulaması ister.
İki gözlemlenen maçın kesin teşhisi için staging'de `[BOT_TRACE]` örnekleri gerekir.
Hiçbir Supabase migration uygulanmadı; ekonomi, dağıtım ve oyun kuralları
değiştirilmedi. İnsan istemcisine bot eli/deste verisi teslim edilmesiyle ilgili
önceki sunucu mimarisi riski bu görevde kapanmış sayılmaz.

## Bu görevde değişen dosyalar

- `lib/game/okey_game.dart`
- `lib/game/bot/bot_engine.dart`
- `lib/game/bot/bot_observation.dart`
- `lib/game/bot/bot_runner.dart`
- `lib/game/bot/okey_bot_turn.dart`
- `lib/game/bot/bot_diagnostics.dart` (yeni)
- `test/bot_engine_test.dart`
- `test/bot_turn_integration_test.dart`
- `test/bot_generated_test.dart`
- `test/bot_draw_live_path_test.dart` (yeni)
- `tool/bot_benchmark.dart`
- Bu rapor, `bot_draw_benchmark_results.json` ve önceki rapordaki sürüm notu.
