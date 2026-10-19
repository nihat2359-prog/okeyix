# Pil optimizasyonu, aşama 3

## Statik inceleme

- `OkeyGame.update()` önce Flame bileşen ağacını güncelliyor; ertelenmiş taş kaldırma kuyruğu boşsa hemen dönüyor. Boş durumda burada liste kopyası oluşturulmuyor. Oyun döngüsünü durdurmak güvenli bir yerel optimizasyon değil; değiştirilmedi.
- Flame 1.35.1 `GameLoop`, Flutter Ticker üzerinden her animasyon karesinde çalışıyor. `FlameGame` update/render ağacını işlemeye devam ediyor. Uygulama genelinde FPS veya döngü değişikliği yapılmadı.
- SDK `pauseWhenBackgrounded` varsayılanı true; paused/hidden/detached durumunda durduruyor, resumed/inactive durumunda kendi durdurduğu motoru sürdürüyor. Bu davranış değiştirilmedi. Üstüne başka bir rota açılması uygulamanın arka plana geçmesiyle aynı şey değil; otomatik durdurma varsayılmamalı.
- `GameWidget.addRepaintBoundary` SDK varsayılanı true. Mevcut ekran bunu kapatmıyor. Ek bir sınırın Flame'in kendi sürekli çizimini durduracağı varsayılmadı; widget katmanı değiştirilmedi.
- `TileSurfaceFx` her karede iki Paint ve iki gradient shader; `PreviewComponent` dört Paint ve iki shader; atma yuvasının `_PremiumDiscardFrame` dekoru beş Paint ve iki shader oluşturuyordu. Aynı boyutta çizim komutları değişmiyor.
- `RackActionButton.render` her karede metin ölçümü, `ClosedPileComponent.render` dört arka yüz çerçevesinin Paint/shader hazırlığını tekrarlıyor. Bunlar bu küçük uygulama kapsamının dışında bırakıldı; sonraki adaylar.
- Sinematik taş/ıstaka efektleri `ThemeFlags` içinde kapalı. `_InvalidFinishFx` 0,9 saniyelik, kendini kaldıran geri bildirim; sürekli dekorasyon olarak değerlendirilmedi ve korunuyor.

## Uygulanan değişiklik

Üç sabit dekor `CachedDecoration` ile yerel çizim komutlarını `ui.Picture` içinde boyut değişene kadar saklıyor. Bu bir bitmap/texture önbelleği değil. GPU aynı görseli her karede çizmeye devam eder; azaltılan iş Dart tarafında komut, geometri, Paint ve shader hazırlığıdır. İlk karede ek kayıt maliyeti ve bileşen başına tutulan Picture belleği vardır.

Konum, ölçek ve efektler kayıt dışında Flame tarafından uygulanır. Çocukların update/render geçişi, görünürlük, sürükleme olayları ve oyun mantığı değişmez. Boyut vektörünün yerinde değiştirilmesi de önbelleği yeniler. Eski Picture boyut değişiminde ve onRemove sırasında dispose edilir. Bu mixin değişken renk/tema/zaman/etkileşim içeren çizimlerde kullanılmamalıdır.

## Doğrulama

`flutter test --no-pub test/game_decoration_cache_test.dart test/game_ui_pulse_test.dart test/game_view_data_source_test.dart`: 22 test geçti.

Yeni dört test: 600 aynı boyutlu çizimde tek kayıt, boyut/removal sonrası yenileme; taş yüzeyi ve önizleme için iki boyutta 1,75 ölçekli RGBA eşitliği; gizli önizlemenin boş çıktı vermesi ve tekrar görünmesi; gerçek FlameGame içinde MoveEffect devamlılığı.

Bu ölçüm 600 render çağrısını bire indirgemek anlamına gelmez: 600 render/drawPicture çağrısı devam eder, sabit dekorun hazırlığı bir kez yapılır. CPU/GPU zamanı, bellek ve pil farkı ölçülmedi.

Sadece değişen Dart dosyaları analiz edildi. Yeni dosyalardaki gereksiz import kaldırıldı; tile_component.dart içindeki mevcut kullanılmayan import/yardımcılar ve deprecated withOpacity bildirimleri kapsam dışı bırakıldı.

## Gerçek cihaz doğrulaması

Android/iOS profile sürümünde aynı masada sabit bekleme, sürükleme/bırakma, çekme/atma, dağıtma, sıra değişimi, zaman aşımı ve ekran çıkış/geri dönüşünü karşılaştırın. İki fiziksel cihaz senkronizasyonu ayrıca gerekli; otomatik testler gerçek sunuculu oyun akışı kapsamıyor.

DevTools CPU allocation profilinde Paint/shader hazırlığını, UI/raster frame sürelerini ve Picture belleğinin tekrar giriş/çıkışlarda birikmediğini kontrol edin. Aynı cihaz/parlaklık/ağ koşullarında sabit süreli pil testi yapın. FPS sınırlama, durağan sahnede motor durdurma ve render mimarisi değişiklikleri bu aşamada uygulanmadı.
