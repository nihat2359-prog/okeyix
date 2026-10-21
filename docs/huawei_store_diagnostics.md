# Huawei mağaza açılış teşhisi

Tasarım, ürün sorgusu ve satın alma işlemleri değiştirilmedi. Debug derlemelerinde
loglar açık; profile/release için teşhis derlemesine şu parametre eklenmeli:

```powershell
flutter run --release --dart-define=OKEYIX_STORE_TRACE=true -d CIHAZ_ID
```

Mevcut Google Play sürümünde bu loglar yoktur. Yeni teşhis derlemesi gerekir.
Bu ayar olmadan normal release derlemesinde loglar kapalıdır.

Uygulamayı açmadan önce bağlı bilgisayarda:

```powershell
adb logcat -v time | Select-String 'STORE_TRACE|AndroidRuntime|E/flutter|F/libc|E/libEGL|E/Adreno|E/Vulkan|E/Impeller'
```

Lobiden mağazaya bir kez basın, siyah ekranda yaklaşık 10 saniye bekleyin ve
geri dönün. Bu aralığın STORE_TRACE satırlarını, stack satırları dahil paylaşın.
Varsa aynı aralıktaki native grafik/AndroidRuntime hatalarını da ekleyin.

## Aşamalar

- `navigation_request`, `route_push_begin`, `route_builder`: giriş ve rota kurulması.
- `create_state_begin/complete`: state alanları, Supabase ve IAP instance erişimi.
- `init_state_begin`, `product_query_begin`, `purchase_listener_begin`,
  `init_state_complete`: başlangıç akışı. Ürün sorgusu async olduğu için
  `product_query_complete` ilk frame'den önce veya sonra gelebilir.
- `store_build`, `scene_layout`, `offer_layout_0..3`: ekran ve dört kartın ölçüleri.
- `artwork_resolve_0..3`, `artwork_loaded_0..3`: asset çözümleme ve decode.
- `scene_paint_begin/complete`, `artwork_paint_0..3`: Dart paint aşaması.
- `first_post_frame`: framework frame callback'i.
- `frame_timing_after_store_paint`: paint sonrasındaki engine frame timing'i.
- `framework_error`, `uncaught_async_error`, `route_error`, `create_state_error`,
  `scene_paint_error`, `artwork_asset_error_*`: exception ve stack.
- `store_dispose`, `navigation_return`: çıkış.

`scene_paint_complete` ve frame timing logu fiziksel ekranda doğru görüntü
olduğunu kanıtlamaz. Bu aşamalar tamamlanıp ekran siyah kalıyorsa native
GPU/renderer logları gerekir. Paint altındaki framework hataları ayrıca
`framework_error` olarak raporlanabilir; tüm hata satırları birlikte incelenmeli.

Loglar kullanıcı ID'si, bakiye, ürün yanıtı veya satın alma makbuzu eklemez.
Framework/async hataları mağaza açıkken yakalanır; bu aralıkta başka bir özelliğin
hatası da raporlanabilir. Önceki hata handler'ları çağrılır, hatalar yutulmaz.
