# Masa sohbeti katılım olayları

Durum: uygulama ve SQL hazır; canlı Supabase kurulumu henüz yapılmadı.

## Kurulum

SQL Editor'da postgres olarak `supabase/migrations/20261027000500_table_chat_membership.sql` dosyasını çalıştırın. Günlük ödül değişikliklerinden bağımsızdır. Ardından güncel Flutter uygulamasını yeniden açın. Kurulum tekrar çalıştırılabilir; bilinmeyen mesaj politikası varsa durur. Kilit/SQL hatasında işlem bütünüyle geri alınır.

Canlı şema çıktısında mesaj RLS'si kapalıydı ve politika yoktu. Kurulum RLS'yi açar: authenticated kullanıcının okuması kendi masa üyeliği ve başlangıcıyla sınırlanır. Gönderim kendi kimliği, doğru oyuncu/izleyici rolü ve açık sohbet gerektirir. İstemci sistem olayı üretemez veya mesaj saatini belirleyemez. Oyun/coin fonksiyonları ve mevcut katılım tetikleyicileri değiştirilmez.

## Davranış

Gerçek oyuncu/izleyici üyelik ekleme ve silme işlemi mevcut mesaj tablosuna kalıcı olay ekler. Avatar ve isim olay anında saklanır. İki ekran aynı satırı kullanır: katılım yeşil, ayrılma kırmızı; izleyicide “izlemeye başladı / izlemekten ayrıldı”. Olaylar avatar konuşma balonu veya ses oluşturmaz. Eski istemciler olayın düz metnini normal mesaj olarak görebilir.

Bağlantı yenilenmesi/idempotent spectator upsert, el, hazır olma ve joined_at güncellemeleri yeni olay veya erişim başlangıcı oluşturmaz. Üyelik gerçekten silinip yeniden eklenirse yeni ziyaret başlar; önceki ziyaretin mesajları görünmez. İzleme ekranını kapatma mevcut uygulamada üyeliği siler; yeniden giriş bu nedenle yeni ziyarettir. Üyeliği koruyan bağlantı kesintisi geçmişi sıfırlamaz.

Kurulum sırasında zaten masada olanlar mevcut joined_at başlangıcını korur; sahte katılım mesajı oluşturulmaz. Eski mesajlar silinmez/değiştirilmez. Kurulum öncesi giriş/çıkışlar geriye dönük üretilemez. Yeni sürekli okuma sorgusu veya animasyon eklenmez; mevcut Realtime ve kurtarma akışı kullanılır.

## Doğrulama

Yerel PostgreSQL 16'da canlı çıktının alan/FK/yayın sözleşmesiyle ayrı test DB'sinde ilk ve tekrar kurulum; oyuncu/izleyici giriş/çıkış; aynı üyelikle yeniden bağlanma; el güncellemesi; kimlik/sistem olayı taklidi; istemci saati; eski geçmiş; dışarıdan/ayrıldıktan sonra erişim; yeniden ziyaret; masa değiştirme; özel şemaya erişim; sohbet/izleyici kapatma; metin/sesli gönderim ve masa silme testleri geçti. Yayındaki açık kolon listesine metadata'nın dahil edilmesi kontrol edildi. Canlı oyun tetikleyicilerinin gövdeleri yerel fixture'a kopyalanmadı; Supabase Realtime dağıtımı yerelde test edilmedi.

Flutter olay görünümü, sohbet senkronizasyonu ve panel testlerinde toplam 41 test geçti. İki ekranın analizinde derleme hatası yok; mevcut lint uyarıları var.

Kurulum sonrası iki oyuncu ve bir izleyiciyle her iki panelde canlı mesaj, katılım ve ayrılmayı kontrol edin. Sonradan gelen izleyici eski yazışmaları görmemeli; yeni mesajı ve gerçek göndereni görmeli. Yerel test başarısı canlı dağıtımın doğrulandığı anlamına gelmez.