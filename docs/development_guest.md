# Sabit geliştirme misafiri

VS Code launch ayarları, Git'e alınmayan `.vscode/dev-guest.local.json` dosyasını
`--dart-define-from-file` ile yükler. Bu dosyada kişiye özel rastgele
`OKEYIX_DEV_GUEST_KEY` bulunur. Anahtarı paylaşmayın veya Git'e eklemeyin.

Yalnız web debug modunda Misafir Oyna bu sabit kimlikle mevcut giriş/kayıt akışını kullanır.
Chrome profili, port veya yerel site verisi değişse bile aynı hesap bulunur.
İlk kullanım yeni geliştirme misafirini oluşturur; eski hesapları birleştirmez.
Android/iOS telefonlar debug dahil her zaman kendi normal kurulum kimliğini
kullanır. Profil ve release modları da her zaman normal kimliği kullanır.

VS Code'dan uygulamayı tamamen durdurup yeniden başlatın; hot reload derleme
parametrelerini değiştirmez. Terminal alternatifi:

```powershell
flutter run -d chrome --web-port=7357 --dart-define-from-file=.vscode/dev-guest.local.json
```

Komutu her seferinde yazmamak için `powershell -File tool/run_chrome.ps1`
kullanılabilir. VS Code genel `dart.flutterAdditionalArgs` ayarı da aynı dosyayı
yükler. Chrome debug'da anahtar yüklenmediyse giriş durdurulur; tarayıcıya bağlı
rastgele misafir kimliğine sessiz geçiş ve yeni hesap oluşturma yapılmaz.

Dosyayı silmek yeni anahtar ve farklı test hesabı gerektirir. Başka geliştirici
kendi yerel dosyasını şu komutla oluşturabilir (mevcut dosyayı ezmez):

```powershell
if (!(Test-Path .vscode/dev-guest.local.json)) {
  @{ OKEYIX_DEV_GUEST_KEY = [guid]::NewGuid().ToString('N') } |
    ConvertTo-Json | Set-Content .vscode/dev-guest.local.json -Encoding UTF8
}
```
