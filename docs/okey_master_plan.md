# Okeyix Master Plan

Bu dosya proje icin tek dogruluk kaynagidir.
Her teknik karar, kural netlestirme ve gelistirme adimi burada takip edilir.

## 1) Proje Ozeti (Mevcut Durum)

### Uygulama Akisi
- `Login/Register` Supabase Auth uzerinden calisiyor.
- `Lobby` ligleri ve bekleyen masalari Supabase'den cekiyor.
- `Masa Ac / Masaya Katil` akislari `tables` + `table_players` uzerinden calisiyor.
- Oyun ekrani Flame tabanli (`OkeyGame`) ve Flutter overlay (`GameAvatarOverlay`) ile kullaniliyor.

### Oyun Cekirdegi (su an)
- Tahta, rack slotlari, closed pile sayaci, discard alanlari var.
- Tas drag/drop, rack icinde kaydirma, preview ve discard kurallari var.
- Realtime:
  - `tables` update dinleniyor.
  - `table_players` update dinleniyor.
- Avatar overlay:
  - 2 ve 4 kisilik masa yerlesimi var.
  - Bos koltuklarda `DAVET` butonu var.
  - Davet popup acilip uygun oyuncu listeleniyor ve `table_invites` insert ediliyor.

### Bilinen Kritik Bosluklar
- Oyun kurallari server tarafinda tam authoritative degil (istemci agirlikli).
- `users.username` okuma tarafinda veri kaynagi / RLS netlestirme gerekiyor.
- Solver kodu mevcut ama ana tur akisina bagli degil.

## 2) Oyun Kurallari (Hedef Davranis)

Bu bolumde yazanlar hedef kural setidir. Kod bu kurallara gore evrilecektir.

### Masa ve Oyuncu
- Masa tipi: `2` veya `4` kisilik.
- Her oyuncunun bir `seat_index` degeri vardir.
- Oyuncu kendi ekraninda kendini her zaman alt pozisyonda gorur (relative seat).

### Destek ve Dagitim
- Toplam tas: klasik okey destesi.
- Gosterge tasi belirlenir.
- Okey (gercek joker) gostergeye gore hesaplanir.
- Baslayan oyuncu 15, digerleri 14 tas alir.

### Tur Kurali
- Siradaki oyuncu:
  1. Kapali desteden bir tas ceker veya acik tas alir.
  2. Elindeki bir tasi acik alana atar.
- Cekmeden atma yapilamaz.
- Tur bitiminde sira bir sonraki oyuncuya gecer.

### Oyun Sonu
- Gecerli bitis kosulu:
  - Kurala uygun per/seri yapisi + elde kalan son tas atimi.
- Bitis dogrulamasi server tarafinda authoritative olmalidir.

## 3) Veri Modeli (Su anki varsayim)

### Kullanilan tablolar
- `tables`
- `table_players`
- `leagues`
- `table_invites`
- `profiles`
- `users`

### Kural
- Ekranda oyuncu adi icin esas kaynak: `users.username`
- Coin: once `users.coins`, yoksa `profiles.coins`

## 4) Hedef Mimarisi

### Istemci (Flutter/Flame)
- UI ve input handling
- Lokal optimistic state (minimum)
- Realtime eventleri isleme

### Server (Supabase/Functions)
- Oyun kurali dogrulamasi
- Tur gecerliligi kontrolu
- Cekme/atma islemlerini transaction/RPC ile kilitleme
- Kazanma kontrolu

## 5) Gelistirme Fazlari

## Faz 0 - Stabilizasyon
- [x] Oyun ekrani init crash fix
- [x] Test ama cli dagitim enjeksiyonu temizligi
- [x] Realtime channel cleanup
- [x] Avatar + davet temel akisi
- [ ] `users.username` tutarliligi (RLS/schema teyidi)

## Faz 1 - Kural Motoru
- [ ] Tur state machine'i netlestir (`draw -> discard -> next`)
- [ ] Client aksiyonlarini RPC uzerine tasima
- [ ] Server dogrulamasi olmadan state mutasyonu yapmama

## Faz 2 - Oyun Sonu ve Skor
- [ ] Kazanma dogrulamasi
- [ ] El/round sonu skor hesaplama
- [ ] Coin/rating etkisi

## Faz 3 - Sosyal ve Lobby
- [ ] Davet kabul/red akisi
- [ ] Arkadas/mesaj sistemini gerçek veri ile tamamlama
- [ ] Masa doluluk, lock, timeout davranislari

