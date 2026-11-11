# Pişti production kurulumu — 31 Ekim 2026

## Güncel ürün: Pişti Molası

Anlık puan düzeltmesi: Pişti Edge’i önce git dışında
`.dart_tool/pisti-score-backup/` altına indirildi, ardından yalnızca public
snapshot’a `score` gösterim alanı eklenerek mevcut projeye yayımlandı.
`total`, maç bitirme koşulu, sonuç kayıtları ve ekonomi değişmedi.
İstemci anlık `score` değerini, eski sunucuda `total` değerini kullanır.
Normal Pişti, valeyle Pişti, kart puanları, el devri/çift sayım ve iki oyuncunun
ekran eşlemesi için 11 sunucu + 1 Flutter testi geçti. Açık Chrome’a hot reload yapıldı.

`20261031000200_pisti_break.sql` mevcut `esqpgtedmojrzoftchis` projesine uygulandı.
Öncesinde aktif Pişti masası bulunmadığı doğrulandı; beş fonksiyonun ve constraint’lerin
önceki tanımları git dışı `break-before-20261031.json` dosyasına kaydedildi.
Secret, Vault, Edge ve admin kurulumu korundu; cron ve özellik açık kaldı.
Yeni masalar sunucuda ücretsiz/özel/seyircisizdir; eski kayıtlar silinmedi.

İki izole gerçek JWT hesabıyla arkadaş daveti, kabul, 144 hamlelik tam maç
(14–104), 147 Realtime olayı, duplicate hamle, iki onaylı rövanş,
aktif maça dönüş, otomatik bot, bot rövanşı ve çıkış doğrulandı.
Başlangıç/son coin 0, Okey rating 1200 kaldı; Pişti kariyer veya maç cüzdan
kaydı oluşmadı. Test hesapları işlem sonunda devre dışı bırakıldı; sonuçlar korundu.
Rapor git dışı `.dart_tool/pisti-install/break-live-verification.json` içindedir.

Yerel SQL: sıfır bakiye, zorunlu gizlilik, mevcut insan arkadaş filtresi,
normal sonuç puanları, iptal/hükmen sonuç, rövanş ve eski ücretli masanın
giriş/ödül sözleşmesinin korunması geçti. Flutter masa/bağlantı/kart hareketi
grubu 15, yeni gezinme/menü grubu 3, landscape görsel grubu 4 test geçti.
Aktif masa JSONB filtresinin gerçek HTTP istek biçimini sınayan ek test de geçti.
Android debug APK derlendi ve açık emülatöre veri silmeden yüklendi. Okey
açılışı ve 2–2–1 düzeni ekranda görüldü. Son emülatör turunda Android ANR
uyarısı ve makinede yüksek bellek baskısı görüldüğünden son APK üzerinde bot
maçını elle oynama kontrolü tamamlanmış sayılmıyor. Bot/arkadaş/rövanş/yeniden
bağlanma sunucuda ve ilgili widget testlerinde ayrıca doğrulandı. Ek analiz
süreci bellek açmak için durduruldu; önceki kapsamlı analizde derleme hatası yoktu.
JSONB üyelik filtresi düzeltildi; bu düzeltme Pişti girişini ve Okey açılışında
aktif Pişti maçına dönüşü kapsar. Okey’in mevcut 2–2–1 lig düzeni korundu.

Güncel akış ve geri dönüş: [pisti_release.md](pisti_release.md).
Aşağıdaki bölüm önceki kurulumun tarihsel kaydıdır.

Kullanıcının migration/secret/Vault/Edge/cron/admin kurulum ve etkinleştirme
onayıyla mevcut **okeyix-prod / esqpgtedmojrzoftchis** projesine kuruldu.
Yeni staging projesi oluşturulmadı; mağazaya sürüm gönderilmedi.

## Kurulanlar

- Migration sırası: `20261030000200_pisti.sql`,
  `20261030000300_pisti_social_worker.sql`, `20261030000400_pisti_admin.sql`.
- `PISTI_WORKER_SECRET` Edge'e, aynı değer `okeyix_pisti_worker_secret`
  adıyla Vault'a kaydedildi. Vault proje URL'si `okeyix_pisti_project_url`.
  Değerler gösterilmedi veya git'e yazılmadı.
- `pisti` Edge **v1 ACTIVE**, `verify_jwt=false`; işleyici oyuncu JWT'sini
  `auth.getUser` ile, worker'ı ayrı secret ile doğruluyor.
- `send_table_invite_push` Edge **v15 ACTIVE**, `verify_jwt=true`.
  Canlı v13 kaynak esas alındı; Okey başlık/metin/veri, token fallback,
  tercihler, Android kanal/ses ve APNs badge/alert davranışı korundu.
  Piştiye özel JWT/üyelik/davet expiry/claim ve oyun yönlendirmesi eklendi.
  İki dal da FCM v1; Legacy FCM ve `FCM_SERVER_KEY` yok.
- `okeyix-pisti-tick`: **job 19**, `1 second`, **active=true**.
  Pişti **enabled=true**. Varsayılan hedef101, giriş1000/5000/10000,
  hamle20sn, bağlantı90sn, timeout limiti3.
