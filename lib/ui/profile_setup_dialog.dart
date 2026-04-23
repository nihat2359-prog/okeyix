import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:okeyix/main.dart';
import 'package:okeyix/ui/avatar_preset.dart';
import 'package:okeyix/ui/avatar_selection_screen.dart' hide AvatarPreset;
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> openProfileSetupDialog({
  required bool forceComplete,
  required String initialUsername,
  required String? initialAvatarRef,
  required String currentUserId,
  required int currentCoins,
  required int renameCoinCost,
  required bool freeRenameUsed,
  required Set<String> ownedPremiumAvatarRefs,
}) async {
  final context = navigatorKey.currentContext!;
  if (context == null) return;

  await showDialog(
    context: context,
    barrierDismissible: !forceComplete,
    builder: (_) {
      return ProfileSetupDialog(
        forceComplete: forceComplete,
        initialUsername: initialUsername,
        initialAvatarRef: initialAvatarRef,
        currentUserId: currentUserId,
        currentCoins: currentCoins,
        renameCoinCost: renameCoinCost,
        freeRenameUsed: freeRenameUsed,
        ownedPremiumAvatarRefs: ownedPremiumAvatarRefs,
      );
    },
  );
}

class ProfileSetupDialog extends StatefulWidget {
  final bool forceComplete;
  final String initialUsername;
  final String? initialAvatarRef;
  final String currentUserId;
  final int currentCoins;
  final int renameCoinCost;
  final bool freeRenameUsed;
  final Set<String> ownedPremiumAvatarRefs;

  const ProfileSetupDialog({
    required this.forceComplete,
    required this.initialUsername,
    required this.initialAvatarRef,
    required this.currentUserId,
    required this.currentCoins,
    required this.renameCoinCost,
    required this.freeRenameUsed,
    required this.ownedPremiumAvatarRefs,
  });

  @override
  State<ProfileSetupDialog> createState() => ProfileSetupDialogState();
}

class ProfileSetupDialogState extends State<ProfileSetupDialog> {
  late final TextEditingController usernameController;
  late String selectedAvatarRef;
  late Set<String> ownedPremiumAvatarRefs;
  String? errorText;
  bool _saving = false;

  String get _initialUsername => widget.initialUsername.trim();

  bool get _didUsernameChange =>
      usernameController.text.trim() != _initialUsername;

  AvatarPreset get _selectedPreset => avatarPresetByRef(selectedAvatarRef);

  bool get _isSelectedPremiumLocked =>
      _selectedPreset.isPremium &&
      !ownedPremiumAvatarRefs.contains(_selectedPreset.id);

  bool get _willConsumeFreeRename =>
      _didUsernameChange && !widget.freeRenameUsed;

  int get _renameCoinCostToCharge =>
      (_didUsernameChange && widget.freeRenameUsed) ? widget.renameCoinCost : 0;

  int get _avatarCoinCostToCharge =>
      _isSelectedPremiumLocked ? _selectedPreset.unlockCost : 0;

  Uint8List? selectedAvatarBytes; // 🔥 seçilen foto (preview için)
  bool isCustomAvatarSelected = false; // 🔥 foto seçildi mi
  int customAvatarCost = 15000;
  int get _customAvatarCoinCost =>
      isCustomAvatarSelected ? customAvatarCost : 0;

  int get _computedCoinCost {
    return _renameCoinCostToCharge +
        _avatarCoinCostToCharge +
        _customAvatarCoinCost;
  }

  get FlutterImageCompress => null;

  @override
  void initState() {
    super.initState();
    usernameController = TextEditingController(text: widget.initialUsername);
    selectedAvatarRef = selectedAvatarRef =
        widget.initialAvatarRef ?? "assets/images/avatars/avatar11.png";
    ownedPremiumAvatarRefs = {...widget.ownedPremiumAvatarRefs};

    final initialPreset = avatarPresetByRef(widget.initialAvatarRef);
    if (initialPreset.isPremium) {
      ownedPremiumAvatarRefs.add(initialPreset.id);
    }

    usernameController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    usernameController.dispose();
    super.dispose();
  }

  Future<bool> _isUsernameTaken(String username) async {
    final rows = await Supabase.instance.client
        .from('users')
        .select('id')
        .ilike('username', username)
        .limit(5);
    for (final row in (rows as List)) {
      final id = row['id']?.toString();
      if (id != null && id != widget.currentUserId) {
        return true;
      }
    }
    return false;
  }

