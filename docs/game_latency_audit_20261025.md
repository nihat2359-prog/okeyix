# Oyun akıcılığı incelemesi — 25 Ekim 2026

Bu çalışma kod incelemesidir. Oyun kodu, SQL, dağıtım ve coin davranışı bu incelemede değiştirilmedi. iPhone 6 üzerinde profil kaydı veya canlı RPC süre ölçümü alınmadı. Aşağıdaki kod yolları mevcut; bunların kullanıcının gözlediği 2–3 saniyenin ne kadarını oluşturduğu henüz ölçülmedi.

## 1. Yerel sürükleme, yanlışlıkla el yenilemesi başlatabilir

Kaynak: `lib/game/rack/tile_component.dart` → `onDragStart`; `lib/game/okey_game.dart` → `_mountedRackTileCount`, `_mountedLooseRackTileCountInWorld`, `_validateCriticalInvariants`, `_hardResyncFromInvariant`.

- Normal sürükleme taşın slotunu boşaltıyor ve `currentSlotIndex=null` yapıyor. Taş dünyada kalıyor ve kilitlenmiyor.
- Slotu olmayan taş, `_mountedRackTileCount` sayımına girmiyor; dünya sayımına girmeye devam ediyor.
- 14 taşlık elde tek taş sürüklenirken bu sayılar 13 ve 14 olabilir. Tutarlılık kontrolü bunu `orphan_world_tiles` olarak ele alıyor.
- Kontrol sürükleme durumunu dışlamıyor. Bir saniyelik masa yoklaması bu kontrolü çağırıyor; hata kabul edilirse zorunlu el yenilemesi başlıyor.
- Normal sürüklemede `activeDraggedTile` atanmıyor; sürüklenen taş `_dragOverlayTiles` içinde tutuluyor. Dolayısıyla yalnızca `activeDraggedTile` kontrolü eklemek de yeterli değil. Altı saniyelik el denetiminde de bu ayrım önemli.

Bu, yerel slot hareketi sırasında ağdan bağımsız çalışması gereken görüntüye yenilemenin karışabildiği somut bir kod yolu. Gerçek cihazdaki sıklığı ölçülmedi.

## 2. Çekme tamamlanınca işlem kilidi hemen bırakılmıyor

Kaynak: `_serverDraw`, `_loadInitialState`, `canDiscardByVoice`, `_canDrawNow`.

Başarılı çekmenin sırası:

1. `game_draw` yanıtını bekle.
2. Uygun biçimdeki yanıt 15 taş içeriyorsa eli göster.
3. Yanıt sözleşmesi uymuyorsa ayrıca `table_players.hand` sorgula.
4. Her durumda `_loadInitialState(forceHandSync:true)` tamamlanmasını bekle.
5. Ancak bundan sonra `_actionInFlight=false` yap.

Tam yenileme `get_full_table_state`, bot bilgisi için `users`, diskart üstleri ve gerektiğinde sıra zamanı güncellemesini de içerebiliyor. Gerçek taş gösterildikten sonraki bu işler hâlâ hamle kilidinin içinde. Çift tıkla atış ve diğer girişler bu kilidi kontrol ediyor. Görüntünün hazır olması, girişlerin hazır olması anlamına gelmiyor.

`…` görünmesinin kaynağı `_showPendingDrawVisualTile` / `showAwaitingDrawConfirmation`. Bunun ne kadar sürdüğünü belirlemek için RPC yanıtı ile gerçek taşın ilk çizildiği kare ayrı ölçülmeli. Depodaki örnek SQL, canlı `game_draw` yanıt sözleşmesinin kanıtı değil; canlı yanıtın hızlı yolu kullanıp kullanmadığı bilinmiyor.

## 3. Atma sonrasında da ek yenileme kilidin içinde

Kaynak: `autoDiscard`, `_serverDiscard`.

- Çift tıkla atışta sunucu isteği yaklaşık 180 ms'lik animasyonun tamamlanma çağrısından başlıyor.
- Başarılı `game_discard_fast` yanıtından sonra `_loadInitialState(forceHandSync:false)` bekleniyor. `false`, tam durum RPC'sini engellemiyor; yalnızca eldeki taşların uygulanmasını etkiliyor.
- `_networkInFlight` bu yenileme bitene kadar açık. Otomatik atışın `_uiLocked` kilidi de bu zincirin sonunda bırakılıyor.

180 ms normal animasyon süresidir, tek başına 2–3 saniyenin açıklaması değildir. Fakat ağ işlemi ve ek sorguların ne zaman başladığı ve girişlerin ne zaman açıldığı ayrı ölçülmelidir.

## 4. Aynı masa birden fazla kaynaktan güncelleniyor

Kaynak: `_startDiscardPoll`, `_startLiveTablePoll`, `_subscribeTableDiscardsRealtime`, `_startHandIntegrityMonitor`; `OkeyGameScreen._startUiLoops`; `GameAvatarOverlay.initState`; `GameViewDataSource`.