## 6) Teknik Is Kurali (Calisma Sekli)

Bu dosya uzerinden ilerleme kurali:
1. Yeni bir is baslamadan once ilgili madde secilir.
2. Kod degisikligi yapilir.
3. Bu dosyada ilgili checkbox ve not guncellenir.
4. Sonraki adim bir oncekiye bagimli ise burada baglantisi yazilir.

Encoding kurali (kritik):
- Flutter/Dart dosyalari UTF-8 formatinda tutulur.
- UI metinlerinde Turkce karakterler (s, i, g, u, o, c ve buyuk harfleri) bozulursa dosya UTF-8 olarak yeniden kaydedilir.
- Metin guncellemelerinde encoding bozabilecek edit yontemleri kullanilmaz; degisiklikten sonra ekran metinleri kontrol edilir.

## 7) Simdiki Oncelik (Aktif)

1. `users.username` neden `Oyuncu 1` fallback'ine dusuyor problemini kesin coz.
2. Tur kurali akisini server authoritative modele tasima tasarimini netlestir.
3. `draw/discard` aksiyonlarini RPC tabanli hale getirme planini cikart.

## 8) Urun Kurallari (Kullanici Tarafindan Verilen Net Kurallar)

Bu bolum kullanicinin adim adim verdigi urun kurallaridir. Kod ve DB bu bolume gore hizalanacaktir.

### Kimlik ve onboarding
- Oyun turu: Okey.
- Teknoloji: Flutter + Supabase.
- Kayit:
  - Kullanici mail + sifre ile hesap olusturur.
  - Mail onay linki gider.
  - Mail onayi tamamlaninca lobby'e girebilir.
- Ilk giris onboarding:
  - Kullaniciya `username` ve `avatar` zorunlu olarak sorulur.
  - Profil tamamlanmadan lobby tam kullanima acilmaz.

### Lobby yapisi
- Ust bolum:
  - Kullanici bilgileri
  - Hizli erisim kisayollari
- Orta bolum:
  - Lig listesi
- Alt bolum:
  - Secili lige ait acik masalar
- Sosyal:
  - Mesaj alani bulunur
  - Sadece arkadas olunan kisilerle mesajlasma aktif olur

### Coin satisi / odeme
- Uygulama icinde coin satis alani olacak.
- Odeme saglayicisi: Lemon.
- Coin paketleri ve fiyatlandirma daha sonra netlestirilecek.
- Lig entry ekonomisi, coin paket/fiyat netlesince kilitlenecek.

### Lig kurallari
- Lig bazli:
  - Entry coin sabittir.
  - Min rating siniri vardir.
  - Lig minimum el (blok) belirler.
- Lig yukselince:
  - Minimum el artar
  - Turn suresi azalir (tempo artar)
  - Entry artar
  - Disiplin artar

### Blok / minimum el ekonomisi
- Her elde coin dagitimi yok.
- Coin transferi sistem havuzu uzerinden.
- Min blok tamamlanmadan cikis:
  - Entry iade edilmez
  - Sabit rating cezasi (ornek: -30)
  - 10 dakika Ranked kilidi
  - Ekstra coin yakimi yok
- Min blok tamamlandiginda:
  - Oyuncuya `Devam etmek ister misiniz?` sorusu cikar.
  - Devam secilirse ayni masa devam eder.
  - Toplam el sayaci artmaya devam eder.
  - Min tamamlandigi icin cikis serbest olur.

### Rating modeli
- Rating her el sonunda degil, minimum blok sonunda hesaplanir.
- Hesaplama toplam skor bazlidir.
- ELO formulu uygulanir.

### Masa akis modeli
1. Oyuncu lig secer (veya sistem oyuncu ligine gore acar).
2. Masa olusturulur.
3. Minimum el sayisi sabitlenir.
4. Oyun baslar.
5. Her elde coin dagitimi yapilmaz.
6. Minimum tamamlaninca devam/cikis karari sorulur.
7. Devam edilirse ayni masada oynanir.
8. Cikis:
   - Minimum tamamlandiysa serbest
   - Minimum tamamlanmadiysa ceza uygulanir

## 9) Karar Bekleyen / Celisen Noktalar

Asagidaki maddeler kodlamaya gecmeden once tek deger olarak kesinlestirilmeli:

