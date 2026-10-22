# Hızlı Oyna — beklemesiz eşleştirme

## Yeni akış

1. Seçili lobi sekmesine bakılmaksızın, bakiyenin ve mevcut lig kurallarının
   izin verdiği tüm liglerdeki katılınabilir gerçek oyuncu masaları taranır.
   Herkese açık, bekleyen, iki koltuklu, bir gerçek oyuncusu olan ve sahibi
   aktif masalar seçilir. Kilitli/dolan aday atlanır; özel masa seçilmez.
2. Uygun masa varsa mevcut masaya katılınır. Yeni masa oluşturulmaz.
3. Uygun masa yoksa oyuncunun sunucudaki rating aralığına göre bulunduğu lig
   belirlenir; seçili lobi kartı kullanılmaz. O ligin `min_coin` değeri alınır.
4. Uygun bot kilitlenir; insan ve bot koltuklarıyla masa aynı transaction'da
   oluşturulur. Doğrudan mevcut oyun başlangıcına geçilir. 10 saniye bekleme,
   Rakip Bekle veya Botla Başla seçenekleri yoktur.
5. Bot yoksa işlem hata verir, transaction geri alınır. Boş masa bırakılmaz.
   Botla oynanacağı panelde açıkça belirtilir; bot gerçek oyuncu gibi tanıtılmaz.

Ücret yine mevcut `start_game` akışında kesilir. Hızlı Oyna coin yazmaz;
oyun kuralları, bot motoru, taş dağıtımı ve ödüller değiştirilmez. Eski
`join_table` ayrıca ücret kestiğinden çağrılmaz; mevcut lobinin koltuk eklemesi
sunucu kontrolleri ve kilitlerle yapılır. Başlangıç yine `OkeyGameScreen`'dir.

## Migration

Yeni düzeltme: `supabase/migrations/20261022000200_quick_play_instant.sql`.
**Canlıya uygulanmadı. Önce staging'de doğrulanmalı.**

- 001 zaten uygulandıysa yalnız 002'yi uygulayın.
- Hiçbiri uygulanmadıysa önce 001, hemen ardından 002'yi uygulayın. Flutter
  sürümünü iki migration tamamlandıktan sonra yayınlayın.
- 001 önceki beklemeli tasarımın migration kaydı olarak korunur; çalışma
  davranışını 002'deki CREATE OR REPLACE FUNCTION belirler.
- `p_league_id` eski istemcilerle RPC imzasını korumak için tutulur; yeni
  aramada belirleyici değildir ve yeni istemci bu parametreyi göndermez.

Eski beklemeli tasarımdan kalmış tek kişilik bir istek yeni istemci tarafından
iptal edilebilir. O istek yeni beklemesiz bir işlemmiş gibi sessizce devam etmez.

## Güvenlik ve hata yönetimi

İstek UUID'si aynı işlemde sabittir; kayıp yanıt ve tekrar deneme ikinci masa
oluşturmaz. Kullanıcı ve bot talepleri advisory lock, masalar satır kilidi ve
koltuk benzersizliğiyle korunur. İptal önce ulaşırsa geciken başlangıç engellenir.
Eşleşme zaten commit edilmişse iptal rakibin koltuğunu silmez, hazır maça geçer.

Kullanıcı ID'si auth.uid() üzerinden alınır. Coin, rating ve bot kimliği
sunucudan okunur. Bot olmak için is_bot bayrağı yeterli değildir: auth.users
hesapları bot olarak seçilmez. Endpoint authenticated dışındaki rollere kapalıdır.
Mevcut manuel bot davet yollarının davranışı bu migration ile değiştirilmez.

İstemci 15 saniyede yanıt alamazsa sunucu işlemini iptal olmuş saymaz; aynı UUID
ile tekrar doğrular veya iptal ister. Sürekli sorgu/polling, bekleme timer'ı ve
Realtime kanalı yoktur. Yalnızca eşleştirme isteği, manuel tekrar/iptal bulunur.

## Testler

`flutter test test/quick_play_test.dart test/table_creation_options_test.dart`

`powershell -NoProfile -File tool/test_quick_play.ps1`

Yerel PostgreSQL aracı iki migration'ı birlikte test eder. Kapsam: farklı lobi
sekmesinden başka lige katılma, yüksek uygun lige katılma, kendi liginde minimum
bedelle anında bot, idempotency, erken/geç iptal, yetersiz bakiye, özel masa,
uygun bot yokken boş masa bırakmama, sahte bot/anon erişimi ve iki eşzamanlı
isteğin koltuk yarışı. Coin değişmediği ayrıca kontrol edilir.

SQL fikstürleri mevcut leave_table ve masa trigger'ının sözleşme test çiftleridir;
canlı Supabase ve gerçek ücret/dağıtım fonksiyonlarının yerine geçmez. Staging'de
iki cihazla gerçek insan eşleşmesi ve otomatik bot başlangıcı doğrulanmalıdır.