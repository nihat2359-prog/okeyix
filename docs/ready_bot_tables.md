# Hazır bot masaları — kurulum

003 numaralı migration zaten çalıştırıldı. Tekrar çalıştırmayın.
SQL Editor'da yalnızca `supabase/migrations/20261023000400_ready_bot_fixed_owner.sql`
dosyasının tamamını çalıştırın.

Masa sahibi: `c1788536-38fa-407a-8fdc-02bf4d94d3c1`.
SQL, hesabın auth.users içinde bulunduğunu kontrol eder; hesap bilgilerini,
coin, rating, bot veya çevrimiçi durumunu değiştirmez. Yeni hesap gerekmez.
Eski activate_ready_bot_tables.sql ve hesap oluşturma aracını kullanmayın.

Sonuçta aktif=true ve lig_basina_hedef=3 görünür. Mevcut dakikalık watchdog,
uygun boşta bot varsa Acemiler, Çıraklar ve Kalfalar'daki katılınabilir
masaları lig başına toplam üçe tamamlar. Uygun gerçek oyuncu masaları da
bu hedefe dahildir. Ustalar ve Şampiyonlar'da otomatik masa açılmaz.

Masa oluşmazsa şu salt okunur raporu paylaşın:

```sql
SELECT public.run_standard_bot_table_maintainer(3,false);
```

Durdurmak için:

```sql
UPDATE okeyix_ready_private.policy SET enabled=false WHERE singleton;
```

004 dosyası canlıya buradan uygulanmadı; bu ek migration için PostgreSQL
çalıştırma testi yapılmadı.