- Oyun: diskart üstleri her saniye; masa durumu her saniye; el denetimi altı saniyede bir.
- Diskart Realtime bildirimi doğrudan olayın görüntüsünü uygulamak yerine diskart üstleri sorgusu çağırıyor.
- Ekran ve avatar katmanlarında iki saniyelik yenilemeler de var. Bu iki katman ortak önbellek ve devam eden istek paylaşımı kullanıyor; bunları tümüyle bağımsız sorgularmış gibi saymamak gerekir.
- Çekme/atma sonrasında ayrıca tam yenileme var.
- Diskart sorgusunun devam eden istek koruması var. Bir saniyelik masa yoklamasında eşdeğer koruma yok; yanıt bir saniyeden uzun sürerse istekler örtüşebilir. Aynı eldeki sıra bilgisi için bu yoklamada yanıt sırası koruması da görünmüyor.

Bu yapı her hareketin sunucu doğrulamasından farklı bir maliyet oluşturuyor: aynı verinin tekrar okunması, ayrıştırılması ve farklı görüntü sahiplerine uygulanması. Ağ/CPU maliyetinin boyutu ölçülmedi.

## 5. Diskartta aynı taşın kalması: normal yol anında kaldırmayı zaten deniyor

Kaynak: `_consumeDiscardTopVisualAfterDraw`, `_animateDiscardToPlayer`, `_syncDiscardTopsFromServerObservedBody`, `_fetchAndShowPreviousDiscardTop`, `_processMoveQueue`.

- Kendi diskarttan alışımız, RPC öncesinde mevcut üst görseli kaldırıp alttakini göstermeyi deniyor.
- Rakibin alma olayı işlendiğinde animasyon başlatılırken üst görsel kaldırılıyor. Kodda özellikle 2–3 saniye sonra kaldırılacak şekilde bir bekleme yok.
- Buna rağmen diskart görüntüsü üst-taş haritası, slotun `currentTile` alanı, yerel taş yığını, geçici animasyon taşı, sunucudaki üst-taş sorgusu ve önceki taşı getiren sorgu tarafından etkileniyor.
- Üst-taş senkronizasyonu sunucu sonucunda olmayan koltukları bilerek temizlemiyor. Alma olayı kaçırılırsa yalnızca eksik üst-taş satırı görmek mevcut görseli temizlemeye yetmeyebilir.
- Senkronizasyon için 900 ms; kendi atışımızda 1200 ms bekletme pencereleri var. Bunlar animasyon koruması, gerçek RPC süreleri değil. Pencere içindeki yanıt atlanıyor; sürenin dolması kendi başına yeni bir sorgu başlatmıyor. Sonraki yoklama/durum yenilemesi gerekiyor.
- Rakip hareketleri sırayla işleniyor; çekme animasyonları yaklaşık 320 ms bekletiyor. Birikmiş bildirimler sırada bekleyebilir. Kuyruk döngüsünde `try/finally` yok: işlenmeyen bir hata `_processingQueue` bayrağının açık kalmasına neden olabilir. Bunun canlı oturumda gerçekleştiğine dair kayıt yok.
- Tüketilmiş taş kimliği ve koltuk revizyonu korumaları zaten var. Dolayısıyla yeniden yalnızca “kimlikle silme ekleyelim” demek mevcut yapıyı tekrar etmek olur.

Bu belirti için hâlâ bilinmeyen: olayın geç gelmesi mi, kuyruğun geç işlemesi mi, yanlış/eski görüntünün yeniden oluşması mı? Aynı numara ve renkte iki fiziksel taş da yalnızca görüntüden ayırt edilemez; olaylar gerçek taş kimliğiyle kaydedilmeli.

## 6. Yerel çizim ve iPhone 6

- Sürüklemede her konum değişikliği `dragOverlayRevision` ile ayrı Flutter `CustomPaint` katmanını yeniden çizdiriyor; gerçek Flame taş bileşeni burada çiziliyor.
- Yerel hareketlerin kısa süreleri var: önizleme kayması 140 ms sonra başlıyor, yerleşme animasyonu 160 ms, gruplama için kaldırıp bekleme 380 ms. Bunlar tek başlarına 2–3 saniye değil; farklı algılanan gecikmelerle karıştırılmamalı.
- Sinematik taş ve ıstaka efektleri şu anda kapalı. Bunları açık kabul ederek suçlamak yanlış olur.
- Önceki performans notları çizim önbelleği ve sunum sorgularında iyileştirme yapıldığını, cihazdaki CPU/GPU ve iki cihazlı canlı oyun gecikmesinin ölçülmediğini söylüyor (`performance_stage2_network.md`, `performance_stage3_render.md`). Mevcut testlerin geçmesi gerçek cihaz akıcılığı kanıtı değil.

## Düzeltme öncesi gerekli doğrulama

