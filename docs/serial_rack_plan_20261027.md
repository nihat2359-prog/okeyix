# Seri dizme — 27 Ekim 2026

İlk dağıtım ve Seri Diz aynı yerel planlayıcıyı kullanır. Önceki yöntem gerçek
okeyleri per seçiminden çıkarıyor ve kalan ikili grupları boşluksuz birleştiriyordu.

Yeni `serial_rack_plan.dart` fiziksel taş indeksleriyle çalışır. Renk serilerini
ve farklı renkli sayı perlerini, gerçek okey alternatifleri dahil üretir. Önbellekli
alt küme araması toplam per içindeki taş sayısını en büyük yapar; eşitlikte uzun
perleri tercih eder. Mevcut 12-13-1 sarma kuralı korunur. Tam perler görsel üst
sıraya, kalan renk komşuları ve sayı ikilileri aralarında boşlukla alt sıraya
yerleşir. Yer yetmediğinde diğer sıra kullanılır; son güvenlik geçişi her fiziksel
taşa benzersiz, geçerli bir slot atar.

Tekli taşlar alt sıranın en sağında tek ve boşluksuz bir blok oluşturur. Bu alan
önceden ayrılır; her tekli taş için boşluk harcanıp 13 gibi tek bir taşın gereksiz
yere üst sıraya taşınması önlenir. İkinci ekran görüntüsündeki el regresyon testidir.

Sunucu işlemleri, bitiş doğrulaması ve Çift Diz değiştirilmedi. Plan yalnızca
ilk dağıtımda veya Seri Diz istendiğinde hesaplanır; her karede çalışmaz.

Doğrulama: seri planlayıcı, gecikme, dolu slota ekleme ve yaşam döngüsü
paketlerinde toplam 45 test geçti. Kullanıcının 15 taşlık örneği, okeyli set,
yarışan perler, aynı taşın iki fiziksel kopyası, sarma kuralı ve 150 rastgele
elde benzersiz slot/taş koruması kontrol edildi. Canlı Chrome görsel testi yapılmadı.
