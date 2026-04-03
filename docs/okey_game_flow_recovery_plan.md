# Okey Oyun Akisi Onarim Plani

Bu plan, oyun alanindaki state cakismalarini kaldirip tek dogruluk kaynagina gecmek icin hazirlandi.

## 1) Problemin Koku

Su anda ayni anda birden fazla state kaynagi var:
- Lokal Flame state (`occupiedSlots`, `closedPile`, `currentTurn`)
- `tables` satiri (`deck`, `current_turn`, `status`)
- `table_players.hand`
- `table_discards`

Bu kaynaklar farkli anlarda update edildigi icin su buglar olusuyor:
- Oyuncu atmadigi tasi atmis gibi gorunme
- Tas cekince deste sayisinin geri ziplamasi
- Sira baska oyuncuya gecse de timer eski oyuncuda akmasi
- Rakibin attigi tasi gorup alamama

## 2) Net Mimari Karari (Kilitle)

Tek dogruluk kaynagi:
- `tables`: `status`, `current_turn`, `deck`, `turn_started_at`, `turn_seconds`
- `table_players`: her oyuncunun `hand`
- `table_discards`: her koltugun discard gecmisi

Client rolu:
- Sadece UI + input
- Mutasyonlari server'a yazar
- Realtime/poll ile state ceker

Kural:
- Lokal state kalici kaynak degil, yalnizca render cache.

## 3) Turn State Makinesi

Tek tur akisi:
1. `start_turn`: server `current_turn`, `turn_started_at`
2. Oyuncu `draw` (closed veya discard)
3. Oyuncu `discard`
4. Server `current_turn = next`, `turn_started_at = now`

Zorunlu kosullar:
- Draw olmadan discard yasak
- Sira kendinde degilse draw/discard yasak
- Timeout olursa server otomatik draw+discard uygular

## 4) Uygulama Sirasiyla Onarim

### Faz A - Stabilizasyon (ilk hedef)
1. Oyun baslayinca `table_players` realtime "tum eli tekrar render" kapali kalacak.
2. Elde sadece kendi local aksiyonlarin gorunmesi saglanacak.
3. `tables.current_turn` degisince timer reset kesin olacak.
4. Timer sadece aktif oyuncuda akacak, digerlerinde full bar.

Kabul kriteri:
- A atinca kendi timer durur, B timer baslar.

### Faz B - Draw/Discard atomiklestirme
1. Draw sonrasi aninda server write:
   - `table_players.hand`
   - gerekiyorsa `tables.deck`
2. Discard sonrasi server write:
   - `table_discards` insert
   - `table_players.hand` update
   - `tables.current_turn + turn_started_at` update
3. Bu 3 adim tek helper zinciri ile (sira garantili) yapilacak.

Kabul kriteri:
- B ortadan cekince deste geri ziplamaz.
- B discard yapinca A ayni tasi gorur.

### Faz C - Discard yigini
1. `table_discard_tops` realtime + poll ile tum istemcilerde senkron.
2. Discardtan cekiste ilgili top kayit `drawn_at` isaretlenir.
3. Alttaki tas otomatik top olur.

Kabul kriteri:
- Ust tas alininca alttaki tas gorunur.

### Faz D - Timeout kurali
1. Timeout hesaplamasi:
   - `now - turn_started_at >= turn_seconds`
2. Timeout aksiyonu:
   - Elde 15 ise uygun tas discard
   - Elde 14 ise draw + discard
3. Timeout yalniz aktif oyuncuda tetiklenir.

Kabul kriteri:
- Sure bitince tur kesin kapanir, rakibe gecer.

## 5) RPC/Edge Tasima (zorunlu)

Mevcut duzende client bircok mutasyonu kendisi yapiyor.
Kalici cozum icin 3 RPC gerekli:
- `game_draw(p_table_id, p_user_id, p_source)`
- `game_discard(p_table_id, p_user_id, p_tile)`
- `game_timeout_move(p_table_id, p_user_id)`

Hepsi server-side validation yapacak:
- turn kontrolu
- hand/deck/discard tutarliligi
- transaction atomik update

## 6) Gozlemleme ve Hata Ayiklama

Gecici debug overlay (yalniz test build):
- `mySeat`
- `currentTurn`
- `hasDrawnThisTurn`
- `handCount`
- `deckCount`
- `turnRemaining`

Hedef:
- "neden atamadi/cekemedi" sorusunu aninda gor.

## 7) Test Senaryolari (zorunlu)

1. A draw + discard -> B draw + discard
2. A discard, B discardtan alma
3. Timeout (A hic oynama)
4. Hiz modlari:
   - Hizli 10 sn
   - Normal 15 sn
   - Yavas 20 sn

Hepsi 2 istemci ile test edilir.

## 8) Uygulama Kurali

Bu plandan sapma yok:
- Once Faz A bitmeden Faz B'ye gecme
- Her faz sonunda kabul kriterini gormeden sonraki faza gecme
- Bug gorulurse once state kaynagi tespiti, sonra patch

## 9) Kullanici Tarafindan Kilitlenen Oyun Kurallari

Bu maddeler birebir uygulanacak; yorum yok.

1. Baslangic tasi (15 tas):
- Oyun ilk basladiginda masayi acan oyuncu 15 tas alir ve ilk sirasi ondadir.
- Sonraki elde 15 tas diger oyuncuya gecer.
- Ayni masada her yeni elde 15 tas hakki sirali degisir.

