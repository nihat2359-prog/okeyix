import 'package:flutter/material.dart';
import 'package:okeyix/main.dart';
import 'package:okeyix/ui/avatar_preset.dart';
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

  int get _computedCoinCost {
    return _renameCoinCostToCharge + _avatarCoinCostToCharge;
  }

  @override
  void initState() {
    super.initState();
    usernameController = TextEditingController(text: widget.initialUsername);
    selectedAvatarRef = avatarPresetByRef(widget.initialAvatarRef).id;
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

  Future<void> _save() async {
    if (_saving) return;
    final username = usernameController.text.trim();
    if (username.isEmpty) {
      setState(() => errorText = 'Kullanıcı adı zorunlu.');
      return;
    }

    final renameCoinSpent = _renameCoinCostToCharge;
    final avatarCoinSpent = _avatarCoinCostToCharge;
    final spentCoins = renameCoinSpent + avatarCoinSpent;
    if (spentCoins > widget.currentCoins) {
      setState(() {
        errorText =
            'Yetersiz coin. Gereken: $spentCoins, mevcut: ${widget.currentCoins}.';
      });
      return;
    }

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
          errorText = 'Kullanıcı adı kontrol edilemedi. Tekrar dene.';
        });
        return;
      }
      if (!mounted) return;
      setState(() => _saving = false);
    }

    final unlockedPremium = <String>{};
    if (_isSelectedPremiumLocked) {
      unlockedPremium.add(_selectedPreset.id);
    }

    Navigator.pop(
      context,
      ProfileSetupResult(
        username: username,
        avatarRef: selectedAvatarRef,
        renameCoinSpent: renameCoinSpent,
        avatarCoinSpent: avatarCoinSpent,
        consumeFreeRename: _willConsumeFreeRename,
        newUnlockedPremiumAvatarRefs: unlockedPremium,
      ),
    );
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
        width: isLandscape ? 720 : 520,
        constraints: BoxConstraints(maxHeight: maxDialogHeight),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF17382E), Color(0xFF0D221B)],
          ),
          border: Border.all(color: const Color(0xD7D0A14A), width: 1.8),
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
              child: isLandscape
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _usernameSection(),
                        if (!keyboardOpen) ...[
                          const SizedBox(width: 18),
                          Expanded(child: _avatarGrid()),
                        ],
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _usernameSection(),
                        if (!keyboardOpen) ...[
                          const SizedBox(height: 14),
                          Expanded(child: _avatarGrid()),
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

  Widget _avatarGrid() {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final crossAxisCount = isLandscape ? 5 : 4;

    final freeWomen = freeAvatarPresetsByGender('female');
    final freeMen = freeAvatarPresetsByGender('male');
    final premiumWomen = premiumAvatarPresetsByGender('female');
    final premiumMen = premiumAvatarPresetsByGender('male');

    return ListView(
      children: [
        _avatarSection(
          title: 'Standart Kadın Avatarları',
          subtitle: 'Ücretsiz',
          presets: freeWomen,
          crossAxisCount: crossAxisCount,
        ),
        const SizedBox(height: 14),
        _avatarSection(
          title: 'Standart Erkek Avatarları',
          subtitle: 'Ücretsiz',
          presets: freeMen,
          crossAxisCount: crossAxisCount,
        ),
        const SizedBox(height: 14),
        _avatarSection(
          title: 'Premium Kadın Avatarları',
          subtitle: 'Coin ile açılır',
          presets: premiumWomen,
          crossAxisCount: crossAxisCount,
          premiumHeader: true,
        ),
        const SizedBox(height: 14),
        _avatarSection(
          title: 'Premium Erkek Avatarları',
          subtitle: 'Coin ile açılır',
          presets: premiumMen,
          crossAxisCount: crossAxisCount,
          premiumHeader: true,
        ),
      ],
    );
  }

  Widget _avatarSection({
    required String title,
    required String subtitle,
    required List<AvatarPreset> presets,
    required int crossAxisCount,
    bool premiumHeader = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: TextStyle(
                color: premiumHeader
                    ? const Color(0xFFFFD27D)
                    : const Color(0xFFE3F4E8),
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: premiumHeader
                    ? const Color(0x33FFD27D)
                    : const Color(0x3345B47A),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: premiumHeader
                      ? const Color(0x66FFD27D)
                      : const Color(0x6645B47A),
                ),
              ),
              child: Text(
                subtitle,
                style: TextStyle(
                  color: premiumHeader
                      ? const Color(0xFFFFD27D)
                      : const Color(0xFFBFE5CC),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.builder(
          itemCount: presets.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemBuilder: (_, index) => _avatarTile(presets[index]),
        ),
      ],
    );
  }

  Widget _avatarTile(AvatarPreset preset) {
    final selected = selectedAvatarRef == preset.id;
    final isLockedPremium =
        preset.isPremium && !ownedPremiumAvatarRefs.contains(preset.id);

    return InkWell(
      onTap: () => setState(() => selectedAvatarRef = preset.id),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: preset.isPremium
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0x6640200D), Color(0x44401008)],
                )
              : null,
          color: preset.isPremium ? null : const Color(0x44213129),
          border: Border.all(
            color: selected
                ? const Color(0xFFE8C36A)
                : (preset.isPremium
                      ? const Color(0x66FFD27D)
                      : const Color(0x334F8F75)),
            width: selected ? 2 : 1,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: CircleAvatar(
                radius: 28,
                backgroundImage: AssetImage(preset.imageUrl),
              ),
            ),
            if (isLockedPremium)
              Positioned(
                left: 4,
                right: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xCC111111),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${preset.unlockCost} coin',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFFD27D),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            if (preset.isPremium)
              const Positioned(
                top: 4,
                right: 4,
                child: Icon(
                  Icons.workspace_premium_rounded,
                  size: 14,
                  color: Color(0xFFFFD27D),
                ),
              ),
            if (isLockedPremium)
              const Positioned(
                top: 4,
                left: 4,
                child: Icon(
                  Icons.lock_rounded,
                  size: 14,
                  color: Color(0xFFFFD27D),
                ),
              ),
          ],
        ),
      ),
    );
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