1. Lig entry degerleri iki farkli sekilde verildi:
   - Set A:
     - Standart 100
     - Bronz 500
     - Gumus 1000
     - Altin 5000
     - Elit 10000
   - Set B:
     - Standart 100
     - Bronz 250
     - Gumus 500
     - Altin 1000
     - Elit 2500

2. Lig bazli minimum el + turn suresi tablosu son durumda su sekilde notlandi (onerilen omurga):
   - Standart: 2 el, 60 sn
   - Bronz: 2 el, 50 sn
   - Gumus: 4 el, 40 sn
   - Altin: 4 el, 35 sn
   - Elit: 6 el, 30 sn
   Not: Entry kolonunda Set B degerleri yer aliyor. Set A veya Set B secilmeden final tablo kilitlenmeyecek.

## 10) Uygulama Notu

Bu dokumanda yazan urun kurallari, teknik backlogdan once gelir.
Her gelistirme adiminda once bu bolume uygunluk kontrolu yapilacak.

## 11) Yurutme Stratejisi (Guncel)

Oncelik sirasini kullanici talebine gore guncelliyoruz:
1. Ana yapiyi tamamlama (auth, onboarding, lobby, masa, realtime, davet, mesajlasma temeli, odeme temeli)
2. Yapilmis / yapilmamis maddelerin checklist olarak kapanmasi
3. Oyun ici detay kural motoru (normal okey kurallari) - sonraki faz

## 12) Supabase Semasi Ihtiyaci

Ana yapiyi dogru kapatmak icin Supabase tablo/iliski bilgisini net gormemiz gerekiyor.
Paylasilmasi istenen minimum tablo listesi:
- `users`
- `profiles`
- `leagues`
- `tables`
- `table_players`
- `table_invites`
- `friendships` (veya arkadaslik icin kullandigin tablo adi)
- `messages` (veya sohbet icin kullandigin tablo adi)
- coin/odeme ile ilgili tablolar (varsa)

Beklenen bilgi formati:
- kolon adlari + tipler
- PK/FK iliskileri
- unique/index kurallari
- RLS policy ozeti (ozellikle select/insert/update)

## 13) Supabase Semasi (Alinan Gercek Cikti)

Kullanicidan alinan `information_schema.columns` ciktiya gore public semada aktif tablolar:
- `coin_transactions`
- `friends`
- `game_states`
- `invites`
- `leagues`
- `match_moves`
- `matches`
- `messages`
- `profiles`
- `rating_transactions`
- `rounds`
- `table_hands`
- `table_invites`
- `table_players`
- `tables`
- `turn_states`
- `users`
- `wallet_transactions`

### Urun hedefiyle dogrudan ilgili olanlar
- Kimlik/profil:
  - `users` (username, email, avatar_url, rating, moderation alanlari)
  - `profiles` (username, rating, coins, avatar)
- Lobby/masa:
  - `leagues` (min_rating, entry_coin, min_rounds, turn_seconds)
  - `tables` (league_id, status, max_players, entry_coin, min_rounds, current_round, current_turn, deck)
  - `table_players` (seat_index, hand, is_ready)
  - `table_invites`
- Oyun state:
  - `turn_states`
  - `game_states`
  - `table_hands`
  - `rounds`
  - `matches`, `match_moves`
- Sosyal:
  - `friends`
  - `messages`
- Ekonomi:
  - `coin_transactions`
  - `wallet_transactions`
  - `rating_transactions`

### Onemli gozlemler
1. `users.username` nullable.
   - Uygulama tarafinda isim zorunlulugu onboarding ile tamamlanmali.
   - DB seviyesinde `NOT NULL` / `CHECK` karari ayrica verilmelidir.

2. Hem `users` hem `profiles` tablosunda username/rating/coin benzeri alanlar var.
   - Tek dogruluk kaynagi secilmeli.
   - Mevcut urun kuralina gore isim kaynagi: `users.username`.

3. Davet icin iki tablo var:
   - `invites`
   - `table_invites`
   - Tek tabloya inmek bakim ve akisi sadeleştirir.

4. Oyun state icin birden fazla alternatif tablo var:
   - `tables.deck/current_turn`
   - `game_states`
   - `turn_states`
   - `table_hands`
   - Authoritative game state modelinde tek akisa indirgenmeli.

5. `leagues` tablosunda urun icin gerekli tum alanlar mevcut:
   - `entry_coin`, `min_rounds`, `turn_seconds`, `min_rating`
   - Bu alanlar dogrudan oyun akisini surukleyebilir.

