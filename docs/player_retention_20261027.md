# Oyuncu adı hatırlatması ve 7 günlük hediyeler

## Kurulum sırası

Canlıya henüz uygulanmadı. Flutter sürümünden önce SQL Editor'da postgres ile:

1. `supabase/migrations/20261027000100_seven_day_rewards.sql`
2. `supabase/migrations/20261027000200_unique_player_names.sql`
3. Yeni Flutter sürümünü yayınla.

İkinci dosya, mevcut adlarda büyük/küçük harf ve baş/son boşluk farkıyla
çakışma varsa açık hata ile durur; hesapları yeniden adlandırmaz veya silmez.
Çakışmaları salt okunur görmek için:

```sql
SELECT lower(btrim(username)) AS name_key,count(*) AS accounts
FROM public.users WHERE nullif(btrim(username),'') IS NOT NULL
GROUP BY lower(btrim(username)) HAVING count(*)>1;
```

## Oyuncu adı

İlk tamamlanmış oyundan sonra (users galibiyet/mağlubiyet sayılarıyla kontrol),
adı hâlâ `Oyuncu_` ile başlayan oyuncuya lobide hatırlatma gösterilir. Mevcut
hesaplar da uygunsa görür. İlk avatar seçimi ve oyuna giriş engellenmez.
Adımı seç mevcut profil düzenleyicisini, isim alanına odaklanıp mevcut adı
seçerek açar. Mevcut ücretsiz ilk değişim ve sonraki değişim maliyeti korunur.

Daha sonra yalnızca mevcut paneli kapatır; sonraki lobi ziyaretinde tekrar
gösterilebilir. Günlük ve oturumluk erteleme engeli yoktur. Açık panel varken
ikinci panel açılmaz. Bir daha gösterme hesap kimliğiyle cihaz/tarayıcı tercihlerinde
kalıcı tutulur; uygulama verisi silinirse veya başka cihazda yeniden sorulabilir.
Gerçek ad istenmez. Sunucu users tablosundaki adları normalize edilmiş benzersiz
indeksle korur. Eski hesaplar otomatik değiştirilmez.

Adımı seç ile editörü açıp otomatik adı değiştirmeden kapatınca da panel hemen
tekrar açılmaz; sonraki lobi ziyaretinde yeniden uygundur. Bir daha gösterme
her durumda önceliklidir. Eski günlük gösterim kayıtları artık dikkate alınmaz;
eski kalıcı Bir daha gösterme tercihi korunur.

## Yedi günlük ödül

| Gün | Coin |
| --- | ---: |
| 1 | 2.500 |
| 2 | 3.000 |
| 3 | 3.500 |
| 4 | 4.000 |
| 5 | 4.500 |
| 6 | 5.000 |
| 7 | 7.500 |

Toplam 30.000 Coin. İlk gün mevcut 2.500 korunur. Tutar istemciden alınmaz.
İlerleme sunucuda özel tabloda saklanır; gün kaçırınca sıfırlanmaz. Yedinci
ödülden sonra ilk güne döner. Günde bir ödül, Europe/Istanbul sunucu tarihiyle
belirlenir. Ödeme makbuzu, bakiye ve ilerleme aynı işlemde yazılır.

Eski `claim_daily_bonus(uuid,integer,text)` değiştirilmez: eski sürüm 2.500
almaya devam eder. İki sürüm aynı günlük benzersiz makbuz anahtarını kullanır;
aynı gün iki ödül alamaz. Eski sürümle alınan ödül yedi günlük ilerlemeyi artırmaz.
Yeni RPC henüz yoksa uygulama eski akışı kullanır; ağ/yetki hatalarında buna
sessizce geçmez ve tahmini ödül göstermez.

Panel mevcut ödül sahnesini, sandık görsellerini, sesleri ve Coin aktarımını
kullanır. İlk günler küçük ödül objeleri, 7. gün büyük sandık gösterilir.
Başarı bildirimi yalnızca sunucu onayından sonra gelir. Sonraki gün için dönüş
mesajı gösterilir. Bildirimler uygulama içidir; işletim sistemi push bildirimi
eklenmedi. Panel otomatik günde bir kez açılır; kapatan oyuncu menüdeki Günlük
Hediyeler'den yeniden ulaşır. Oyun rotasının üstünde açılmaz.

## Doğrulama

Yerel PostgreSQL 16'da minimal sözleşme fixture'ı ile iki migration uygulandı.
8 günlük döngü, ara verilen gün, yinelenen istek, eski/yeni sürüm günlük ortak
sınırı, bakiye, eksik profilde tam rollback, anonim erişim, özel tablo erişimi
ve büyük/küçük harf/boşlukla ad çakışması test edildi. Ayrıca 8 eş zamanlı yeni
istemci ve 8 karışık eski/yeni istemci isteğinde hesap başına tek ödeme doğrulandı.
Fixture canlıdaki diğer trigger ve politikaları kapsamaz; canlı sistem testi yapılmadı.

Yerel dosyalar: `test/sql/retention_fixture.sql`, `test/sql/retention_test.sql`,
`test/sql/retention_concurrency.ps1`. Fixture yalnızca `okeyix_retention_test`
adlı yerel test veritabanında çalışır; Supabase'e uygulanmamalıdır.

Flutter testleri: `retention_flows_test`, `daily_bonus_dialog_test`,
`reward_landscape_test`, `profile_editor_scene_test`, `lobby_side_menu_test`.
İki mevcut profil golden testi hariç 77 test geçti; yeni iki panelin görselleri
de oluşturulup incelendi. Hedefli analizde derleme/tip hatası yok; mevcut
dosyalardaki kullanılmayan kod/deprecation uyarıları devam ediyor.
568×320 ve 844×390 boyutlarında büyük yazı dahil yeni panel kontrolleri var.
İki mevcut profil golden testi aynı oranlarda değişiklik öncesi HEAD koduyla da
başarısız oldu (%92,72 ve %65,29); eski golden dosyaları değiştirilmedi.