2. Tur davranisi:
- Sirasi gelen oyuncu suresi icinde bir tas atmak zorundadir.
- Atis yaparsa sira rakibe gecer, rakibin suresi baslar.
- Rakip atilan tasi alabilir veya kapali desteden cekebilir; sonra bir tas atar.
- Bu dongu ayni sekilde devam eder.

3. Timeout davranisi:
- Oyuncu suresi biterse:
  - Eger 15 tasi varsa, sistem otomatik uygun bir tasi atar.
  - Atilacak otomatik tas kesinlikle gercek okey tasi olamaz.
- Eger oyuncu henuz tas cekmediyse (discard almadi / ortadan cekmedi):
  - Sistem ortadan bir tas ceker ve onu discard eder.
- Timeout sonrasi sira rakibe gecer.

4. Ust uste timeout cezasi:
- Ayni oyuncu ust uste 3 kez sistemi otomatik oynatirsa oyuncu masadan atilir.
- O eldeki dagitim iptal edilir (rollback/temizleme).
- Masada kalan oyuncularin ellleri de temizlenir.
- Masa yeniden bekleme durumuna doner ve yeni oyuncu beklenir.

5. Rack butonlari:
- `Seri Diz`: Istakadaki taslari mantikli seri/per yapisina gore dizer; perler arasi bosluk birakir.
- `Cifte Diz`: Cift olanlari grup halinde bir siraya, cift olmayanlari diger siraya dizer.
- `Cifte Git`:
  - Basmadan once onay popup'i cikar.
  - Onay verirse oyuncu bu karari geri alamaz.
  - Oyuncu artik yalnizca ciftten bitmek zorundadir.
  - Bu durum hem kendi avatarinda hem rakipte gorunen bir isaret ile belli olur.

6. Bitis bildirimi:
- Oyuncu eli bittiginde, bitis icin atilacak tasi kapali deste ustune birakir.
- Bu hareket "eli bitiriyorum" anlamina gelir.
- Sistem eli server tarafinda kontrol eder:
  - Gecersizse: "Elin bitmiyor" uyarisi verilir.
  - Gecerliyse: el biter ve yeni oyun geri sayimla baslar.

7. Discard gecmisi:
- Sadece son tas degil, oyuncu bazli tum discard gecmisi tutulur.
- Ust tas alindiginda alttaki tas gorunur kalir.
- Cifte/analiz gibi durumlarda atilan tum taslar gorulebilir olmalidir.

## 10) Güncel Uygulananlar (2026-03-06)

Bu dosya son geliştirmelerle güncellendi.

1. Lobby - Masa Aç ekranı:
- Diyalog ekranı kısa yüksekliklerde taşmayacak şekilde kompakt hale getirildi.
- Scroll gerektirmeden hızlı seçim ve masa açma akışı korundu.
- Varsayılan masa tipi 2 oyunculu (düello) olacak şekilde bırakıldı.

2. Lobby - Sağ panel / Mesajlaşma:
- Sağdan açılan panel genişliği ekranın yaklaşık %80’i olacak şekilde artırıldı.
- Mesajlaşma alanındaki kişi listesi genişletildi.
- Mesaj giriş alanı okunur hale getirildi:
  - Yazı rengi açık tona alındı.
  - İmleç ve placeholder renkleri güncellendi.
  - Koyu arka plan + border + focus stili eklendi.

3. Premium yükleme göstergeleri:
- Lig ve masa yüklenirken kullanılan spinner premium stile çekildi.
- Mesaj paneli loading görünümü de aynı premium loader ile güncellendi.
- Login/Register ekranı buton loading indicator renkleri genel tasarıma uyumlu hale getirildi.

4. Arkadaşlık isteği bilgilendirmesi:
- Kullanıcıya yeni arkadaşlık isteği geldiğinde anlık bilgilendirme diyaloğu eklendi.
- Diyalog içinden doğrudan `Kabul Et`, `Reddet`, `Engelle` aksiyonları çalışır hale getirildi.
- Aynı istek için tekrar tekrar popup çıkmasını önleyen koruma eklendi.

5. Türkçe karakter standardı:
- `lobby_screen.dart` içindeki bozulmuş tüm Türkçe metinler düzeltildi.
- `tile_component.dart` içindeki bozuk Türkçe yorumlar düzeltildi.
- Proje içinde Türkçe karakter bozulması tarandı; bozuk karakter izi bırakılmadı.

6. Lig listesi düzeltmeleri:
- Lig kartı başlık/metinlerinde Türkçe karakter normalizasyonu eklendi.
- Ligdeki oyuncu sayısı hesaplaması düzeltildi:
  - Artık masaların toplamı değil,
  - O ligde `waiting/playing` masalarda bulunan **benzersiz aktif kullanıcı** sayısı gösteriliyor.

7. Yayın hazırlığı:
- Uygulama ikonu eklendi ve Android/iOS icon setleri üretildi.
- Ikon kaynağı: `assets/images/app_icon.png`
- Store ekran görüntüleri için otomasyon scripti eklendi:
  - `tool/capture_store_screenshots.ps1`
- Yayın varlıkları dokümantasyonu eklendi:
  - `docs/store_release_assets.md`