  Future<String?> _validateSelectedImage() async {
    if (selectedAvatarBytes == null) return null;

    final bytes = selectedAvatarBytes!;

    // 🔥 1. boyut kontrol (çok küçük)
    if (bytes.length < 5 * 1024) {
      return "Seçilen görsel çok küçük veya geçersiz.";
    }

    // 🔥 3. çözünürlük kontrol (opsiyonel ama iyi)
    try {
      final codec = await instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      if (image.width < 128 || image.height < 128) {
        return "Görsel çözünürlüğü çok düşük.";
      }
    } catch (_) {
      return "Görsel okunamadı.";
    }

    // 🔥 4. SOFT UYARI (her zaman gösterilebilir)
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;

    final username = usernameController.text.trim();

    if (username.isEmpty) {
      setState(() => errorText = 'Kullanıcı adı zorunlu.');
      return;
    }

    final renameCoinSpent = _renameCoinCostToCharge;
    final avatarCoinSpent = _avatarCoinCostToCharge;
    final customAvatarCoinSpent = isCustomAvatarSelected ? customAvatarCost : 0;

    final spentCoins =
        renameCoinSpent + avatarCoinSpent + customAvatarCoinSpent;

    if (spentCoins > widget.currentCoins) {
      setState(() {
        errorText =
            'Yetersiz coin. Gereken: $spentCoins, mevcut: ${widget.currentCoins}.';
      });
      return;
    }

    // 🔥 kullanıcı adı kontrol
    if (_didUsernameChange) {
      setState(() {
        _saving = true;
        errorText = null;
      });

      try {
        final taken = await _isUsernameTaken(username);
        if (taken) {
          setState(() {
            _saving = false;
            errorText = 'Bu kullanıcı adı zaten kullanımda.';
          });
          return;
        }
      } catch (_) {
        setState(() {
          _saving = false;
          errorText = 'Kullanıcı adı kontrol edilemedi.';
        });
        return;
      }

      if (!mounted) return;
      setState(() => _saving = false);
    }

    setState(() => _saving = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;

      String? finalAvatarUrl = selectedAvatarRef;

      // 🔥 CUSTOM AVATAR VARSA UPLOAD
      if (selectedAvatarBytes != null) {
        final path = "avatars/$userId/avatar.jpg";

        try {
          await supabase.storage
              .from('avatars')
              .uploadBinary(
                path,
                selectedAvatarBytes!,
                fileOptions: const FileOptions(upsert: true),
              );
        } catch (e) {
          print("UPLOAD ERROR: $e");
        }

        finalAvatarUrl = Supabase.instance.client.storage
            .from('avatars')
            .getPublicUrl(path);
      }

      // 🔥 PREMIUM UNLOCK
      final unlockedPremium = <String>{};
      if (_isSelectedPremiumLocked) {
        unlockedPremium.add(_selectedPreset.id);
      }

      if (!mounted) return;

      Navigator.pop(
        context,
        ProfileSetupResult(
          username: username,
          avatarRef: finalAvatarUrl,
          renameCoinSpent: renameCoinSpent,
          avatarCoinSpent: avatarCoinSpent + customAvatarCoinSpent,
          consumeFreeRename: _willConsumeFreeRename,
          newUnlockedPremiumAvatarRefs: unlockedPremium,
        ),
      );
    } catch (e) {
      print("SAVE ERROR: $e");
      setState(() {
        _saving = false;
        errorText = "Kayıt sırasında hata oluştu.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    final title = widget.forceComplete
        ? 'Profilini Tamamla'
        : 'Profili Düzenle';

    final viewInsets = MediaQuery.of(context).viewInsets;
    final keyboardOpen = viewInsets.bottom > 0;
    final maxDialogHeight = (size.height - viewInsets.bottom - 16).clamp(
      300.0,
      size.height * 0.94,
    );
    return Dialog(
      backgroundColor: Colors.transparent,
      alignment: keyboardOpen ? Alignment.topCenter : Alignment.center,
      insetPadding: EdgeInsets.fromLTRB(18, keyboardOpen ? 8 : 18, 18, 18),
      child: Container(
        width: isLandscape ? 600 : 520,
        constraints: BoxConstraints(maxHeight: maxDialogHeight),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xEE13291F), Color(0xEE0C1712)],
          ),
          color: const Color(0xFF0F2F2A).withOpacity(0.70),
          border: Border.all(color: const Color(0xD7D0A14A), width: 0.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0xB3000000),
              blurRadius: 28,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: const Color(0x2CECCB79),
                    border: Border.all(color: const Color(0x66E9C46A)),
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: Color(0xFFFFE0A8),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Text(
                        'Kullanıcı bilgilerini ve avatarını güncelle',
                        style: TextStyle(
                          color: Color(0xFFBBD2C4),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!widget.forceComplete)
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0x221A2520),
                      border: Border.all(color: const Color(0x55FFFFFF)),
                    ),
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _usernameSection(),
                  if (!keyboardOpen) ...[
                    const SizedBox(width: 18),
                    Expanded(child: _avatarPanel()),
                  ],
                ],
              ),
            ),
            if (errorText != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  errorText!,
                  style: const TextStyle(
                    color: Color(0xFFFF8E8E),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (!keyboardOpen) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0x2A111A17),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x4DE7C06A)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Color(0xFFE9C46A),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _computedCoinCost > 0
                            ? 'Toplam maliyet: $_computedCoinCost coin'
                            : (_didUsernameChange && !widget.freeRenameUsed)
                            ? 'İlk isim değişikliği ücretsiz.'
                            : 'Bu kayıt için coin harcanmayacak.',
                        style: const TextStyle(
                          color: Color(0xFFD9EBDD),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(_saving ? 'Kontrol ediliyor' : 'Kaydet'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2B7B55),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(
                            color: Color(0xFF8F6215),
                            width: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _avatarPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 🔥 avatar preview (yukarı alındı)
        Transform.translate(
          offset: const Offset(0, -15),
          child: Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE9C46A), width: 2),
            ),
            child: ClipOval(
              child: selectedAvatarBytes != null
                  ? Image.memory(
                      selectedAvatarBytes!,
                      fit: BoxFit.cover,
                      key: ValueKey(
                        selectedAvatarBytes!.length,
                      ), // 🔥 repaint fix
                    )
                  : selectedAvatarRef != null
                  ? (selectedAvatarRef!.startsWith('http')
                        ? Image.network(
                            selectedAvatarRef!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _fallbackAvatar(),
                          )
                        : Image.asset(selectedAvatarRef!, fit: BoxFit.cover))
                  : _fallbackAvatar(),
            ),
          ),
        ),

        const SizedBox(height: 4), // 🔥 boşluk azaltıldı
        // 🔥 BUTONLAR (compact hale getirildi)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: _openAvatarGrid,
              icon: const Icon(Icons.grid_view_rounded, size: 18),
              label: const Text("Avatar Seç"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2B7B55),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(width: 10),

            OutlinedButton.icon(
              onPressed: _onUploadAvatar,
              icon: const Icon(Icons.photo_camera, size: 18),
              label: const Text("Fotoğraf"),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFFE9C46A)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _fallbackAvatar() {
    return Container(
      color: Colors.white10,
      child: const Icon(Icons.person, color: Colors.white38, size: 40),
    );
  }

  void _openAvatarGrid() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AvatarSelectionScreen(
          ownedPremiumAvatarRefs: {...ownedPremiumAvatarRefs},
          userCoins: widget.currentCoins,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        selectedAvatarRef = result;
        selectedAvatarBytes = null;
        isCustomAvatarSelected = false;
      });
    }
  }

  Widget _usernameSection() {
    final renameInfo = !widget.freeRenameUsed
        ? 'İlk isim değişikliği ücretsiz. Sonrası ${widget.renameCoinCost} coin.'
        : 'Her isim değişikliği ${widget.renameCoinCost} coin.';

    return SizedBox(
      width: 240,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Kullanıcı adı',
            style: TextStyle(
              color: Color(0xFFD9EBDD),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: usernameController,
            maxLength: 20,
            scrollPadding: const EdgeInsets.only(bottom: 240),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'Örnek: OkeyUstasi',
              hintStyle: const TextStyle(color: Color(0x88D9EBDD)),
              filled: true,
              fillColor: const Color(0x33273830),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            renameInfo,
            style: const TextStyle(
              color: Color(0xFFB9CFBF),
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onUploadAvatar() async {
    final picker = ImagePicker();

    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85, // ilk seviye sıkıştırma
    );

    if (file == null) return;

    Uint8List bytes;

    // 🔥 1. HER ZAMAN OKU (GARANTİ)
    bytes = await file.readAsBytes();

    // 🔥 2. MOBİLDE GÜVENLİ COMPRESS (NULL DÖNMEZ)
    if (!kIsWeb) {
      try {
        final compressed = await FlutterImageCompress.compressWithList(
          bytes,
          minWidth: 256,
          minHeight: 256,
          quality: 70,
        );

        if (compressed != null && compressed.isNotEmpty) {
          bytes = compressed;
        }
      } catch (_) {
        // fallback zaten bytes
      }
    }

    // 🔥 3. SON GÜVENLİK (BOYUT KONTROL)
    if (bytes.length > 1024 * 1024) {
      // hala büyükse tekrar sıkıştır
      try {
        final compressed = await FlutterImageCompress.compressWithList(
          bytes,
          minWidth: 256,
          minHeight: 256,
          quality: 60,
        );
        if (compressed != null && compressed.isNotEmpty) {
          bytes = compressed;
        }
      } catch (_) {}
    }

    if (!mounted) return;

    setState(() {
      selectedAvatarBytes = bytes;
      isCustomAvatarSelected = true;
    });
    showTopBanner(context);
  }

  OverlayEntry? entry;

  void showTopBanner(BuildContext context) {
    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: 20,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.85),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Color(0xFFE9C46A)),
            ),
            child: const Text(
              "Uygunsuz içerikler reddedilebilir.",
              style: TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(entry!);

    Future.delayed(const Duration(seconds: 5), () {
      entry?.remove();
    });
  }
}

class ProfileSetupResult {
  final String username;
  final String avatarRef;
  final int renameCoinSpent;
  final int avatarCoinSpent;
  final bool consumeFreeRename;
  final Set<String> newUnlockedPremiumAvatarRefs;
  int get spentCoins => renameCoinSpent + avatarCoinSpent;
  String? get unlockedAvatarRef => newUnlockedPremiumAvatarRefs.isEmpty
      ? null
      : newUnlockedPremiumAvatarRefs.first;

  const ProfileSetupResult({
    required this.username,
    required this.avatarRef,
    required this.renameCoinSpent,
    required this.avatarCoinSpent,
    required this.consumeFreeRename,
    required this.newUnlockedPremiumAvatarRefs,
  });
}
