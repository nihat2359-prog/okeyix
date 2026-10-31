# Pişti kart yüzleri

2–10 kartlarının sembol yerleşimleri standart iki uçlu iskambil düzenindedir.
Alt yarıdaki semboller 180° döner; köşe değerleri ve küçük semboller birbirine
ters yönlüdür. As ortada tek büyük sembol kullanır. J/Q/K, büyük harfli soyut
tasarım yerine klasik, renkli ve çift yönlü insan figürleri kullanır.

Figür kaynağı: [SVG-cards — David Bellot / Huub de Beer](https://github.com/htdebeer/SVG-cards).
Lisans: **LGPL-2.1**, ücretsiz kullanım; yeni Flutter paketi eklenmedi.

- `assets/images/pisti_cards/svg-cards.svg`: indirilen değiştirilmemiş kaynak.
- `LICENSE.txt`: tam lisans; `AUTHORS.txt`: kaynak yazar kaydı.
- `club/diamond/heart/spade_jack/queen/king.svg`: gerekli SVG bağımlılıklarıyla
  ayrılmış 12 figür. Tümünde viewBox `27 10 115 224` ile orta figür kırpıldı;
  Flutter SVG'nin desteklemediği metin düğümleri çıkarıldı. Köşe indeksleri
  mevcut Montserrat ile Flutter tarafından çizilir. Figürlerin çizimleri değişmedi.
- Küçük ve büyük sayısal semboller Dart Canvas ile çizilir; raster atlas yok.

İndirme adresleri: deponun `master/svg-cards.svg`, `master/LICENSE`,
`master/AUTHORS` dosyaları. Asıl kaynak ve lisanslar uygulama varlıkları içinde
saklanır; türetilmiş SVG'ler de aynı lisans kapsamındadır.

Kontrol: `flutter test test/pisti_cards_test.dart`.
`PISTI_CAPTURE_CARDS=1` ile test 52 kartlık inceleme görselini
`build/pisti_demo_captures/standard_52_cards.png` yoluna yazar.
