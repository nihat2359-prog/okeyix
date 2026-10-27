# Dolu slota çekilen taşın görünmemesi — teşhis

İlk teşhiste oyun kodu değiştirilmeden beş karakterizasyon testiyle aşağıdaki
hatalı davranışlar doğrulandı. Ardından aynı gün kullanıcı onayıyla istemci
düzeltmesi uygulandı; aşağıdaki teşhis bölümleri eski davranışı kaydeder.

## Doğrulanan yol

1. Ortadan ve diskarttan sürükleme `endSourceDrawDrag` içinde hedef slotu
   `_pendingPreferredDrawSlot` olarak saklıyor.
2. Sunucudan gelen eldeki yeni taş, `_syncHandIncremental` içinde bileşen
   haritasına ekleniyor. Hedef doluysa `insertIntoRow` çağrılıyor.
3. `insertIntoRow` hedefin yalnız sağında, aynı sırada boşluk arıyor. Sol tarafa
   kaydırma yalnız hedef sıranın en son slotuysa deneniyor.
4. Hedef sıranın ortasındaysa ve sağdaki bütün slotlar doluysa
   `_restoreTileToOriginalSlot` çağrılıyor. Yeni çekilen taşın ne eski ne güncel
   slotu var. Varsayılan `originalPosition` olan `(0,0)` konumuna gidiyor.
5. Taş bileşen haritasında kalıyor, fakat `occupiedSlots` içinde bulunmuyor:
   15 bileşen / 14 slot. Bir taş çıkarıldıktan sonra 14 bileşen / 13 slot oluyor.

Tam dolu sıra halinde diğer sırada boşluk olması da bu yerleştirme yolunda
değerlendirilmiyor. Solda boşluğu olan bir sırada da aynı sorun üretildi.

## Yerel kanıt

İlk karakterizasyon testleri, düzeltmeden sonra
`test/rack_draw_insertion_test.dart` dosyasında regresyon testlerine dönüştürüldü:

- 14 mevcut taş; üst sırada 1–12 dolu, 0 boş; dolu 5. slota yeni taş ekleme:
  yeni taş slotsuz, `(0,0)` konumunda, yalnız 14 slot dolu.
- 14 mevcut taş; üst sıradaki 13 slot dolu; diğer sırada boşluk mevcut:
  dolu 5. slota eklenen yeni taş yine slotsuz.
- Kontrol: hedefin sağında boşluk varsa yeni taş yerleşiyor ve 15 slot doluyor.

Ek test: sağda boşluk bulunmasına rağmen, komşu taşın animasyon/önizleme
konumu hedef slotla çakıştığında `_mountedTileAtSlot` komşuyu gerçek slot
sahibinden önce döndürüyor. `insertIntoRow` gerçek slot sahibinin harita
girdisini değiştiriyor. Yeni taş ve eski slot sahibi aynı `currentSlotIndex`
değerini taşıyor; 15 bileşen için yalnız 14 benzersiz slot sahibi kalıyor.

Ek normal sürükleme testi: mevcut bir taş dolu slota taşındığında, hedefe
görsel olarak yaklaşmış komşu taş iki ayrı harita girdisinde kalabiliyor; asıl
hedef taşı haritada bulunmuyor. Haritada aynı bileşen iki kez yer alırken oyun
dünyasında o bileşenin yalnız bir örneği olduğu doğrulandı. Ardından yapılan
başka bir hareket ve mevcut eşitleme bu örnekte 14 benzersiz slotu geri getirdi.
Bu kayıt tutarsızlığı, ekranda birebir iki taş çizildiğinin kanıtı değildir;
çift çizim görüntüsü cihazda ayrıca doğrulanmalıdır.

Beş test geçti; hata senaryoları düzeltmeyi değil, mevcut hatanın tekrar
üretilebildiğini doğrulayan karakterizasyon testleridir. Kullanılan fonksiyon,
oyunun gerçek `insertIntoRow` uygulamasıdır. Sunucuya veya bakiyeye yazılmaz.

## Sınırlar

