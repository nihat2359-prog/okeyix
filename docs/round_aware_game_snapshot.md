# Eksik raund bilgisi nedeniyle elin yeniden dağıtılması

Canlı logda `get_full_table_state` yanıtlarının `table.round_count` alanı yoktu.
Yeni el mevcut raund numarasıyla çiziliyor; sonraki `tables` sorgusu gerçek yeni
raundu görünce `_pollLiveTableState` eli temizliyordu. Paylaşılan logdaki
`hand_applied` (35), `playing / serverRound: 2` (37) ve `hand_clear` (40) sırası
bu durumu gösteriyor. Önceki sentetik yanıtlar round_count içerdiği için testler
bu sunucu sözleşmesi farkını kapsamıyordu.

## Kurulum

1. Supabase SQL Editor'da `20261028000700_round_aware_game_snapshot.sql` dosyasının
   tamamını postgres olarak çalıştırın.
2. Chrome'da uygulamayı Stop → Run ile yeniden başlatın. iOS için yeni derleme gerekir.

Yeni `okeyix_full_table_state(uuid)` işlevi mevcut el/oyuncu sorgusunu kullanır.
Masa satırına okuma kilidi alarak durum, raund ve sıra bilgilerini aynı işlemde
yanıta ekler. Çağıranın masada oturması zorunludur. Deste, el, ücret, ödül veya
oyun süresinde değişiklik yapmaz. Eski get_full_table_state işlevi değiştirilmez.

İstemci yeni işlev yoksa eski işlevi deneyebilir; fakat raund numarası olmayan
bir eli tahmin ederek göstermez. Böyle bir kurulumda konsola
`GAME_SNAPSHOT_ROUND_MISSING` yazar ve hazırlık ekranında kalır; SQL kurulmalıdır.

`playing` durumuna geçmek tek başına hazırlık panelini kapatmaz. Panel ve sayaç
elin yerleşmesini bekler; sunucunun gerçek oyun süresi değiştirilmez.

## Doğrulama

```sql
select to_regprocedure('public.okeyix_full_table_state(uuid)') is not null
  as round_aware_snapshot_installed;
```

Yeni debug loglarının `build` alanı `round-aware-snapshot-2` olur.
`full_snapshot` olayında `serverRound` dolu olmalıdır. `elapsedMs` ilk eldeki
beklemenin yanıt gelmeden önce mi, çizim sırasında mı olduğunu ayırmaya yardımcıdır.
Önceki loglarda zaman bilgisi bulunmadığından ilk eldeki üç saniyenin tamamını
yalnızca eksik raund alanına bağlayamayız.

Yerel SQL testi eski işlevin raund numarası döndürmediği durumu kurar; yeni yanıtın
doğru raundu taşıdığını, ellerin değişmediğini ve masada olmayan hesapların
erişemediğini doğrular. Flutter regresyonu eksik numaralı elin önce eski raunda
dağıtılmasını ve sonraki periyodik sorgunun yeni eli silmesini kontrol eder.
