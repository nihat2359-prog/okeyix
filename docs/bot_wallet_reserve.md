# Bot çip rezervi

**Hazır, canlıya uygulanmadı.** Migration:
`supabase/migrations/20261021000400_bot_wallet_reserve.sql`.
Flutter, bot zekâsı, oyun RPC'leri, hediye/referral ve maç ödül formülleri değişmez.

## Canlı sözleşmeden doğrulanan ekonomi

Kullanıcının gönderdiği envanterde `leagues(id=elite)` Şampiyonlar aralığı
3.000.000–10.000.000; bütün liglerdeki en yüksek `max_coin` 10.000.000'dur.
Kaynak: lobby `_loadLeagues`, `_showCreateModal`, `buildTableStakes` bu sütunları
kullanır. Migration bedeli sabitlemez; her bakımda `max(leagues.max_coin)` okur.

`profiles.coins` ve `wallet_transactions.amount` integer'dır. Politika 5/20
çarpanlarını kullanır: mevcut ayarlarla **50M alt eşik, 200M hedef**. Tam 50M'de
değişiklik yoktur; altında yalnızca hedefe eksik fark eklenir. Büyük kazançlar
azaltılmaz. NULL bakiye sıfır kabul edilir. Negatif/missing cüzdan hata verir.
Hedef integer kapasitesini aşarsa para kırpmak yerine işlem reddedilir.

Güncel `join_table(uuid,uuid,int)` giriş bedelini keser; `source_start_game`
her el başında ayrıca giriş keser. Bot masa bakımı ise doğrudan üyelik ekler,
join RPC çağırmaz. Bu mevcut fark ve ödül/ceza işlemleri değiştirilmedi.
Botların ilk oluşturulma SQL'i sunulan bakım fonksiyonunda yoktur: fonksiyon
mevcut `users.is_bot` hesaplarını seçer; yeni hesap oluşturmaz.

## Otomatik çalışma

- Kurulumda mevcut uygun botlar bir kez kayıt/takviye edilir.
- Zaten var olan `okey_watchdog_job` dakikada bir postgres olarak çalışır.
  Önce orijinal watchdog (ve varsa oyun/istatistik yakalama) tamamlanır,
  ardından rezerv kontrol edilir. Dönüş JSON'u korunur. **Yeni cron yoktur.**
- `run_standard_bot_table_maintainer(...,true)` seçmeden önce takviye yapar.
  `p_apply=false` takviye yapmaz. Eski `coins <= v_max_coin` filtresi kaldırılır;
  aksi halde 200M rezervli bot Acemiler bakımından tamamen dışlanırdı.
  Yalnızca kayıtlı botlar seçilir; masa sayısı, ligi ve giriş bedeli değişmez.
- Bu görev bütün liglerdeki uygun botların parasını destekler; yeni bir
  Şampiyonlar bot-masa oluşturucusu eklemez. Mevcut otomatik masa oluşturucu
  hâlâ sadece standard ligini hedefler.
- Kontrol anlık coin SELECT trigger'ı değildir. Watchdog kontrolleri arasında
  en fazla mevcut cron aralığı kadar gecikme olabilir. 5 yüksek girişlik rezerv
  bunu tamponlar; sıfırlandıysa sonraki watchdog/masa bakımı yeniden destekler.

## Güvenlik ve atomiklik

Envanterde users RLS kapalı ve anon/authenticated `is_bot` yazabiliyor.
Sadece bu bayrağı canlı okuyup para vermek güvenli olmadığından özel registry
kullanılır. Mevcut kayıtlar kurulum sırasında postgres tarafından benimsenir.
**auth.users ile eşleşen hesaplar, is_bot=true olsa bile asla fonlanmaz.**
Böyle bir kayıt gerçek bir bot ise otomatik fonlanmaz; kimliği ayrıca incelenmeden
bu koruma kaldırılmamalıdır. Ön kontrol bu kayıtların yalnızca sayısını gösterir.

Yeni bot kaydı yalnızca postgres SQL/cron veya gerçek service_role bağlamında
is_bot=true yazıldığında otomatik eklenir. Doğrudan istemci INSERT/UPDATE,
bot kimliğini silme/değiştirme ve authenticated bir SECURITY DEFINER aracılığıyla
kendini bot yapma engellenir. Normal kullanıcı avatar/isim güncellemeleri korunur.
Mevcut users RLS yapısı topluca değiştirilmez; bu genel erişim yetkilerinin
tamamının güvenlik denetimi değildir.

