# Oyun gecikmesini ölçme

Chrome debug çalıştırmasını ölçüm açık şekilde başlatın:

```powershell
flutter run -d chrome --dart-define=OKEYIX_LATENCY_TRACE=true
```

Bu derleme seçeneği değiştiğinde uygulamayı yeniden başlatın. Varsayılan olarak
ölçüm kapalıdır; release derlemesinde etkinleşmez. Ek ağ isteği veya veritabanı
kaydı oluşturmaz, taş/oyuncu bilgisi yazmaz.

Konsoldaki `GAME_LATENCY` satırları işlem başlangıcından itibaren geçen süreyi
milisaniye olarak gösterir:

| İşlem / aşama | Anlamı |
| --- | --- |
| draw / prepared_face_queued | Önceden okunan taş yüzü çizilmek üzere eklendi |
| draw / rpc_response | Asıl çekme isteğinin yanıtı geldi |
| draw / confirmation_received | RPC veya ayrı el okumasıyla çekme doğrulandı |
| draw / hand_render_queued | El görselleri güncellendi ve bekleme görseli kaldırıldı |
| discard / rpc_confirmed | Atma işlemi sunucudan başarılı döndü |
| discard / turn_refreshed | Atma sonrasında sıra sorgusu tamamlandı |

`queued` aşamaları ekrandaki gerçek ilk çizim süresi değildir. RPC süresi ağ ve
sunucu işlemini birlikte içerir; bu ölçüm tek başına veritabanı kilit süresini
ayırmaz. Ayrı el okuması çekmeyi daha erken doğrularsa RPC satırı sonradan gelebilir.

Sayaç katmanında sunucudan gelen sıra bilgisi, profil/avatar bilgilerinden önce
çizilir. Aynı koltuğa dönen yeni sıra da güncellenir; eski zaman veya raund bilgisi
yeni sayacı geri alamaz. Profil ve kullanıcı okumaları paraleldir; mevcut ortak
önbellek ve istek birleştirme davranışı korunur.

Doğrulama senaryoları: geciken profil yanıtları sırasında sayacın yenilenmesi,
kaçırılmış ara hamleden sonra aynı koltuğa dönen sıra, eski sorgu yanıtı,
raund geçişi, reddedilen çekme/atma ve bağlantı yenilenmesi.

Bu değişiklik için yeni SQL kurulumu gerekmez. Chrome'da güncel kodu yeniden
başlatın; iOS'ta değişikliklerin yer aldığı yeni derlemeyi kullanın.
