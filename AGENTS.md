# Okeyix UI/UX kuralları

- Okeyix, landscape-first bir Flutter mobil oyunudur.
- Okeyix lobi ekranındaki beş lig kartı landscape kullanımda her zaman 2–2–1 düzeninde gösterilir. İlk iki satırda ikişer lig, üçüncü satırda tam genişlikte Şampiyonlar bulunur. Küçük ekranlarda tek sütuna düşülmez ve ligler için dikey kaydırma kullanılmaz.
- Yeni veya değiştirilen tüm ekranlar, diyaloglar, popup'lar, bottom sheet'ler, menüler, ödül ekranları ve oyun içi paneller yatay kullanım için tasarlanmalıdır.
- Portrait telefon tasarımını varsayılan kabul etme.
- Kullanılabilir ekran yüksekliği, tüm UI çalışmalarında temel kısıtlardan biridir.
- Küçük landscape ekranlarda içerikler kesilmemeli ve aksiyon butonları ekran dışında kalmamalıdır.
- Genişliğin fazla olması, yüksekliğin yeterli olduğu anlamına gelmez.
- Gerekli durumlarda iki sütunlu veya yatay kompozisyonları tercih et.
- Responsive tasarım için LayoutBuilder, MediaQuery, SafeArea, Flexible ve Expanded gibi Flutter araçlarını uygun şekilde kullan.
- Kaydırma gerekiyorsa yalnızca ilgili içerik bölümünü kaydır; temel aksiyonları mümkün olduğunca görünür tut.
- Yeni UI geliştirmelerinde landscape taşma kontrollerini zorunlu kabul et.
- Mevcut oyun mantığını ve işlevleri koru.
- Bütün yeni veya değiştirilen arayüzler, SaaS/dashboard modal estetiği yerine Okeyix'in oyun masasına, lobi atmosferine ve mevcut görsel varlıklarına uyumlu oyun arayüzleri olarak tasarlanmalıdır.
- Ödül ekranlarını standart form kartları olarak değil; belirgin ödül objesi, katmanlı sahne, tutarlı aydınlatma ve oyun kimliğiyle uyumlu aksiyonlarla oluştur. Landscape kompozisyonunu ve kısa ekran yüksekliğini tasarımın başlangıç noktası kabul et.
