# Başlangıçta takılan masaların kurtarılması

Kurulum dosyası: `supabase/migrations/20261028000500_stale_start_recovery.sql`.
Henüz canlı sunucuya uygulanmış değildir. Önce staging üzerinde mevcut gerçek
`leave_table` ve watchdog işlevleriyle doğrulayın; ardından Supabase SQL Editor'da
postgres olarak migration dosyasının tamamını çalıştırın. Yeni iOS sürümü gerekmez.

Koruma mevcut `public.run_okey_watchdog()` zamanlamasını kullanır; yeni cron işi
eklemez. Her `start`/`starting` girişinin zamanını sunucuda ayrı kaydeder. Masa
oluşturulma zamanı başlangıç zamanı olarak kullanılmaz. Kurulumdaki mevcut
masalara da tam 2 dakikalık süre tanınır.

Masa en az 2 dakikadır başlangıçta bekliyorsa ve bir insan oyuncunun
`profiles.last_seen_at` değeri en az 2 dakika eskiyse, mevcut `leave_table`
çağrısıyla ayrılması sağlanır. Uygulama kapatılırken online işareti açık kalmış
olabilir; karar yalnızca bu işarete bağlı değildir. Eksilen masa, çıkış işlevi
tarafından silinmemişse `waiting` durumuna döner ve `ready_since` temizlenir.
Kalan oyuncunun koltuk numarası değiştirilmez.

Yeni başlangıçlar, güncel bağlantısı olan insanlar, botlar, `playing` masalar
ve herhangi bir oyuncusuna taş dağıtılmış masalar bu yoldan temizlenmez.
Bağlantı zamanı bilinmeyen oyuncu için tahminle çıkarma yapılmaz. Her çalışmada
en fazla 50 aday kontrol edilir; kilitli masalar atlanır. Tek masa hatası kendi
işlemlerini geri alır, diğer masaları ve mevcut watchdog işlerini durdurmaz.
Hatalar sunucu logunda `START_RECOVERY_FAILED` olarak görünür.

Bu kontrol uygulamanın genel bağlantı sinyalini kullanır. Oyuncu lobide veya başka
bir ekranda uygulamayı kullanmayı sürdürüyorsa güncel genel bağlantı bilgisi onu
masadan çıkarmak için yeterli kanıt sağlamaz. Bu ayrı senaryo için masa bazında
bağlantı sinyali gerekir. Ayrıca aktif oyunculu bir masada `start_game` sunucu
hatası yaşanıyorsa bu migration oyuncuyu çıkarmak veya zorla oyun başlatmak
yerine masayı korur.

## Doğrulama

Yerel sentetik PostgreSQL testleri:

```powershell
$env:START_RECOVERY_LOCAL_PG='1'
node --test test/start_recovery_test.mjs
```

Test çalıştırıcısı yalnızca `127.0.0.1:55449` üzerindeki PostgreSQL'e bağlanır;
kendisine ait geçici test veritabanını oluşturur ve sonunda kaldırır.
Testler migration'ın gerçek SQL'ini çalıştırır. Mevcut oyun sunucusunun
`leave_table` ve watchdog kaynakları sentetik sözleşme karşılıklarıdır;
canlı kaynaklarla uyumluluk staging'de ayrıca doğrulanmalıdır.

Staging'de bot + insan ile dolmuş, henüz taş dağıtılmamış masayı oluşturun.
İnsan uygulamayı kapattıktan ve her iki süre eşiği dolduktan sonra bir sonraki
watchdog turunda koltuğun temizlendiğini ve kalan masanın beklemeye döndüğünü
kontrol edin. Güncel bağlantılı oyuncuyla aynı denemede koltuk korunmalıdır.
Mevcut çıkış akışının ücret/iade ve istatistik davranışını da karşılaştırın.

Kurulum kontrolü (salt okunur):

```sql
select to_regprocedure('okeyix_start_private.recover()') as recovery_function;
select position('okeyix_start_private.recover()' in prosrc)>0 as watchdog_connected
from pg_proc where oid='public.run_okey_watchdog()'::regprocedure;
select t.id,t.status,s.entered_at
from okeyix_start_private.pending s
join public.tables t on t.id=s.table_id
order by s.entered_at;
```