Tek bir işlem kimliğiyle şu anları ilişkilendirmek gerekir:

- Parmak başlangıcı/bırakılması, hedef slot, yerel hareketin son karesi.
- RPC başlangıcı/bitişi, yanıtın hızlı el yoluna uygunluğu; gizli taş içeriği kaydedilmeden.
- Gerçek taşın bileşene uygulanması ve ilk çizimi.
- Tam yenileme başlangıcı/bitişi ve hangi nedenle başlatıldığı.
- Hamle kilitlerinin açıldığı an.
- Diskart olayının alınması, kuyruğa girmesi/işlenmesi, fiziksel taş kimliğiyle görselin kaldırılması/yeniden eklenmesi ve güncelleme kaynağı.
- Sürükleme sırasında tutarlılık kontrolünün sayıları ve yenileme nedeni.
- Aynı zaman çizgisindeki UI/raster kare süreleri; eski/yeni ağ yanıt sırası.

Öncelik: (1) yerel sürüklemeyi yanlış toparlanma kontrollerinden ayırmak; (2) başarılı hamleden sonraki ek okumaların giriş kilidini tutmasını kaldırmak; (3) diskartın bütün görsel sahiplerini tek zaman çizgisinde doğrulamak; (4) iki fiziksel cihazda profile/release derlemesiyle gecikmeli ağ ve uzun oturum ölçmek.

İlk incelemede değişiklik uygulanmadı. Sonraki uygulamanın kapsamı aşağıdadır. Canlı sunucu gecikmesi, RPC kilit beklemeleri ve iPhone 6 kare süreleri için sayı veremiyoruz. Bunlar alınmadan “genel yavaşlık giderildi” sonucuna varılamaz.

## Uygulanan dar kapsamlı değişiklikler

- Normal ve grup sürükleme katmanı artık el denetimlerinde tanınıyor; geçici slotsuzluk toparlanma başlatmıyor. Devam eden hamleler de tutarlılık denetiminin dışında. Aynı elin sıradan yenilemesi aktif sürüklemeyi yeniden yerleştirmiyor; yeni elin zorunlu kurulumu korunuyor.
- Geçerli, onaylanmış 15 taşlık çekme yanıtı doğrudan uygulanıyor ve başarılı yol ek tam masa yenilemesi beklemiyor. Eski yanıt sözleşmesi ve hata toparlanması korunuyor.
- Başarılı atıştan sonra tam masa/kullanıcı/diskart zinciri yerine yalnızca güncel masa sırası okunuyor. Bu tek okuma hâlâ bekleniyor; sunucunun bildirmediği sonraki sırayı tahmin etmiyoruz.
- Periyodik masa okumaları devam eden isteği paylaşıyor. Atış sonrası okuma eski bir isteği paylaşmak yerine onun bitiminden sonra yeni okuma yapıyor. Önceki elden dönen sonuç uygulanmıyor.
- Başarılı diskart üstü sorgusunda artık bulunmayan taş görseli temizleniyor. Koltuk revizyonu, animasyon/bekletme ve sürükleme korumaları korunuyor; önceki elden gelen sonuç reddediliyor. Tüketilen taş kimliği slot yedeğinden de alınabiliyor.
- Bir görsel hamle işlenirken hata olması sonraki hamlelerin kuyruğunu kalıcı olarak kilitlemiyor.

`test/game_latency_regression_test.dart`, gerçek Supabase HTTP istemcisini sahte ağ yanıtlarıyla kullanıyor. Gecikmiş çekme, sorgu sayıları, sürüklemede yanlış toparlanma, korunmuş slotlar, boş diskart ve eski yanıt/yeni hareket çakışmaları kontrol ediliyor. Fiziksel cihaz ve canlı sunucu performans ölçümü yerine geçmez.

### Yeni el dağıtımında tekrar dizilme incelemesi

Dağıtım bileşenleri `world.add` ile kuyruğa girerken slotları hemen ayrılıyor. Flame ilk bağlama geçişini yapmadan çalışan tutarlılık kontrolü, slot sayısını yalnızca ekrana bağlanmış taş sayısıyla karşılaştırabiliyordu. Bu geçici durumda toparlanma istemek gereksizdi. Eklenmesi beklenen taşlar artık hata sayılmıyor ve slot haritası yeniden kurulurken yerlerini koruyor. El temizlenirken henüz `world.children` içine girmemiş kayıtlı taşların eklemeleri de iptal ediliyor. Önceki el numarasına ait Realtime durum bildirimi yeni ele uygulanmıyor.

İki ek test, ilk kareden önce ve dağıtım animasyonu devam ederken gelen ikinci aynı el yanıtının aynı taş bileşenlerini koruduğunu kontrol ediyor. İlgili gecikme ve taş görüntüsü testlerinde 26 test geçti. Bu sonuç, fiziksel iki cihazdaki bildirilen olayın bütünüyle giderildiğini kanıtlamaz.