- Mevcut Vercel admin sunucu secret'ları zaten tanımlıydı ve korundu.
  Hosted `SUPABASE_URL` değerinin aynı onaylı proje ref'ine ait olduğu
  doğrulandı; kontrol için açılan geçici ortam dosyası silindi.
  Pişti admin ekranı `https://www.okeyix.com/admin/dashboard` altında yayında.
  Deployment: `https://okeyix-nto14dxxl-elnevoapp-5384s-projects.vercel.app`.

## Doğrulananlar

- Önce salt okunur preflight, ilgili fonksiyon/trigger/policy/cron ve canlı
  Edge kaynağı yedeği alındı. Sonrasında mevcut public Okey fonksiyonlarının
  tanımlarında **0 değişiklik** doğrulandı.
- Yalnızca davet uyumluluğuyla ilgili **5 kontrol geçti**:
  v13 Okey FCM istek/cevap eşitliği, fallback/tercih/OPTIONS,
  Pişti oyun payload'ı, sahte gönderen/expiry/claim ve JWT/istemci route ayrımı.
  Testin v13 fixture'ı canlıdan alınan kaynak; secret içermiyor.
- Gerçek Vault→pg_net→Edge worker çağrısı **HTTP 200**, timeout yok.
  Cron çalışma kayıtları `succeeded`.
- Gizli durum Realtime'a yayınlanmıyor; `authenticated` rolünün özel state
  SELECT ve `okeyix_pisti_load` EXECUTE yetkisi yok.
- İki ayrı gerçek Auth/JWT test hesabı arkadaş davetiyle aynı özel masaya
  katıldı, hazır oldu ve **288 hamlede 101–95 tam maç** tamamladı.
  **291** yetkili Realtime masa olayı alındı.
- Gerçek snapshot'larda rakip eli ve deste yok. Tekrar hamle aynı receipt'i
  döndürdü; bitişten sonra tekrar da ödülü çoğaltmadı.
- Cüzdan: iki kez **−1000 giriş**, bir kez **+2000 ödül**; toplam korundu.
  Her iki hesabın Okey rating'i aynı kaldı.
- Okey davet Edge'i gerçek JWT ile, legacy anahtar gerektirmeden çalıştı.
  Pişti davet Edge'i geçerli daveti kabul etti, farklı gönderen JWT'sini
  reddetti. Test hesaplarında cihaz token'ı yoktu; gerçek kullanıcıya push
  gönderilmedi. FCM payload'ı ve istemcinin Okey/Pişti route ayrımı test edildi;
  fiziksel bildirim gösterimi/tıklaması yapıldı diye raporlanmıyor.
- Admin login **HTTP 200**; oturumsuz Pişti admin API **HTTP 401**.
  Hosted Next.js build ve production alias yayını başarılı.
- Test masası kapalı, iki test Auth hesabı ve public kullanıcı kaydı engelli.
  Test maç/cüzdan geçmişi korundu. Geçici şifreli test erişim dosyaları silindi.

## Cihazda kontrol

Pişti kodunu içeren güncel uygulamayı kullanın; yerel Android debug APK
`build/app/outputs/flutter-apk/app-debug.apk`. **Lobi → Menü → Pişti · İki kişilik**.
Bir hesap masa oluşturur, diğeri listeden veya arkadaş davetinden katılır;
iki taraf **Hazırım** der. Boş masada **Botla oyna** seçeneği de var.
Mağazadaki eski uygulama Pişti girişini içermeyebilir; mağaza yayını yapılmadı.

Fiziksel Android/iOS cihazda bildirim gösterimi ve dokununca doğru ekran,
mikrofon/sesli mesaj, uygulamayı arka plana atıp dönüş ve pil davranışı
kullanıcının cihazında kontrol edilmelidir. Bunlar sunucu/API testleriyle
doğrulanmış sayılmıyor.

## Geri dönüş kaydı

Git dışı `.dart_tool/pisti-install/`: preflight, önceki tanımlar, canlı v13
Edge kaynağı, deployment bilgileri, migration hash'leri ve doğrulama raporları.
Önceki admin production deployment:
`https://okeyix-obv7vyn1o-elnevoapp-5384s-projects.vercel.app`.
Özelliği kapatın; aktif Pişti masalarını admin **Kapat / İade** ile sonlandırın,
sonra job19'u kapatın. İhtiyaçta yedek v13 Edge ve önceki admin deployment'a
dönülebilir. Muhasebe ve maç tablolarını silmeyin.

Uygulanan migration SHA-256:

| Migration | SHA-256 |
|---|---|
| 20261030000200 | CE1E96021B2CB1FB18587B18F9EEAB46CAEA299BFA72EFBFA0B6E0EE6040798B |
| 20261030000300 | 60A9E0694086E041AE80A65740D77752A1BFB3C890547330A4CFA2E7CA205F89 |
| 20261030000400 | C695706D7A383EA84BA68E12C10E0A4F43814020C518ADF036BC2728DA373AC3 |

Migration kaynakları hash korunması için değiştirilmedi; başlangıçtaki
`NOT APPLIED` yorumları tarihsel taslak yorumlarıdır. Güncel durum bu kayıttır.
