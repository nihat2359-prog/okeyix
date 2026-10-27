# Rak yerleşme hareketi

- Rak içi hareket ve önizleme dönüşü: 180 ms easeOutCubic; hedef aşımı yok.
- Aynı hedefe tekrarlanan çağrı devam eden hareketi yeniden başlatmaz.
- Dolu slota eklemede slot sahipliği hemen güncellenir; yalnızca görsel hareket eder.
- Önizleme temizliği ve iptal dönüşü slota ışınlanmak yerine aynı hareketi kullanır.
- Aynı slotu doğrulayan el güncellemesi devam eden doğru hedefli hareketi kesmez.
- Ortadan/diskarttan çekilen gerçek taş, geçici görselin son konumunda oluşturulur.
  Geçici yüz aynı karede gizlenir. Geçici görsel yoksa mevcut kaynak konumu kullanılır.
- İlk dağıtımın 220 ms süresi ve taş başına 25 ms gecikmesi korunur.
- Hareket sırasında yeni taşıma başlayınca eski hareket durdurulabilir.
- Oyun kuralları, sunucu RPC'leri ve para işlemleri değişmedi; yeni ağ sorgusu yok.

58 ilgili test geçti: monoton hareket, tekrar hedefleme, sunucu güncellemesi,
çekme önizlemesi devri, dolu satırlar, fiziksel taş/slot sayısı, ilk dağıtım,
çift tık ve yaşam döngüsü. Canlı Chrome/telefon kare süresi ölçümü yapılmadı.