## 14) Sonraki Netlestirme Ihtiyaci

Bu cikti kolon bazli bilgi veriyor; kodu guvenli kilitlemek icin su iki cikti daha gerekli:
1. PK/FK/UNIQUE constraint ciktilari
2. RLS policy ciktilari

Bu iki cikti geldikten sonra:
- `users.username` neden fallback'e dusuyor net tespit edilir
- join/ilişki hatalari kalici olarak kapanir
- hangi tabloda hangi is katmani tutulacak netlestirilir

## 15) Constraint / FK Analizi (Gelen 2. Cikti)

Kullanicidan gelen PK/FK/UNIQUE bilgilerine gore kritik bulgular:

### A) `users.username` problemi icin net bulgular
1. `users.username` UNIQUE var, ancak nullable (NOT NULL gorunmuyor).
   - Sonuc: kullanicida username bos kalabiliyor.
   - Uygulamada `Oyuncu N` fallback'ine dusme bu nedenle olasi.

2. `users` tablosunda `users_username_key` mevcut.
   - Onboarding tamamlandiktan sonra DB tarafinda bos username'i engellemek icin ek kural lazim.

### B) FK tutarsizliklari (cok kritik)
1. `table_invites.from_user` ve `table_invites.to_user` -> `profiles.id`
   - Uygulama kodu bircok yerde `user_id`/`users.id` ile calisiyor.
   - Bu fark davet akisinda sessiz bug ve gorunmez veri hatasi uretebilir.

2. `table_players` icin listede `user_id -> users.id` FK gorunmuyor.
   - Bu, iliski/join sorunlarinin temel sebeplerinden biri olabilir.

3. `tables.created_by_fkey` var ama hedef tablo/kolon ciktiya net dusmemis.
   - Muhtemelen `auth.users` veya `users.id` baglantisi var.
   - Kesin hedef tablo teyidi gerekli.

4. `profiles.id_fkey` var ama hedef tablo net gorunmuyor.
   - Genelde bu alan `auth.users(id)`'e baglanir.
   - Teyit edilmeden join stratejisi tam kilitlenmemeli.

### C) Model carpismalari
1. Davet tablolari:
   - `invites` ve `table_invites` ikisi birden var.
   - Tek davet tablosu standardi secilmezse kod karmasasi surer.

2. Oyun state tablolari:
   - `tables`, `game_states`, `turn_states`, `table_hands`, `matches`, `rounds` ayni probleme farkli cozumler sunuyor.
   - Authoritative state icin tek merkez secilmeli.

### D) Sosyal tablolar
1. `friends` tablosu PK/FK yapisi ciktida anomali gosteriyor (friends_pkey tekrarli/supheli maplenmis).
   - Muhtemelen composite key var (`user_id`, `friend_id`).
   - Gercek constraint SQL'i gorulmeden arkadaslik akisina gecilmemeli.

## 16) Bu Ciktidan Dogan Aksiyonlar

1. `users.username` zorunlu kilidi:
   - Uygulama: onboarding tamamlanmadan lobby/masa erisimini engelle.
   - DB: `users.username` icin NOT NULL + bos string kontrolu (karar sonrasi migration).

2. Davet FK standardi:
   - Karar: davette kimlik anahtari `users.id` mi `profiles.id` mi?
   - Kod ve FK ayni modele cekilecek.

3. `table_players.user_id` FK teyidi:
   - Yoksa eklenmesi gerekir.

4. `tables.created_by` hedef tablo teyidi:
   - `users.id` / `auth.users.id` netlestirilecek.

5. Arkadaslik ve mesajlasma:
   - `friends` composite PK/unique kurali net SQL ile dogrulanacak.

## 17) Beklenen Son Cikti (RLS)

Hala gerekli son parca:
- `pg_policies` ciktilari (RLS)

RLS gelince su iki konu kesin kapanacak:
1. Neden bazi kullanicilarda `users.username` okunamiyor?
2. Neden belirli sorgularda fallback'e dusuluyor?

## 18) Index Analizi (Gelen 3. Cikti)

Gelen `pg_indexes` verisine gore:

### Dogrulanan kritik noktalar
1. `friends` tablosu composite PK ile dogrulandi:
   - `friends_pkey (user_id, friend_id)`
   - Onceki pkey anomali suphesi kapanmistir.