Bu kanıt istemcideki yerleştirme hatası içindir; sunucudaki elin 13'e düştüğünü
göstermiyor. Sağında boşluk olan her dolu slota bırakmada aynı hata oluştuğu
iddia edilmiyor. Test sunucu çağrısını veya tam parmak sürüklemesini taklit
etmeden, onaylanmış yeni taşın gerçek yerleştirme fonksiyonunu çalıştırıyor.

## Sorunun neden kalıcı olabildiği

`_checkAuthoritativeHandIntegrityObservedBody` eksik slotu tespit edip elin
doğru üyeliğini tekrar okuyor. Fakat `_syncHandIncremental` içinde bileşen
kimliği zaten varsa yeni yerleştirme atlanıyor. Slotsuz bileşen veya aynı slota
sahip iki bileşen mevcut olduğunda bu yol geçerli, benzersiz slot atamıyor.
Hatalı yerleşimlerden sonra aynı 15 taşlık el tekrar eşitlendiğinde 14 slotta
kalması da testlerde doğrulandı. Bu, periyodik kontrolün çalışmasının neden
tek başına görünmeyen taşı kurtarmadığını açıklıyor.

## Bitişe etkisi

`_tryFinish` per/slot verisini `_buildSlotsJson(occupiedSlots)` üzerinden
oluşturuyor ve son taşı ayrıca gönderiyor. `_buildSlotsJson`, haritayı
`currentSlotIndex` değerlerinden yeniden kuruyor. Slotsuz taş bu veriye hiç
giremiyor; aynı slotta iki taş varsa biri diğerini örtüyor. Dolayısıyla eldeki
taş bileşenleri mevcut olsa da bitişte gönderilen düzen eksik kalabiliyor.
Bu aşamada sunucuda gerçek bir bitiş RPC'si çalıştırılmadı.

## Düzeltme için gereken koşul

Yeni taşın eski slota döndürülmesi geçerli bir kurtarma yolu değildir. Aynı
sırada iki yönde yer aranmalı; sıra doluysa diğer sıradaki boş slot kullanılmalı.
Her onaylı el taşına benzersiz geçerli bir slot ayrılması güvenceye alınmalı.
Mevcut taşın rak içinde taşınması ve sunucudan yeni çekilen taş ayrı ele alınmalı.

## Uygulanan düzeltme ve doğrulama

- Slot sahipliği animasyon konumuna göre değil, `currentSlotIndex` ile belirlenir.
  Henüz ilk karesinde eklenmemiş bileşenlerin atanmış slotları da korunur.
- Ekleme önce sağdaki, sağ taraf doluysa soldaki boşluğu kullanır. Sıra tamamen
  doluysa yeni çekilen taş başka bir boş slota yerleşir; taşın eski slota
  dönüşü yalnız mevcut taşlarda geçerli bir önceliktir.
- Slot atamasında aynı taşın eski harita girdileri temizlenir. İptal edilen
  sürükleme, eski slot artık doluysa o slotun sahibini ezmez.
- Artımlı el eşitleme slotsuz/çakışan taşları uygun boş slotlara yerleştirir.
  Sağlıklı taşların slotları ve bileşen kimlikleri korunur; el yeniden dağıtılmaz.
- Bitiş hazırlığı, sorunlu yerleşimleri onarır ve son taşı per listesinden ayrı
  tutar. Aktif sürükleme sırasında genel yerleşim onarımı çalıştırılmaz.
- Gerçek draw-response yolu MockClient ile hem `closed` hem `discard` için,
  sağ taraf dolu ve tüm sıra dolu senaryolarında test edildi. Tek `game_draw`
  çağrısıyla 15 benzersiz slot sahibi kaldığı doğrulandı; ek sunucu sorgusu yok.
- 150 ardışık rak hareketi ve mevcut çift tık, önizleme, otomatik atış,
  oyun yaşam döngüsü, bitiş yerleşimi, süre dolumu kontrolleriyle toplam 54 test geçti.
- Analizde derleme/tip hatası raporlanmadı; dosyalardaki mevcut uyarılar sürüyor.

SQL veya sunucu oyun/ödeme değişikliği yok. Gerçek telefon ve canlı sunucuda
parmak sürüklemesiyle uçtan uca doğrulama henüz yapılmadı; düzeltme Flutter
uygulama güncellemesiyle dağıtılır.
