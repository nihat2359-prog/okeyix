# Oyuncu profil kartı — 1. aşama

Ortak `ProfileService.showUserCard` girişi yeni `PlayerProfileCard` bileşenini
kullanır. Kendi profilindeki düzenleme/hediye geçmişi ve diğer oyunculardaki
mevcut arkadaşlık/hediye/engelleme/şikâyet işlemleri korunur. Sonraki aşamada
eklenen karşılaştırma/paylaşım özelliğinin ayrıntıları `player_comparison.md` içindedir.

## Kurulum

007 kuruluysa SQL Editor ile yalnızca
`supabase/migrations/20261020000800_profile_career_breakdown.sql` dosyasının
tamamını bir kez çalıştırın. 007 henüz kurulmadıysa önce 007, sonra 008 uygulanır.
Kurulu migration dosyalarını yeniden çalıştırmayın.
008 canlıya ajan tarafından uygulanmadı. Flutter sürümünü bu okuma
RPC'si kurulduktan sonra yayınlayın. RPC eksik veya erişilemezse kart hata/tekrar
dene durumu gösterir; mevcut kariyer sayıları okunabildiyse görünür kalır.

## Sayım ve güvenlik

- Ana galibiyet/mağlubiyet değerleri `users.wins` / `users.losses` kariyer
  sayaçlarından gelir. Toplam oyun ve kazanma oranı bu değerlerden hesaplanır.
  Böylece mevcut oyuncunun kayıt öncesi birikimi korunur. Veri okunamazsa sıfır
  yerine bilinmeyen değer işareti gösterilir.
- Tek “Galibiyetlerin” grubunda Önceki kazanımlar / Normal / Okeyli / Çiftli
  bulunur. Önceki kazanımlar = kariyer galibiyeti − kayıtlı tekil galibiyet.
  Kariyer sayaçları ve bitişler aynı sunucu snapshot'ında okunur. Detay kaydı
  olmayan oyuncunun kazanımları Önceki kazanımlar olarak görünür. Bunlar normal
  bitiş diye etiketlenmez; geçmiş için sahte el oluşturulmaz.
- Kariyer sayacı NULL veya kayıtlı galibiyetten küçükse önceki kazanımlar NULL
  döner. Arayüzde sıfır/negatif sayı üretilmez; bilgi ikonunda eşleştirme durumu
  açıklanır. Eksik yeni kayıt varsa farkın eski dönem olduğunu kesin varsaymayız;
  tooltip “Bitiş türü kaydedilmeyen galibiyetler” der.
- Bitiş sayıları yalnızca kazanılan elleri ifade eder. Normal: iki bayrak da
  false. Okeyli ve çiftli: ilgili bayrak true. İkisi true ise iki başlığa da
  dahildir; bilgi ikonlarında ortak sayı ayrıca belirtilir.
- Tamamlanmış, kuyrukta bekleyen olaylar aynı SQL snapshot'ında kalıcı sonuçlarla
  birleştirilir. Terminal kalıcı kaydı bulunan olay yeniden sayılmaz. Bu yüzden
  cron projeksiyonunu beklemek gerekmez.
- Authenticated kullanıcı hedef oyuncunun sadece toplu sayaçlarını okuyabilir.
  Fonksiyon sahibi postgres; sabit search_path ve açık hedef filtresi kullanır.
  anon/service_role/PUBLIC EXECUTE kapalıdır. RLS ve özel kuyruk yetkileri açılmaz.
- Her kart açılışında tek istatistik isteği vardır. Otomatik polling yoktur.
  Kullanıcı değişince eski future sonucu yeni karta taşınmaz. Manuel tekrar
  deneme dışında rebuild yeni istek başlatmaz.

## Yerel doğrulama

`test/player_profile_card_test.dart`: küçük yatay ekranlar (568×320, 667×375,
844×390), metin ölçeği 1/1.3, açık aksiyonlar, yükleme/hata/tekrar deneme,
eski oyuncunun gecikmiş cevabı, bitiş bayrağı tutarlılığı.

Kart eski profilin kimlik satırı, seviye/coin alanı ve dört doluluk çubuğu
düzenini korur. Kariyer çubukları galibiyet, mağlubiyet, toplam ve kazanma
oranını gösterir. Oyuncu ID'si alt satırda seçilebilir.

Kısa yatay ekranlarda avatar, seviye/coin alanları, çubuklar ve düğmeler kompakt
ölçülere geçer. Orta bölüm kaydırma alanı değildir; kalan alana yalnız gerektiği
kadar küçülerek sığar. Başlık, kapatma ve işlem şeridi bu ölçeklemenin dışındadır.
Oyuncu ID'si de yatay kaydırma oluşturmadan satıra sığdırılır. 480×270, 568×320
ve 667×375 ölçülerinde güvenli alan ve %130 metinle bütün rozetlerin/düğmelerin
erişilebilir ve scroll mesafesinin sıfır olduğu test edilir.

İşlem şeridinde en fazla beş eylem doğrudan görünür; daha büyük eylem kümeleri
etiketli Diğer menüsüne taşar. Sosyal eylemler önce sıralanır. Böylece mevcut
arkadaş kartında Karşılaştır/Hediye/Çıkar/Engelle/Şikayet birlikte
sığar. Karşılaştır yalnız oturum sahibinden farklı profilde görünür. Yedi eylemli test düzeni
küçük yatay ekranda menü erişimini doğrular.

`test/statistics/profile_statistics.sql`: yalnız izole localhost test veritabanı
içindir ve ROLLBACK ile biter. Başka oyuncuyu okuma, bot, boş geçmiş, NULL/eksik
oyuncu, anon/yetki sınırı, yarım kalan elin dışlanması, birleşik bitiş ve
projeksiyon öncesi/sonrası aynı sayım kontrol edilir. Canlıda çalıştırmayın.