2. `table_players` tarafinda koltuk cakismasi guvencesi var:
   - `table_seat_unique (table_id, seat_index)`
   - Ayni masada ayni koltuga ikinci oyuncu girisi DB seviyesinde engellenir.

3. `users` ve `profiles` username alanlari unique:
   - `users_username_key`
   - `profiles_username_key`
   - Ancak `users.username` nullable oldugu icin onboarding zorunlulugu halen gerekli.

4. Mesaj/ekonomi tablolarinda temel performans indexleri var:
   - `idx_messages_receiver`
   - `idx_rating_user`
   - `idx_wallet_user`

### Halen acik kalanlar
1. `table_players.user_id` icin FK bilgisi index ciktisindan gorulmuyor (beklenen zaten FK ciktisidir, burada yer almaz).
2. `table_invites` FK modeli `profiles.id` ile calismaya devam ediyor; uygulama modeliyle hizalanmasi gerekiyor.
3. RLS policy ciktilari halen eksik oldugu icin gercek okuma/yazma yetki davranisi kesin degil.

## 19) Bu Asamada Kesinlesen Teknik Sonuc

Ana yapi gelistirmelerinde su kabul yapilacaktir:
- Oturma duzeni:
  - `table_players` + `table_seat_unique` guvenli.
- Arkadaslik:
  - `friends (user_id, friend_id)` composite key modeline gore geliştirilecek.
- Username:
  - Ekran kaynagi `users.username`.
  - `users.username` bos ise onboarding tamamlatma zorunlu olacak.

## 20) RLS Durumu (Gelen Son Cikti)

Tum public tablolar icin `rls_enabled = false`.

Sonuc:
1. `users.username` fallback problemi RLS kaynakli degil.
2. Problem buyuk olasilikla veri eslesmesi / id modeli kaynakli.
3. Ozellikle `table_players.user_id` (auth user id) ile `users.id` birebir ayni degilse,
   - `users` sorgulari bos donecek
   - UI `Oyuncu N` fallback'ine dusecek.

## 21) Kilitlenen Kararlar (Kullanici Cevaplari)

Asagidaki kararlar kullanici tarafindan netlestirildi:

1. Profil ana kaynagi:
   - `users` (tek kaynak)

2. Davet tablosu:
   - "Mantikli olani kullan" karari teknik olarak tek tabloya inmeyi gerektirir.
   - Secim: `table_invites` (uygulama oyun masasi odakli oldugu icin)

3. Oyun state ana modeli:
   - "Mantikli olani kullan" karariyla asamali model secildi.
   - Secim:
     - Kisa vadede: `tables + table_players.hand` (mevcut akisla uyumlu)
     - Kural motoru oturunca: `turn_states` ve ilgili state tablolariyla server authoritative genisleme

4. Minimum blok bitti davranisi:
   - Oyuncu isterse cikar, isterse kalir.

5. Ceza yazimi:
   - `users` tablosu uzerinden uygulanacak.

6. Ceza kilidi kapsam:
   - Kilit suresinde oyuncu oyun oynayamaz ve mesaj atamaz.

7. Ekonomi:
   - Sistemde gercek cuzdan bakiye modeli olacak.

8. Oyun dogrulamasi:
   - Her zaman server tarafinda authoritative.
   - Kullanicinin belirttigi gibi Supabase functionlari kullanilacak (kodlari bekleniyor).

9. Surumleme:
   - "Ilk surumde kisitli kapsam" yok; tum secenekler hedef.
   - Uygulama plani fazli ilerlese de hedef kapsam tam.

10. Lig entry seti:
   - Set A kilitlendi:
     - Standart: 100
     - Bronz: 500
     - Gumus: 1000
     - Altin: 5000
     - Elit: 10000

## 22) Bir Sonraki Veri Ihtiyaci

Server authoritative akis icin kullanicinin belirttigi Supabase functionlarinin kodlari alinacak:
- Function adlari
- SQL / plpgsql govdeleri
- Beklenen input/output sozlesmeleri

## 23) Server Function Envanteri

### 23.1 `start-game` (alindi)

Amac:
- `table_players` kayitlarindan masa oyuncularini cekmek
- Deck uretip karistirmak
- Oyuncu ellerini dagitmak
- `tables` kaydini `playing` durumuna almak

Mevcut akistan cikan teknik notlar:
1. Dagitim su an her oyuncuya 14 tas veriyor.
   - Okey kuralinda baslayan oyuncu 15 tas alir.
