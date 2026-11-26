# Hediye görselleri v2

Onaylanan çay örneği esas alınarak 16 katalog görseli, yerleşik Imagegen aracıyla mevcut PNG'ler düzenlenerek yenilendi. Objelerin kimliği, ana renkleri, aksesuarları ve ifadeleri korundu. Üretim istemleri ve kaynak yolları `output/gift-refresh-v2/manifest.json` içinde tutulur.

Uygulama varlıkları aynı `assets/images/hediyeler/<id>.png` yollarını kullanır. Çayın reddedilen Canvas prototipi kaldırıldı; katalog, avatar yanı ve Flame uçuşu aynı onaylanan PNG'yi kullanır. Hediye kimlikleri, fiyatlar, sunucu ve ödeme mantığı değişmez.

`tool/install_gift_refresh.dart` tüm görselleri önce doğrular, ardından 512×512 RGBA PNG olarak kaydeder. Alfa korunur, palet/renk azaltma uygulanmaz. İlk kurulumdaki orijinaller `.dart_tool/gift-refresh-v2/originals` altında saklanır. Boyut raporu `output/gift-refresh-v2/verification.json`, toplu önizleme `output/gift-refresh-v2/preview.png` dosyasındadır.

Bu değişiklik uygulama ile paketlenir; kullanıcıların yeni görselleri görmesi için uygulamanın yeni derlemesini kullanması gerekir. Supabase'e görsel yüklenmez.

Son 16 dosya toplam 4.618.261 bayttır. Tüm katalog PNG'leri Flutter codec ile 512×512 ve şeffaf köşe olarak doğrulandı. İlgili testlerde 11 test geçti; önceden de bulunan iki hata sürüyor: emekli `hediye_paketi.png` dosyası eksik, seyirci testinin beklediği hediye konumu mevcut uygulamayla uyuşmuyor. 480×270 ve 844×390 yatay ekran satın alma/uçuş testleri geçti.
