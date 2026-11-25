# Lobi mağaza bağlantıları

## Cross-promo

`CrossPromoService` gerçek HTTP mağaza sonuçlarını platform başına uygulama
oturumu boyunca önbelleğe alır. Boş/yanlış kimlikler, kapalı test sayfaları,
istek hataları, CORS hataları ve belirsiz yanıtlar listeye alınmaz. Masaüstü web
iOS kataloğunu kontrol eder; iOS/Android cihazlar kendi mağazasını kontrol eder.
Webde mağaza CORS izni vermediğinde oyunlar gizlenir; tarayıcı güvenliği aşılmaz.

Kullanıcı tarafından sağlanan iOS kimlikleri:

| Oyun | Bundle ID | Apple ID |
| --- | --- | --- |
| Okix | com.okeyix.okix | 6838298677 |
| Kartix | com.okeyix.kartix | 6837629065 |
| Sirenix | com.okeyix.sirenix | 6836349354 |

Android paket adları kullanıcı tarafından iOS bundle kimlikleriyle aynı olarak
doğrulandı: `com.okeyix.okix`, `com.okeyix.kartix`, `com.okeyix.sirenix`.
Yalnızca herkese açık Google Play kontrolünden geçen oyunlar gösterilir.
`OKIX_ANDROID_PACKAGE`, `KARTIX_ANDROID_PACKAGE`, `SIRENIX_ANDROID_PACKAGE`
dart-define değerleriyle girilebilir. iOS değerleri de `*_IOS_BUNDLE` ve
`*_IOS_APP_ID` üzerinden değiştirilebilir.

## Ödülü etkinleştirme

Hazırlanan `20261124140000_cross_promo_rewards.sql` migration'ı **henüz uzak
veritabanına uygulanmadı**. Mevcut tablo, oturum, günlük ödül ve satın alma
akışlarının API'lerini değiştirmez. İki yeni tablo ve bir RPC ekler.

Migration incelemesinden sonra yayımlanan her oyunun ilgili platformu sunucuda
da etkinleştirilmelidir. `cross_promo_catalog` yalnızca yönetici tarafından
değiştirilebilir. Örnek (yalnızca gerçekten yayında olduğu doğrulandıysa):

```sql
update public.cross_promo_catalog
set ios_enabled = true
where game_id = 'okix' and ios_bundle = 'com.okeyix.okix';
```

Android için gerçek `android_package` ve `android_enabled` birlikte girilir.
Kapalı testteki oyunlar etkinleştirilmez. Yayından kaldırılan oyunlar sunucuda da
kapatılmalıdır. Migration hazır olmadan istemci ödül verildiğini göstermez.

Mağaza bağlantısı başarıyla açıldıktan sonra kimliği doğrulanmış RPC, sabit
5.000 çipi atomik olarak `profiles.coins` ve `wallet_transactions` içine yazar.
`(user_id, game_id)` tekilliği cihaz değişikliğinde ve eşzamanlı isteklerde de
tekrar krediyi önler. SharedPreferences kullanıcı/oyun bazında yerel önbellektir;
sunucu kaydının yerini almaz. İndirme veya kurulum doğrulaması yapılmaz; kullanıcının
istediği gibi mağaza bağlantısının açılması ödül tetikleyicisidir.