2. Gosterge tasi / okey hesaplama su an yok.
3. Shuffle icin `Math.random()` kullaniliyor.
   - Server authoritative modelde deterministic veya cryptographic strateji karari gerekli.
4. Islem transaction degil.
   - Oyuncu ellleri update edilirken yari-da kalma riski var.
5. Fonksiyon sadece `tables.current_turn=0` yaziyor.
   - `turn_states` entegrasyonu henuz yok.
6. `joker: true` kullanimi ile istemci tarafindaki `isJoker/isFakeJoker` modeli birebir uyumlu degil.
7. Masa oyuncu sayisi `players.length` uzerinden alinmis.
   - `max_players` ile uyumsuzluk / eksik oyuncu baslatma kontrolu eklenmeli.

Oncelikli revizyon listesi (`start-game v2`):
- [ ] Baslayan oyuncuya 15 tas dagit
- [ ] Gosterge + gercek/sahte okey hesapla
- [ ] Tek transaction/RPC atomik yazim
- [ ] `turn_states` kaydi baslat
- [ ] Deck/tile payload formatini istemciyle standartlastir
- [ ] Oyuncu sayisi dogrulama (`players.length == table.max_players`)

### 23.2 `validate-okey` (alindi)

Amac:
- Verilen tas listesiyle elde bitis mumkun mu kontrolu (`valid: boolean`)

Mevcut yaklasim:
- Recursive backtracking
- Set ve run kombinasyonlari deneniyor
- Joker kullanimi icin temel destek var

Mevcut fonksiyondan cikan teknik notlar:
1. `isJoker` tek tip joker gibi ele alinmis.
   - Bizde gercek okey ve sahte okey ayrimi vardir.
2. Fonksiyon sadece "eldeki tum taslar gruplara ayrilabilir mi" sonucuna bakiyor.
   - Masa kurallari (son tas atimi, siradaki oyuncu vb.) kontrol etmiyor.
3. Okey varyant detaylari (same number set tekrar kurallari, wrap/run istisnalari vb.) net degil.
4. Input validasyonu sinirli.
   - Tile schema disi payload'a karsi sert kontrol yok.
5. Performance acisindan buyuk elde recursion maliyeti olabilir.
   - Timeout/guard eklenmesi gerekebilir.

Oncelikli revizyon listesi (`validate-okey v2`):
- [ ] Joker modelini bizim tile standardina uyarlama (`isJoker` + `isFakeJoker`)
- [ ] Kural kapsamini "normal okey"e gore netlestirme
- [ ] Input schema validasyonu ekleme
- [ ] Hesaplama guvenlik limiti (maks recursion/time guard)
- [ ] Sonuc objesini genisletme (neden gecersiz / hangi kombinasyonlar)

## 24) Function Entegrasyon Sirasi

Server authoritative hedefe gore sira:
1. `start-game v2` (dogru dagitim + state baslatma)
2. `draw/discard` RPC'leri (henüz kodu alinmadi)
3. `validate-okey v2` ile bitis dogrulamasi
4. Round/ceza/rating hesaplari (minimum blok modeline gore)

## 25) Sifirdan Uygulama Plani (Masa Acmaya Kadar)

Bu bolum, "en bastan masa acmaya kadar eksiksiz" hedefi icin zorunlu is listesidir.
Bu liste tamamlanmadan oyun ici kurallara gecilmeyecek.

### A) Auth ve hesap olusturma
- [ ] Register ekrani:
  - Email/sifre validasyonu
  - Supabase signup cagri
  - Basarili kayitta "mail onaylandi mi?" yonlendirme metni
- [ ] Email callback (web) kurgusu:
  - Mailde gelen link tiklandiginda su formatta acilis oluyor:
    - `http://okeyix.com/?code=<supabase_auth_code>`
  - `okeyix.com` yayinlandiginda bu callback yakalanip kullanici dogru akisa alinmali
  - Gerekirse ara bir "Dogrulama tamamlandi, uygulamaya don" sayfasi tasarlanacak
- [ ] Email dogrulama sonrasi login:
  - Dogrulanmamis kullaniciya lobby erisimi yok
  - Hata mesajlari acik ve Turkce
- [ ] Session yonetimi:
  - Oturum aciksa dogrudan lobby
  - Oturum kapaliysa login

Kabul kriteri:
- Yeni kullanici kayit olur, mail onaylar, login olur, lobbyye girer.