Takviye fonksiyonları özel şemadadır, istemciye USAGE/EXECUTE yoktur.
Mevcut iki bakım endpoint'i anon/authenticated rollerinden kapatılır;
yalnızca postgres ve service_role çalıştırır. JWT ve dış role kontrolü definer
sahibinin postgres olmasını istemciye yetki olarak yorumlamaz.

Her eksik profil `FOR UPDATE SKIP LOCKED` ile kilitlenir. Eşzamanlı ikinci
bakım kilitli botu atlar; bir sonraki bakım tekrar kontrol eder. Para ve özel
`topups` denetim makbuzu tek transaction'dadır; makbuz hatası hepsini geri alır.
Makbuz mevcut insan cüzdan hareketlerine yapay bir oyun ödülü olarak eklenmez.

## Yerel test ve sınırları

Çalıştırma: `powershell -File tool/test_bot_wallet.ps1` (PostgreSQL 16 bin yolu
gerekirse `-PgBin` ile verilir). Script workspace altında yeni izole cluster
oluşturur, yalnızca loopback port 56484 kullanır, kendi cluster'ını doğrular ve
sonunda durdurur. Mevcut Supabase'e bağlanmaz veya veritabanı silmez.

Fixture gerçek şema/rol/PLpgSQL sözleşmelerini temsil eder; watchdog ve bakım
gövdeleri contract-double'dır. Değiştirilmemiş migration'ın bu farklı gövdeleri
reddettiği test edilir; finans testleri için SADECE iki beklenen fingerprint
geçici migration kopyasında fixture hash'leriyle değiştirilir. Üretim migration'ı
değiştirilmez. Gerçek sağlanan fonksiyonlarla staging testi hâlâ gereklidir.

Doğrulanan senaryolar:

| Senaryo | Yerel sonuç |
|---|---|
| Yeterli/eşik seviyesindeki bot | Bakiye ve makbuz değişmedi |
| Eşik altı, sıfır ve NULL bakiye | Hedefe yalnızca fark eklendi |
| Şampiyonlar maksimum girişi | Hedef bunu karşılıyor |
| Normal ve auth bağlantılı sahte bot | Para eklenmedi |
| authenticated/anon sahte bayrak/INSERT | Yetki hatası |
| Definer aracılığıyla sahte bayrak | Yetki hatası |
| Public/private takviye çağrısı | İstemciye yetki yok |
| İki gerçek bağlantıda kilit çakışması | Tek takviye, tek makbuz, tam hedef |
| Maç giriş/ödül işlemleri | Aynı gövdeler ve aynı tutarlar |
| Makbuz yazılamaması | Takviye ve watchdog atomik geri alındı |
| Tekrar kontrol / kapalı politika | Gereksiz yükleme yok |
| Lig maksimumunun değişmesi | Yeni hedef dinamik hesaplandı |
| Integer taşması | Açık hata; kısmi işlem yok |
| Yüksek rezervli botun standard bakımı | Eski üst sınır artık dışlamıyor |
| Yetkili service_role | Mevcut bakım girişinden çalışıyor |

## Staging ve canlıya alma

1. Önce `docs/bot_wallet_preflight.sql` çalıştırın. Geçerli aralık, integer
   kapasitesi, iki source fingerprint ve aktif postgres watchdog doğrulanmalı.
   Eksik/negatif bot cüzdanları ve auth bağlantılı bot işaretleri incelenmelidir.
2. Migration'ı önce staging'e uygulayın. Source fingerprint farklıysa durur;
   korumayı silip körlemesine uygulamayın. Staging'e güncel kaynak sözleşmelerini
   güvenle eşitleyin veya farkı inceleyerek migration'ı yeniden değerlendirin.
3. `docs/bot_wallet_installation_check.sql` sonucunu kontrol edin. İstemci EXECUTE
   ve private schema access false, iki kimlik guard'ı true olmalı. Eksik cüzdan
   olmamalı; kilitli botlar sonraki bakımda tekrar kontrol edilir.
4. Staging'de düşük ve yeterli bakiyeli botla standard/elite masa akışını ve bir
   normal oyuncuyla giriş/ödül akışını doğrulayın. Mevcut watchdog'un bir sonraki
   dakikalık çalışmasını kontrol edin. Uygulama açık olmak zorunda değildir.
5. Kontrollerden sonra aynı migration'ı canlıya siz uygulayabilirsiniz.
   Flutter dağıtımı veya yeni cron kurulumu gerekmez.

Merkezi ayar sadece postgres tarafından
`okeyix_bot_wallet_private.policy` satırından değiştirilir (enabled,
low_multiple,target_multiple). Bot bakiyelerini elle ayarlamak gerekmez.
