# Okeyix iki kişilik Pişti — v1

Kaynaklar: [Pagat / John McLeod](https://www.pagat.com/fishing/pishti.html),
[Oyun Kütüphanesi](https://www.oyunkutuphanesi.com/oyun/pisti).
30 Ekim 2026 tarihinde karşılaştırıldı. İki kişilik, takımsız, hedef 101
varyantı seçildi. Hedef masa açılırken merkezî ayardan sabitlenir.

52 kart karıştırılır. İlk dağıtan rastgele, sonraki ellerde dönüşümlüdür.
Ortaya üç kapalı ve bir açık kart, oyunculara dörder kart gelir. Başlangıç
valeleri ortaya konan dört kartın altına döndürülür; dördü de valeyse yeniden
karıştırılır. Dağıtmayan başlar. Eller boşaldıkça dörder kart dağıtılır; altı
dağıtımda deste biter. Kesme/açık deste altı gösterimi bu dijital varyantta yoktur.

Üsttekiyle aynı değer veya vale ortayı alır. Tek kartı eş değerle almak 10,
tek valeyi valeyle almak 20 Pişti puanıdır. Vale ile farklı tek kartı toplamak
Pişti değildir. İlk ve son oynanan kart Pişti yapmaz; son süpürme de yapmaz.
As/vale 1, sinek 2 iki, karo 10 üç; kart çoğunluğu 3 puandır. 26–26 kartta
çoğunluk bonusu yoktur. Son orta son toplayana, hiç toplama yoksa dağıtana gider.
Hedef el sonunda denetlenir; eşit toplamda bir el daha oynanır.

Pişti Molası botla veya arkadaşla ücretsizdir. Giriş bedeli, coin ödülü ve
rating değişimi yoktur; maç içindeki Pişti puanları ve sonuç geçmişi korunur.
Ayrılma, üç toplam süre aşımı veya 90 saniye heartbeat yokluğu hükmen
yenilgidir. Süreler/limit yeni masalar için admin ayarından değiştirilebilir.
Önceden oluşan ücretli maç ve muhasebe kayıtları korunur.

Sunucu motoru `supabase/functions/pisti/core.mjs` tek kural otoritesidir.
Bot aynı motorun doğruladığı hamleleri, yalnızca kendi eli ve açık orta
üzerinden seçer. Debug demosunun yerel fixture motoru üretimde kullanılmaz.
