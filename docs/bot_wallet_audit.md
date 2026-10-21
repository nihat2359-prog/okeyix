# Bot çip yönetimi: kaynak incelemesi

Durum: kullanıcının paylaştığı canlı envanter ve fonksiyon sözleşmeleri alındı.
`20261021000400_bot_wallet_reserve.sql` hazırlandı; staging/canlıya uygulanmadı.
Yerel PostgreSQL 16 contract-double testleri geçti. Asistan üretim veritabanına
bağlanmadı. Kurulum ve test sınırları için `bot_wallet_reserve.md` dosyasına bakın.

## Doğrulanan kaynaklar

- `lib/screens/lobby_screen.dart`: `_loadLeagues()` doğrudan `public.leagues`
  okur; `_showCreateModal()` ligdeki `min_coin/max_coin` aralığını kullanır.
- `lib/core/table_creation_options.dart`: `buildTableStakes` maksimumu seçeneklere
  dahil eder; `tableCreationPayload` seçimi bu aralıkla doğrular.
- `test/table_creation_options_test.dart`: Şampiyonlar örneği 3M–10M'dir.
  Bu bir test girdisidir; canlı lig yapılandırmasının kanıtı değildir.
- `docs/supabase_join_table_safe.sql`: `join_table(uuid,uuid,int)` masa kilidi,
  profil satır kilidi, `profiles.coins` yeterlilik kontrolü, giriş kesintisi,
  `wallet_transactions(reason=table_entry)` ve üyelik eklemesini aynı işlemde yapar.
- `docs/supabase_game_finish_full.sql`: ödül `profiles.coins` alanına eklenir,
  `game_win` makbuzu oluşur; sonraki elden önce bakiyesi girişten düşük olanlar
  çıkarılabilir. Ödül formülü değiştirilmemelidir.
- `docs/supabase_game_rpc.sql`: zaman aşımı ve atış yolları da ceza/ödül
  bakiyelerini etkileyebilir. Bunlar farklı tarihli SQL sözleşmeleridir.
- Hediye migration'ı göndereni borçlandırır; referans migration'ı uygun insan
  hesaplarına ödül ekler. Bu akışlar değiştirilmemelidir.
- Bot kimliği `public.users.is_bot` üzerinden okunur. Bot oluşturma ve otomatik
  masaya yerleştirme fonksiyonlarının tanımları kaynak ağacında bulunmuyor.

## Envanter neden gerekli?

Takviye bakiye kontrolünden ÖNCE çalışmalı. `table_players` INSERT trigger'ı
join içindeki ön bakiye kontrolünden sonra kalır ve sıfır bakiyeyi kurtaramaz.
`profiles.coins` UPDATE trigger'ıyla kesintiyi gizlice değiştirmek ise normal
maç muhasebesini ve önce/sonra bakiye farkına bakan istatistikleri bozabilir.
Bu nedenle bu iki kestirme uygulanmadı.

`is_bot` işaretine tek başına güvenmeden önce istemci yazma yetkileri ve mevcut
sunucu bot oluşturma zinciri doğrulanmalıdır. Genel bir para artırma RPC'si
ve sırf bu belirsizliği örtmek için cron eklenmemelidir.

## Hedeflenen sözleşme

En büyük geçerli lig giriş bedeli veritabanının gerçek lig ayarlarından okunur.
Paylaşılan envanterde bu değer 10.000.000'dur. Eşik 5 katı (50M çip), hedef
20 katıdır (200M çip); çarpanlar özel politika tablosunda merkezidir.
Profilin coin türü kapasitesini aşan ayar sessizce kırpılmamalı, hata vermeli.

Sunucunun doğruladığı bot için profil satırını kilitle; kilitten sonra bakiyeyi
tekrar kontrol et. Eşik üstünde değişiklik yapma. Eşik altında yalnızca
`hedef - mevcut` farkını ekle ve aynı transaction'da denetim makbuzu oluştur.
Başarısız denetim yazımı da yüklemeyi geri almalı. İnsan hesapları değişmemeli.
İstemciye doğrudan çağrılabilir bir takviye endpoint'i verilmemeli.

İlk incelemenin ardından sağlanan gerçek sunucu sözleşmesi, watchdog'un zaten
dakikalık cron ile çalıştığını doğruladı. Takviye bu mevcut göreve ve bot masa
bakımına eklendi. Güvenlik/işlem testleri yalnızca yerel fixture üzerinde geçti;
staging ve üretimde etkinleşmesi migration'ın ayrıca uygulanmasını gerektirir.
