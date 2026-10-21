# İki gerçek okey stratejisi

İki gerçek okeyli elde, henüz çiftli moda geçilmemişse ve kapalı taş varsa,
bot normal bitişi erteleyip okey atarak bitiş hedefler. Hemen geçerli okey
atabiliyorsa bitişi yapar. Hazırlık sırasında iki okeyi korur ve atış adaylarını
bir okey atıldıktan sonra kalacak 13 taşın tamamlanma potansiyeline göre seçer.
Sahte okeyler bu koşula dahil değildir. Çiftli mod ve tek okeyli eller korunur.
Deste tükendiğinde mevcut normal bitiş kabul edilir.

Bu tercih hazır normal galibiyetten vazgeçme riski taşır; daha yüksek kazanma
oranı iddiası değildir. Kullanıcının istediği okey atma stratejisidir.
`findFinish` hukuki bitiş sorgusu olarak tüm geçerli planları bulmaya devam eder;
yalnızca oyun kararlarında normal bitişin ertelenmesi uygulanır.

Değişiklikler `lib/game/bot/bot_engine.dart` ve `test/bot_engine_test.dart`.
Oyun RPC'leri, ekonomi, taş dağıtımı, kayıt sistemi ve migration değişmedi.
