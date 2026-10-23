# Hediye kataloğu güncellemesi

Yeni seçim sırası:

Çay → Kahve → **Emzik → Soğuk Su → Sigara** → Pasta → Kırmızı Gül → Limon →
Acı Biber → Şans Yıldızı → Nazar Boncuğu → Şans Nalı → Taç → Yüzük →
Dört Yapraklı Yonca → Saat.

Üç yeni hediye kullanıcı tercihiyle **250 coin**. Mevcut diğer hediyelerin
fiyatları değiştirilmez; SQL testi paylaşılan gerçek fiyatları esas alır.

Hediye Paketi yeni seçimlerden çıkarıldı. Eski satın alma kayıtları ve
avatarların mevcut hediyeleri yabancı anahtarlarla bağlı olduğu için kayıt
silinmedi; `enabled=false` olur. Eski PNG ve istemci geçmiş kayıt desteği korunur.

Panelin üstündeki alıcı ve bakiye satırları kaldırıldı. Satın almanın alıcı
kimliği, sunucu bakiye kontrolü, atomik ödeme, canlı güncellemeler, hediye uçuşu
ve seyirci yetkileri korunur. Bakiye yalnızca görünümden çıkarıldı.

## Görseller

Yeni AI üretimi, şeffaf alfa kanallı 512×512 PNG varlıkları:

- `assets/images/hediyeler/emzik.png`: altın detaylı turkuaz/beyaz emzik.
- `assets/images/hediyeler/soguk_su.png`: buzlu, yoğuşma damlalı kristal su bardağı.
- `assets/images/hediyeler/sigara.png`: kristal küllük üzerinde markasız sigara.

Mevcut Çay/Kahve varlıklarının gerçekçi malzeme, altın ışık ve üç boyutlu
ürün sunumu referans alındı. Yüksek çözünürlüklü üretimler alfa korunarak mevcut
PNG'lerle aynı tuval boyutuna indirildi. Ek paket veya asset dizini eklenmedi.

## Kaynak dosyalar

- `lib/models/table_gift.dart`: 16 seçilebilir kimlik + geçmiş için Hediye Paketi.
- `lib/services/table_gift_service.dart`: eski sunucudan gelse bile Hediye Paketi'ni
  seçimden çıkarır; yeni üç hediyeyi kahveden sonra sıralar. Fiyatlar sunucudan gelir.
- `lib/ui/table_gift_layer.dart`: alıcı/bakiye satırları kaldırıldı.
- `supabase/migrations/20261023000100_table_gift_catalog_refresh.sql`: yalnızca katalog verisi.
- `test/table_gifts_test.dart`: varlıklar, sıralama, eski kayıtlar ve panel kontrolleri.
- `test/sql/gift_catalog_fixture.sql`, `gift_catalog_assertions.sql` ve
  `tool/test_gift_catalog.ps1`: izole yerel PostgreSQL testi.

## Doğrulama

- `flutter test --no-pub test/table_gifts_test.dart`: **12 test başarılı**.
- PNG'ler Flutter codec ile çözüldü: 512×512, köşe alfa değeri 0.
- 480×270 ve 844×390 yatay ekranlarda panel/satın alma ve hediye konumu testleri geçti.
- `tool/test_gift_catalog.ps1`: migration iki kez uygulanarak fiyat koruma,
  16 seçenek, kesin sıra, 250 coin yeni fiyatlar ve tarihçe bütünlüğü doğrulandı.
- Test çıktıları `.dart_tool/gift_catalog_final_tests.log` ve
  `.dart_tool/gift_catalog_sql_tests.log` dosyalarında.

## Dağıtım

**Canlı Supabase'e uygulanmadı.** Önce staging'de
`20261023000100_table_gift_catalog_refresh.sql` çalıştırılmalı.
Mevcut `20261021000200_table_gifts.sql` tekrar çalıştırılmaz.

Yeni uygulama/assets ile katalog SQL'i birlikte planlanmalı. Eski sürümlerde
hediye kimlikleri sabit bir izin listesiyle okunuyor; yeni kimlikleri tanımayan
eski istemcilerin hediye ekranı yüklenmeyebilir. Desteklenen istemciler
güncellendikten sonra katalog yeni kimliklerle etkinleştirilmeli.

Yeni satırlar sunucuya eklenmeden istemci bunları sahte yerel fiyatla sunmaz.
Migration oyun/ödeme RPC'lerini, yetkileri veya başka tabloları değiştirmez.