### B) Onboarding (username + avatar zorunlu)
- [ ] Login sonrasi `users` kaydini kontrol et
- [ ] `users.username` veya `users.avatar_url` yoksa zorunlu onboarding modal/acilis sayfasi
- [ ] Onboarding tamamlanmadan lobby ana aksiyonlari kapali
- [ ] Username unique ihlali hata mesaji

Kabul kriteri:
- Eksik profil ile lobbyde masa ac/katil yapilamaz.

### C) Lobby temel verileri
- [ ] Header:
  - `users.username`
  - coin/rating (tek kaynak kurala gore)
- [ ] Lig listeleme:
  - `leagues` display_order ile
  - min_rating kilit gostergesi
- [ ] Acik masalar:
  - secili lig + `status=waiting`
  - max_players, entry_coin, olusturan bilgisi

Kabul kriteri:
- Lig degisince masa listesi dogru filtrelenir.

### D) Sosyal iskelet (masa oncesi)
- [ ] Arkadas listesi kaynagi `friends`
- [ ] Mesaj paneli kaynagi `messages`
- [ ] Ceza kilidinde mesaj gonderimi engeli (kural 6)

Kabul kriteri:
- Arkadas olmayanla mesajlasma acik degil.

### E) Coin magazasi iskeleti (Lemon hazirlik)
- [ ] Coin magazasi UI
- [ ] Paketlerin config tablosu/objesi
- [ ] Lemon checkout baslatma noktasi (mock/placeholder olabilir)

Kabul kriteri:
- Lobbyde coin satin alma akisina giris noktasi calisir.

### F) Masa olusturma (hedef bitis noktasi)
- [ ] Masa olusturma formu:
  - lig, kisi sayisi (2/4), entry
- [ ] Olusturma dogrulamalari:
  - coin yeterlilik
  - min rating
  - ceza kilidi (oynayamaz)
- [ ] DB yazimi:
  - `tables` insert
  - olusturanin `table_players` kaydi (seat 0)
- [ ] Masa olustuktan sonra oyun ekranina gecis

Kabul kriteri:
- Kural disi kullanici masa acamaz.
- Kurali saglayan kullanici tek tikla masa acar ve oyuna girer.

## 26) Bu Plana Gore Uygulama Sirası (Net)

1. Auth + session
2. Onboarding kilidi
3. Lobby veri baglantilari
4. Sosyal temel
5. Coin magazasi iskeleti
6. Masa olusturma akisi

Not:
- Her adim bitince bu dokumanda ilgili checkbox kapanacak.
- "Eksik bir sey kalmasin" hedefi icin her adimda kabul kriteri test edilmeden sonraki adıma gecilmeyecek.

## 27) Sosyal Panel ve Ortak Profil Karti (Yeni Net Kurallar)

- [x] Alt bar:
  - Arkadas butonunda badge = toplam arkadas sayisi
  - Mesaj butonunda badge = okunmamis mesaj sayisi
  - Bu iki butona basinca sagdan acilan buyuk panel acilacak
- [ ] Sol menu:
  - `Ayarlar` secenegi olacak
  - Ayarlar secenegi de sag panelde ilgili sekmeyi acacak
- [x] Arkadas paneli:
  - Sadece arkadaslar listelenecek
  - Her satirda avatar + kullanici adi olacak
  - Satira tiklaninca ortak profil karti acilacak
- [x] Mesaj paneli:
  - Sol: arkadas listesi
  - Sag: secili arkadas ile chat gecmisi
  - Alt: mesaj yazma alani + gonder butonu
  - Mesajlasma sadece arkadaslar arasinda aktif
- [x] Ortak profil karti:
  - Arkadas listesinden acilabilir
  - Lobby masa avatarina tiklaninca acilabilir
  - Kendi avatarina tiklaninca acilabilir
  - Diger kullanici icin:
    - arkadaslik istegi gonder
    - arkadasliktan cikar
    - engelle / engel kaldir
  - Kendi kartin icin:
    - isim degistir
    - avatar degistir
- [ ] Arkadaslik akisi:
  - Istek gonderilen kullanici kabul ederse arkadas olunur
  - Engellenen kullanici arkadaslik istegi gonderemez
- [ ] Engelli kullanici gorunurlugu:
  - Lobby masa avatarlarinda engelli kullaniciya ait isaret gosterilecek

## 28) Coin Paketleri ve Fiyatlandirma (Ilk Taslak)

