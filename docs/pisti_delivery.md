# Güncel ürün kararı — Pişti Molası

31 Ekim 2026: Açılış doğrudan Okey lobisidir. Çok oyunlu ana ekran kaldırıldı. Pişti Molası botla veya mevcut arkadaşla ücretsiz özel maçtır; açık liste, rastgele eşleşme ve kariyer girişi gösterilmez. Oyun sahnesi, puanlar, kart animasyonları, tema, davet ve yeniden bağlanma korunur. Sunucuda casual maçlar coin/ledger/rating değiştirmez. [Güncel teknik rehber](pisti_release.md). Aşağıdaki notlar önceki teslimin tarihsel kaydıdır.

# Pişti üretim entegrasyonu

## İnceleme ve uygulama planı

Mevcut demo `lib/dev/pisti` altında yerel `PistiGame` kullanıyor. Okey
`tables/table_players` tetikleyicileriyle başlıyor; bu tabloların Pişti için
kullanılması Okey dağıtımını ve ücret kesimini çalıştırır. Pişti oturumları
ayrı tutulacak; kimlik `auth.uid()`, bakiye `profiles.coins`, muhasebe
`wallet_transactions`, arkadaşlık `friends`, hediye kataloğu
`okeyix_gift_catalog` üzerinden sürdürülecek. Okey rating alanları değişmeyecek.
Web admin projesi `../okeyix_web` altında mevcut.

1. Ortak kart yardımcıları, sunucu Pişti motoru ve kural testleri.
2. Eklemeli özel durum deposu, atomik masa/ekonomi RPC'leri, güvenli snapshot.
3. Edge hamle işleyicisi, bağımsız zamanlayıcı, bot ve yeniden bağlanma.
4. Landscape lobi ve mevcut animasyon sahnesinin çevrimiçi adaptörü.
5. Davet/sosyal/seyirci, ayrı kariyer ve admin yönetimi.
6. Güvenlik/ekonomi testleri, Flutter analiz/test/derleme ve yayın yönergesi.

## Tamamlanma kontrol listesi

- [x] Kural motoru, puanlama/çoğunluk/beraberlik ve tam maç testleri
- [x] Gizli durum deposu, filtrelenmiş snapshot, servis yetkileri, RLS ve CAS
- [x] Masa listesi/oluşturma/hızlı katılma/hazır/ayrılma/rövanş
- [x] Sunucuda bot, timeout, disconnect, snapshot ile yeniden bağlanma
- [x] Ortak cüzdan, tekil ödeme/iade/hediye, ayrı rating/istatistik/geçmiş
- [x] Üretim oyun girişi, animasyon adaptörü, avatar ve sonuç/ödül gösterimi
- [x] Arkadaş daveti, FCM v1 dalı, sohbet/ses/hediye, seyirci erişimi kodu
- [x] Web admin inceleme/ayar/kapatma ve audit
- [x] Yerel güvenlik/ekonomi, kısa landscape, Dart analiz ve Android derlemesi
- [x] Yerel iki oturumlu HTTP + PostgreSQL tam maç testi ve yayın yönergesi
- [x] Mevcut production Supabase Gateway/Auth/Realtime/cron kurulum doğrulaması
- [ ] Fiziksel cihazda Storage ses kaydı ve bildirim teslimatı
- [ ] İki fiziksel cihazda tam maç, reconnect, mikrofon ve FCM/APNs teslimatı
- [ ] iOS derlemesi ve cihazda pil/arka plan kontrolü
- [x] Üretim kurulum onayı alındı; 31 Ekim 2026 tarihinde mevcut projeye kuruldu

Canlı migration/Edge/admin deploy ve özellik açma için sonraki mesajlarda
onay alındı. Mağaza yayını yapılmadı.

## Yerel doğrulama — 31 Ekim 2026

- Pişti + seçilen Okey regresyon grubu: **80 test geçti**.
- Üretim menü girişi: **1 test geçti**. Kural/ayrılma diyalogları da
  568×280, 640×320 ve 960×320 boyutlarında kontrol edildi.
- Backend: SQL migration/regresyon/RLS/hediye/ses/iade kontrolleri ve
  iki oturumlu HTTP tam maç, duplicate hamle, bot, timeout, disconnect ve
  eşzamanlı son koltuk testleri geçti. Beraberlikte ek el testi ayrıca geçti.
- Seyirci erişimi arkadaşlık veya mevcut Genel Seyirci Geçişiyle sınırlandı;
  geçiş satın alma mevcut cüzdan kaydına atomik ve tekrar güvenli bağlandı.
  Seyirci yazılı sohbeti de aynı yetkiyle çalışır.
- Yeni Pişti Dart kaynaklarında analiz temiz. Ortak eski dosyalarda mevcut
  deprecated/lint bildirimleri Pişti çalışması kapsamında topluca değiştirilmedi.
- Ana `lib/main.dart` ile Android debug APK ve web admin Next.js build geçti.
- Edge TypeScript girişlerinin sözdizimi kontrolü geçti. Sonraki kurulum
  onayıyla gerçek Supabase Edge deploy ve iki JWT ile tam maç da doğrulandı.

## Değişiklik sınırı

Yeni uygulama: `lib/cards`, `lib/screens/pisti_*`, `lib/services/pisti_service.dart`.
Onaylanan `lib/dev/pisti` sahnesi çevrimiçi projeksiyonla tekrar kullanılıyor;
yerel demo fixture'ları debug girişinde kaldı. Lobi resume/davet ve push
yönlendirmesi oyun türünü ayırır. Profil menüsünden ayrı Pişti kariyeri açılır.

Backend: `supabase/functions/pisti`, Pişti migration'ları `...000200`–`...000400`,
davet göndericisinin Piştiye özel FCM v1 dalı. Okey kural/dağıtım/ödül
fonksiyonları değişmedi. Ortak `table_players` üzerinde yalnızca eşzamanlı
Pişti/Okey üyeliğini engelleyen ek trigger var. Bu nedenle staging'de mevcut
Okey masa oluşturma/katılma tetikleyicileriyle birlikte doğrulanmalı.

Web admin: `../okeyix_web/src/app/api/admin/pisti/route.js`, `PistiScreen.js`
ve mevcut admin navigasyonu. Gizli el/deste admine de gönderilmiyor.

Bu çalışma öncesindeki Okey, reengagement, pubspec ve demo varlık değişiklikleri
korundu; başka işler için commit/reset yapılmadı.

## Erişilemeyen doğrulamalar

Yeni staging oluşturulmadı. Kullanıcı onayıyla mevcut production projede
Auth/Gateway/Realtime/pg_net/cron, arkadaş daveti ve tam maç doğrulandı.
İki fiziksel cihaz, mikrofon/Storage ses akışı, FCM/APNs teslimatı ve iOS
pil/arka plan kontrolü yapılmış gibi sunulmuyor.
Web projesinin yerel `.env.local` dosyasında yalnızca Supabase URL/anon
değişkenleri var; admin RPC'leri için gereken `SUPABASE_SERVICE_ROLE_KEY`
yerelde tanımlı değil. Değer istenmedi, üretilmedi veya istemciye yazılmadı.
Mevcut Vercel production ortamında bu sunucu secret'ı zaten bulunuyordu;
korundu ve Pişti admin arayüzü yayınlandı.

[Kurallar](pisti_rules.md) · [Hedef şema ön kontrolü](pisti_preflight.sql) ·
[Kurulum, iki hesapla oynama ve geri dönüş](pisti_release.md).

[Canlı kurulum ve doğrulama sonucu](pisti_production_status_20261031.md).
