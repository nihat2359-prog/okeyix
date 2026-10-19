# Aşama 4A: çizim hazırlığı ve gözlemsel aktivite

## Uygulama

- RackActionButton, kelime başına bir TextPainter tutar; boyut değişirse yeniden ölçer, kaldırılırken dispose eder. Etiket final, stil sabit ve boyuta bağlıdır; mevcut bir çalışma zamanı tema girişi yoktur. Yeni stil/etiket için yeni bileşen kullanılır. Basılı durum, renkler, giriş ve basılma efektleri değiştirilmedi. Boyut değişiminde font ve satır yüksekliği birlikte yenilenir.
- ClosedPileDecoration, dört sprite/çerçeve ve sabit sayaç plakasını Picture içinde saklar. Sayaç TextComponent'i ve oyun etkileşimleri parent üzerinde kalır. Boyut, sprite/image/source rect ve Paint görünüm özellikleri anahtara dahildir. Güncel kodda sabit dekor renkleri tema durumundan okunmaz. Gelecekte tema bağımlılığı eklenirse anahtara da eklenmelidir. Eski Picture yenilemede ve parent onRemove sırasında temizlenir; paylaşılan sprite/image dispose edilmez.
- Aşama 3 CachedDecoration mixin'ine eklenen decorationKey varsayılanı null; önceki üç kullanıcıda davranış değişmez.

## 600 sabit boyutlu çizim

| İş | Önce | Sonra |
|---|---:|---:|
| İki kelimelik bir butonun yardımcı metin ölçümü | 1.200 layout | 2 layout |
| Üç butonun aynı ölçümü (koddan hesap) | 3.600 | 6 |
| Deste dekoru hazırlığı | 600 | 1 |
| Deste Paint oluşturma (18/adım, koddan hesap) | 10.800 | 18 |
| Deste shader oluşturma (9/adım, koddan hesap) | 5.400 | 9 |

Önceki Flame TextPaint kendi çizim paragrafını ayrıca önbellekliyordu; 1.200 sayısı kaldırılan yardımcı ölçümlerdir. Yeni kod aynı TextPainter'ı ölçüm ve çizim için kullanır. Render sayısı azaltılmadı. Sayaç metni Picture'a dahil değil. CPU/GPU süresi veya pil kazancı ölçülmedi.

## Aktivite aracının kullanımı

Varsayılan kapalıdır. Debug veya profile çalıştırmada:

```
flutter run --profile --dart-define=OKEYIX_ACTIVITY_PROBE=true
```

Debug için --profile kaldırılabilir. Release'te define verilse de GameActivityProbe.enabled false'tur; probe oluşturulmaz ve update örnekleme dalı kapalıdır. Pointer listener/observer kurulmaz. Döngü/FPS/pause/step, sorgular, timeout ve coin işlemleri değiştirilmez.

Debugger/DevTools değerlendirme penceresinde mevcut OkeyGame nesnesinin `activityProbe?.snapshot()` sonucunu alın. Otomatik log, sunucuya gönderim veya sınırsız olay listesi yoktur. En fazla 32 olay anahtarı, sabit süre kategorileri ve son örneğin en fazla 2.048 efekt/bileşen gözlemi tutulur. En fazla 100 ms'de bir ağaç örneklenir; etkin araç açıkken her update'te yalnız zaman/örnekleme eşiği kontrol edilir. Aracın kendi maliyeti de cihazda ölçülmelidir.

### Kapsama ve sınırlar

- Pointer down/up/cancel: oyun alanındaki Listener'dan doğrudan sayılır; olay tüketmez. Üst Flutter kontrollerinin tamamını kapsamaz. Up ve cancel ortak sayılır.
- Sürükleme: mevcut aktif taş, kaynak çekme ve drag-overlay durumlarının örneklenmesi. Pointer basılı kaldığında da ihtiyatlı olarak active sınıfı kullanılır.
- Efekt: ağaçta ilk görülen ve artık görünmeyen Effect nesneleri sayılır. İkincisi kesin başarıyla tamamlandı demek değildir; iptal/kaldırma olabilir. İki örnek arasındaki kısa efektler kaçabilir. Gecikmeli veya duraklatılmış efektler de ihtiyatlı olarak active sayılır.
- Dağıtma: mevcut dağıtma bildirim noktasındaki dealRequested ve gözlenen taş efektleri izlenir. Kesin dağıtma başlangıç/bitiş aralığı raporlanmaz.
- Ağ: _handleTableUpdate ve _renderHand girişleri aday olaydır; aynı veri tekrar gelebilir. Değişiklik karşılaştırması eklenmedi. Diğer bütün ağ callback'lerinin görsel etkileri eksiksiz kapsanmaz.
- Bileşen yaşam döngüsü: update öncesindeki hasLifecycleEvents ve ertelenmiş taş kaldırma kuyruğu örneklenir. Her ekleme/kaldırma için kesin olay sayacı değildir.
- Görünürlük: mevcut rota, TickerMode ve uygulama lifecycle bilgisi. Kısmi örtülme, platform penceresi ve her özel popup'ın piksel görünürlüğü garanti edilmez.

Süre kategorileri: active, hidden, unknown, quietUnverified. Bunlar örneklemeye dayalı yaklaşık sınıflardır; kısa geçişlerde en az bir örnekleme aralığı belirsizlik olabilir. Efekt görülürken quiet sınıfı kullanılmaz. Ağaç taraması sınırı aşılırsa unknown kullanılır. Flutter avatar halkası/atmosfer gibi bağımsız çizimler bu Flame sınıflandırmasının dışında kalır.

**Gerçek idle süresi henüz ölçülmüyor.** Snapshot'ta confirmedIdleMeasured=false ve confirmedIdleMicroseconds=0, ölçüm yok anlamındadır; hiç idle olmadığının kanıtı değildir. QuietUnverified, motoru durdurma izni olarak kullanılamaz. Snapshot sadece istenince kopyalanır; release'te dışarıya raporlanmaz.

## Doğrulama ve 4B kararı

Yeni testler metin piksellerini önceki TextPaint çizimiyle; deste piksellerini doğrudan dekor çizimiyle karşılaştırır. Boyut, sprite, tint ve kaldırma sonrası yenileme, 600 kare sayaçları, gerçek Flame rack giriş efekti, aktif/quiet/unknown/hidden ayrımı ve rota kapatma/geri dönme kontrol edilir. Önceki üç aşamanın ilgili 22 testi de regresyon kapsamındadır.

4B için bu araç tek başına güvenli otomatik uyuma koşulu sağlamaz. İlk prototip yalnız izleme modunda olmalı; bütün efekt/dağıtma başlangıç ve bitişleri, pending lifecycle, görsel ağ mutasyonları ve ilk pointer olayları eksiksiz enstrümante edilmelidir. Özellikle onComplete içinden RPC yapan atma ve bağımsız 320 ms temizleme timer'ı çözülmeden pause uygulanmamalıdır. Sonrasında ayrı özellik bayrağı ve iki fiziksel cihaz testleri gerekir. Gerçek cihaz profil/pil ölçümü bu çalışmada yapılmadı.