- [x] Magaza ekrani olusturuldu (`StoreScreen`)
- [x] Paket tipleri ve fiyatlari UI icinde sabitlendi (Lemon baglantisina hazir)

Mevcut paketler:
- Deneme: 10.000 coin, bonus yok, 9,99 TL
- Baslangic: 25.000 coin + 2.500 bonus, 24,99 TL
- Standart: 60.000 coin + 9.000 bonus, 59,99 TL
- Pro: 150.000 coin + 22.500 bonus, 149,99 TL
- Elit: 300.000 coin + 60.000 bonus, 299,99 TL
- Mega: 600.000 coin + 120.000 bonus, 599,99 TL

Not:
- Bu degerler ilk taslaktir.
- Denge karari: max masa entry (2.500) ile coin + fiyat paketleri dogru orantili hale getirildi.
- Lemon odeme callback'i baglandiginda satin alma sonrasi cuzdana coin yazimi backend tarafinda kesinlestirilecek.

## 29) Kaldigimiz Yer Ozeti (Sabit)

Bu bolum her oturum sonunda guncellenir ve "kaldigimiz yeri" sabit tutar.

### Son tamamlananlar
- Lobby ana ekran premium revizyonlari yapildi:
  - Sol panel (`OKEYIX`, `Hemen Oyna`, `Magaza`) gorsel olarak guclendirildi
  - Alt bar premium gradient + isik efektine cekildi
  - Orta `Masa Ac` butonu premium stile alindi
  - Lig kutulari lig renklerine gore temalandi (icon + baslik + alt satir + border tonu)
- Masa listesi revizyonu yapildi:
  - 2 kolon grid gorunumu aktif
  - Masa kartlari yeniden tasarlandi
  - `assets/images/table_list.png` kart arka plani olarak baglandi
  - Masa metni sadeleştirildi (`Masa Coin`)
- Sosyal katmanin calisan temel surumu eklendi:
  - Arkadas paneli
  - Mesaj paneli (arkadas listesi + chat + gonder)
  - Ortak profil karti (kendi/diger oyuncu aksiyonlari)
  - Alt bar badge sayaclari (arkadas + okunmamis mesaj)
- Magaza ekrani olusturuldu ve lobbyden baglandi.
- Yeni uye onboarding akisina baslangic coin destegi eklendi (welcome coin: 1000).
- Coin okumada `users.coins` fallback aktif edildi; yeni uye standart masaya coin yok diye takilmaz.
- Profil tamamlama/duzenleme tek ekranda birlestirildi:
  - Onboarding ekrani gorsel olarak yenilendi
  - 12 adet secilebilir avatar preset eklendi
  - Profil kartinda "Isim Degistir + Avatar Degistir" yerine tek "Duzenle" aksiyonu aktif
  - Secilen username + avatar `users` tablosuna yazilip tum UI'da ortak kullaniliyor
- Oyun baslatma:
  - Creator tarafinda masa doldugunda `start-game` (edge function / RPC fallback) otomatik tetiklenir.
- UTF-8/encoding korumasi eklendi:
  - `.editorconfig` (utf-8)
  - `.vscode/settings.json` (`files.encoding: utf8`)

### Acik kalan kritik maddeler
- Server authoritative oyun akisi (RPC/transaction) tamamlanmadi.
- `start-game` ve `validate-okey` v2 revizyonlari acik.
- Lemon odeme callback + gercek satin alma/yazim akisi acik.
- RLS/policy guvenlik katmani hala acik.
- Bazi plan checklist maddeleri dokumanda [ ] durumda, ama bir kisminin kodu fiilen atildi; checklist senkronu duzenli guncellenmeli.

### Sonraki net adim (onerilen)
1. `docs` checklist senkronizasyonu: fiilen yapilanlari [x] olarak guncelle.
2. Sosyal akisin DB kurallari: block/friend request kisitlarini policy/trigger ile zorunlu kil.
3. Magaza: paketleri DB config'e tasi + Lemon checkout endpoint bagla.
4. Oyun cekirdegi: `start-game v2` + tur state machine RPC.

## 30) Oyun Akisi Onarim Plani
- Ayrintili teknik plan: `docs/okey_game_flow_recovery_plan.md`

## 31) Kilitli Oyun Kurali Seti (Kullanici Onayi)
Ayrintili kural listesi `docs/okey_game_flow_recovery_plan.md` dosyasinda `## 9)` altinda kilitlendi.
Sonraki tum oyun motoru degisiklikleri bu kurallara birebir uyacak.
