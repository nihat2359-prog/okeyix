# Aşama 4B — yalnız gözlem

Motor durdurulmadı; FPS, dt, sorgu, animasyon süresi ve oyun kuralı değiştirilmedi. Kullanım aynı: debug/profile için `--dart-define=OKEYIX_ACTIVITY_PROBE=true`. Varsayılan kapalı; release'te probe ve efekt gözlemci çocukları oluşturulmaz. Gözlem açıkken alınan CPU profili, aracın kendi maliyetini de içerir.

## Merkezi bildirim

GameActivityProbe.notifyWake(GameWakeReason), sınırlı enum sayaçları ve wakeRevision üretir. Gerçek motor çağrısı, stream yayını, widget rebuild veya sürekli log yoktur. Snapshot debugger üzerinden `game.activityProbe?.snapshot()` ile alınır. Pointer down/up/cancel/move, rota/lifecycle görünürlüğü, resize, efekt kuyruğu/tamamlanma/iptal, yaşam döngüsü ve ağ işlem giriş/çıkışları bu noktaya bağlanır. Bildirim bir değişiklik adayıdır; aynı veri tekrar geldiğinde de oluşabilir.

## Efekt yaşam döngüsü

observeGameEffect, orijinal Effect nesnesini aynen döndürür. Mevcut MoveEffect tür kontrolleri, parent/target, controller, süre, eğri ve removeOnFinish değişmez. onComplete önceki callback'i aynı anda çağırır; finally yalnız gözlem kaydını kapatır. Async void callback'in Future'ı beklenmez; böylece orijinal Flame semantiği korunur.

Efekt constructor'ından sonra ve parent'a eklenmeden önce kaydedilir. Gecikmeli veya henüz mount edilmemiş efekt de açık kalır. Küçük gözlemci çocuk onMount bildirimi yapar ve onRemove sırasında hâlâ açık kayıt varsa iptal sayar. Tamamlanmış kayıt ikinci kez kapatılmaz. Parent kaldırılması da iptali kapatır; test edilmiştir. Sequence ve iç efektler ayrı kaydedilir, gözlemci child Sequence controller listesine eklenmez. Kısa efektlerin tamamlanması örneklemeye bağlı değildir.

Bu kayıt **kuyruğa alınma–tamamlanma/iptal aralığıdır**. Controller.startDelay sonrası ilk gerçek hareketin onStart anı ayrıca ölçülmez. effectMounted hareket başladı anlamına gelmez. Başlamadan iptal de bu aralığa dahildir. Yanlış idle üretmemek için süreyi geniş tutar.

OkeyGame.dart içindeki 12, TileComponent içindeki 5, Stage içindeki 4 mevcut Effect constructor noktası bağlandı: dağıtma, otomatik atma/geri dönüş, gösterge bonusu sequence'i, uzak oyuncu hareketleri, slot düzeltme, taş kaldırma vurgusu ve ıstaka butonları. Bunlar aynı nesneyi döndüren gözlem sarmalayıcılarıdır. Aşama 4A'nın 100 ms sınırlı taraması, sarmalanmamış efektleri denetlemek için korunur; her kare tam tarama yapılmaz.

## Bekleyen iş ve bileşenler

_handleMove, _handleTableUpdate, _pollLiveTableState, _syncDiscardTopsFromServer ve _checkAuthoritativeHandIntegrity Future'ları gözlem açıkken try/finally işlem sayacına bağlanır. Asıl metot gövdeleri ve sorgular korunur. Probe kapalıyken doğrudan gövde çağrılır. Dönen Future tamamlanmadan kayıt kapanmaz; hatada da kapanır.

World, TileComponent ve RackActionButton doğrudan child ekleme/kaldırma bildirimleri verir. Tüm ağacın her pending ekleme talebini olay anında kapsadığı iddia edilmez. Mevcut hasLifecycleEvents, kaldırma kuyruğu, network/action/stateSync/UI-lock/el-bütünlüğü bayrakları örnekleme sırasında ayrıca dikkate alınır. Açık efekt veya açık işlem varken quiet sınıfına geçilmez. Aktif kayıtlar 2.048 ile sınırlıdır; taşma unknown durumunu kalıcı olarak işaretler. Kayıt hiç mount olmadan kaybolursa açık kalabilir: bu eksik ölçümün güvenli yönde bloklamasıdır. Oyun kapanışında kayıtlar temizlenir.

## Kesin olmayan alanlar / motor durdurulmadan önce gerekenler

1. Snapshot coverageComplete=false ve confirmedIdleMeasured=false kalır. confirmedIdleMicroseconds=0 ölçüm yok anlamındadır. Bu altyapı motoru uyutma kararı vermez.
2. Özel update/render animasyonları (_InvalidFinishFx gibi), bütün doğrudan position/visibility/sprite atamaları, kamera mutasyonları ve bağımsız Flutter efektleri eksiksiz enstrümante edilmedi.
3. SpectatorGame'in efekt constructor'ları bu aşamada değiştirilmedi. Onun için ayrı host/probe kapsamı gerekli.
4. Beş işlem kapsamı bütün RPC, storage ve gecikmeli Future/Timer işlerini temsil etmez. Özellikle async onComplete içindeki RPC, efekt callback'inin dönmesiyle tamamlanmış sayılamaz. Mevcut action/UI-lock bayrakları korunsa da tam bir işlem envanteri gerekir.
5. Tekrar reset edilen veya dışarıdan onComplete'i sonradan değiştirilen efektlerde yeni yaşam döngüsü güvenilir sayılmaz. Mevcut bağlanan noktalarda böyle bir kullanım bulunmadı; ileride merkezi factory/sözleşme ve denetim gerekir. Yeni efektler sarmalanmazsa denetim örneklemesi kısa ömürlü olanı kaçırabilir.
6. Görünürlük route/TickerMode/app lifecycle temellidir; kısmi örtülme ve bütün platform görünürlükleri kapsanmaz. Geri dönüşte sunucu uzlaştırması bitmeden idle kararı verilemez.
7. Bağımsız 320 ms temizleme ile Flame efekti zamanı ve onComplete içindeki taş atma RPC'si, motor durdurulmasında hâlâ kritik risklerdir. Değiştirilmediler.

## Testler

Yeni otomatik testler: kısa atma-benzeri efektte aynı nesne/tür/pozisyon ve callback sırası; parent kaldırılarak uzak hareket iptali; nested Sequence move+scale tamamlanması; mount bekleyen efekt/ağ Future'ının açık kalması; hata sonrası işlem temizliği ve dispose sonrası bildirimlerin etkisizliği. Bunlar gerçek Supabase'li otomatik atma veya iki cihaz testi değildir. Önceki pointer/sürükleme sınıflandırması, route çıkış/geri dönüş, görsel eşitlik ve animasyon testleri regresyon olarak çalıştırılır.

İlgili test grubu 32 test geçti. Gerçek cihazda CPU/GPU, input gecikmesi, pil veya iki oyuncu senkronizasyonu ölçülmedi. Üretimde olay bazlı render için henüz güvenli onay verilemez; önce eksik kapsamların kapatılması ve iki cihazlı profile testleri gerekir.
