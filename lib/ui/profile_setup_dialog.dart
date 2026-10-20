import 'dart:typed_data';
import 'dart:ui';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:okeyix/main.dart';
import 'package:okeyix/ui/avatar_preset.dart';
import 'profile_editor_scene.dart';
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
  final bool asPage;
  final String initialUsername;
  final String? initialAvatarRef;
  final String currentUserId;
  final int currentCoins;
  final int renameCoinCost;
  final bool freeRenameUsed;
  final Set<String> ownedPremiumAvatarRefs;

  const ProfileSetupDialog({
    required this.forceComplete,
    this.asPage = false,
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
  static final Random _random = Random();
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
    final client = Supabase.instance.client;
    final rowsUsers = await client
        .from('users')
        .select('id')
        .ilike('username', username)
        .limit(5);
    for (final row in (rowsUsers as List)) {
      final id = row['id']?.toString();
      if (id != null && id != widget.currentUserId) {
        return true;
      }
    }

    final rowsProfiles = await client
        .from('profiles')
        .select('id')
        .ilike('username', username)
        .limit(5);
    for (final row in (rowsProfiles as List)) {
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

    final username = widget.forceComplete
        ? await _generateAutoUsername()
        : usernameController.text.trim();

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
    if (!widget.forceComplete && _didUsernameChange) {
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
  Widget build(BuildContext context) => PopScope(
    canPop: !widget.forceComplete,
    child: ProfileEditorScene(
      avatar: _avatarPortrait(),
      username: usernameController,
      forceComplete: widget.forceComplete,
      asPage: widget.asPage,
      saving: _saving,
      error: errorText,
      renameInfo: !widget.freeRenameUsed
          ? 'İlk isim değişikliği ücretsiz. Sonrası ${widget.renameCoinCost} coin.'
          : 'Her isim değişikliği ${widget.renameCoinCost} coin.',
      costInfo: _computedCoinCost > 0
          ? 'Toplam maliyet: $_computedCoinCost coin'
          : _willConsumeFreeRename
          ? 'İlk isim değişikliği ücretsiz.'
          : 'Bu kayıt için coin harcanmayacak.',
      onAvatar: _openAvatarGrid,
      onPhoto: _onUploadAvatar,
      onSave: _save,
      onClose: () => Navigator.pop(context),
    ),
  );
  Future<String> _generateAutoUsername() async {
    String buildSuffix(int length) {
      const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      final buffer = StringBuffer();
      for (var i = 0; i < length; i++) {
        buffer.write(alphabet[_random.nextInt(alphabet.length)]);
      }
      return buffer.toString();
    }

    for (var i = 0; i < 2000; i++) {
      final len = _random.nextBool() ? 5 : 6;
      final candidate = 'Oyuncu_${buildSuffix(len)}';
      final taken = await _isUsernameTaken(candidate);
      if (!taken) return candidate;
    }

    while (true) {
      final raw =
          (DateTime.now().microsecondsSinceEpoch ^ _random.nextInt(1 << 20))
              .toRadixString(36)
              .toUpperCase();
      final suffix = raw.length > 6 ? raw.substring(raw.length - 6) : raw;
      final candidate = 'Oyuncu_$suffix';
      final taken = await _isUsernameTaken(candidate);
      if (!taken) return candidate;
    }
  }

  Widget _avatarPortrait() {
    if (selectedAvatarBytes != null) {
      return Image.memory(
        selectedAvatarBytes!,
        fit: BoxFit.cover,
        key: ValueKey(selectedAvatarBytes!.length),
      );
    }
    if (selectedAvatarRef.startsWith('http')) {
      return Image.network(
        selectedAvatarRef,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _fallbackAvatar(),
      );
    }
    return Image.asset(
      selectedAvatarRef,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _fallbackAvatar(),
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
          showPremium: !widget.forceComplete,
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
