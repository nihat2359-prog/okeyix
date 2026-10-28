# Kapalı desteden sürüklerken taş hazırlama

Önce `supabase/migrations/20261028000600_prepare_closed_draw.sql` dosyasını
Supabase SQL Editor'da çalıştırın. Ardından güncel uygulamayı Chrome'da Hot Restart
ile başlatın; iOS için yeni derleme gerekir.

Sürükleme başlangıcında `okeyix_prepare_closed_draw` yalnızca mevcut sıradaki
oyuncunun sıradaki kapalı taşını okur. El, deste, süre ve bakiye değiştirilmez.
Sürükleme sırasında taşın yüzü gizli kalır. Rak dışına bırakılırsa hazırlık
geçersizleşir ve `game_draw` çağrılmaz.

Raka bırakıldığında hazırlık geldiyse taş yüzü hemen gösterilir. Hazırlık henüz
gelmediyse gelene kadar bekleme görseli kalır; ön okuma her ağ koşulunda anında
gösterimi garanti etmez. Gerçek çekme `game_draw` ile bırakma anında yapılır.
Sunucu onayına kadar hazırlanan yüz kilitli bir görseldir, oynanabilir elin üyesi
değildir. Son karar sunucudan gelen eldir; ret durumunda geçici yüz kaldırılır
ve el sunucudan yeniden eşitlenir.

Raund/sıra/masa değişimi veya yeni sürükleme eski hazırlığı geçersizleştirir.
Hazırlık işlevi kurulmamışsa veya okuma başarısızsa mevcut çekme akışı devam eder.
Bu bir rezervasyon değildir; veri istemcide alınır ama arayüzde sürüklerken açılmaz.

Doğrulama: 49 Flutter görsel/çekme regresyon testi ve yerel PostgreSQL üzerinde
yetki, sıra kontrolü ve el/destede değişiklik olmaması testleri geçti.
