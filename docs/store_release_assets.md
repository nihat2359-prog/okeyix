# Store Release Assets

## 1) Uygulama ikonu

Bu projede ikon kaynagi:
- `assets/images/app_icon.png`

Ikonlar otomatik uretildi:
- Android launcher icon
- iOS app icon set

Tekrar uretmek icin:

```bash
flutter pub get
dart run flutter_launcher_icons
```

## 2) Android yayin ekran goruntuleri

Hazir script:
- `tool/capture_store_screenshots.ps1`

Kullanim:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\capture_store_screenshots.ps1
```

Script akisi:
1. Bagli Android cihazi algilar.
2. Her sahne icin sen hazirlarsin.
3. Enter ile o anki ekrani kaydeder.
4. Dosyalari `release/screenshots/android` altina koyar.

Varsayilan cekim listesi:
- `01_login`
- `02_lobby`
- `03_create_table`
- `04_table_list`
- `05_in_game`
- `06_profile`
- `07_store`

## 3) Google Play hizli checklist

- En az 2 telefon ekran goruntusu
- PNG/JPEG
- Kisa kenar: 320-3840 px
- Uzun kenar: 320-3840 px
- En-boy orani: 16:9 - 9:16 araliginda

Not:
- Cihaz bildirim alani ve debug overlay gorunmesin.
- Metinler Turkce karakterlerle net gorunsun.
