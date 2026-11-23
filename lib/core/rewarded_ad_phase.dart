enum RewardedAdPhase {
  preparing('Reklam hazırlanıyor…', 'Video için bağlantı kuruluyor. Lütfen bekle.'),
  loading('Video yükleniyor…', 'Günlük hediyen için video hazırlanıyor.'),
  opening('Video açılıyor…', 'Ödülü kazanmak için videoyu tamamla.'),
  verifying('Ödül doğrulanıyor…', 'Videon tamamlandı. Coinlerin için onay bekleniyor.');

  const RewardedAdPhase(this.label, this.message);
  final String label;
  final String message;
}
