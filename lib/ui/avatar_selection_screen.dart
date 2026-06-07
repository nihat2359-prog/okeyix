import 'package:flutter/material.dart';
import 'package:okeyix/ui/avatar_preset.dart';

// 🔥 senin mevcut fonksiyonların (zaten projede var)
List<AvatarPreset> freeAvatarPresetsByGender(String gender) {
  return avatarPresets
      .where((e) => e.gender == gender && !e.isPremium)
      .toList();
}

List<AvatarPreset> premiumAvatarPresetsByGender(String gender) {
  return avatarPresets.where((e) => e.gender == gender && e.isPremium).toList();
}

class AvatarSelectionScreen extends StatefulWidget {
  final Set<String> ownedPremiumAvatarRefs;
  final int userCoins;
  final bool showPremium;
  final String title;
  final bool canClose;
  const AvatarSelectionScreen({
    super.key,
    required this.ownedPremiumAvatarRefs,
    required this.userCoins,
    this.showPremium = true,
    this.title = 'Avatar Seç',
    this.canClose = true,
  });

  @override
  State<AvatarSelectionScreen> createState() => _AvatarSelectionScreenState();
}

class _AvatarSelectionScreenState extends State<AvatarSelectionScreen> {
  String? selectedAvatarRef;

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    final freeWomen = freeAvatarPresetsByGender('female');
    final freeMen = freeAvatarPresetsByGender('male');
    final premiumWomen = premiumAvatarPresetsByGender('female');
    final premiumMen = premiumAvatarPresetsByGender('male');

    return PopScope(
      canPop: widget.canClose,
      child: Scaffold(
        backgroundColor: const Color(0xFF0C0F14),
        body: Stack(
          children: [
            Positioned(
              top: -120,
              left: -50,
              child: _ambientOrb(const Color(0x663A4A66), 240),
            ),
            Positioned(
              bottom: -140,
              right: -40,
              child: _ambientOrb(const Color(0x66E9C46A), 280),
            ),
            SafeArea(
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xEE232A33), Color(0xEE131820)],
                  ),
                  border: Border.all(
                    color: const Color(0xE0D0A14A),
                    width: 0.7,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0xC0000000),
                      blurRadius: 34,
                      offset: Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 10),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _genderColumn(
                              title: 'Kadın Avatarları',
                              freePresets: freeWomen,
                              premiumPresets: premiumWomen,
                              crossAxisCount: isLandscape ? 3 : 2,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _genderColumn(
                              title: 'Erkek Avatarları',
                              freePresets: freeMen,
                              premiumPresets: premiumMen,
                              crossAxisCount: isLandscape ? 3 : 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ambientOrb(Color color, double size) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, Colors.transparent],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return Container(
      padding: EdgeInsets.fromLTRB(
        isLandscape ? 7 : 10,
        isLandscape ? 6 : 10,
        isLandscape ? 4 : 8,
        isLandscape ? 6 : 10,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x20FFFFFF), Color(0x10000000)],
        ),
        border: Border.all(color: const Color(0x55E9C46A)),
      ),
      child: Row(
        children: [
          Container(
            width: isLandscape ? 32 : 44,
            height: isLandscape ? 32 : 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: const Color(0x332A313C),
              border: Border.all(color: const Color(0x66E9C46A)),
            ),
            child: Icon(
              Icons.face_retouching_natural_rounded,
              color: Color(0xFFFFE0A8),
              size: isLandscape ? 18 : 24,
            ),
          ),
          SizedBox(width: isLandscape ? 6 : 10),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isLandscape ? 13 : 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                if (isLandscape && widget.showPremium)
                  const Text(
                    '(Premium seçilebilir)',
                    style: TextStyle(
                      color: Color(0xFFD5EADB),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
          if (widget.canClose)
            IconButton(
              onPressed: () => Navigator.pop(context),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, color: Colors.white70),
            ),
        ],
      ),
    );
  }

  Widget _genderColumn({
    required String title,
    required List<AvatarPreset> freePresets,
    required List<AvatarPreset> premiumPresets,
    required int crossAxisCount,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x33BFC7D8)),
      ),
      child: ListView(
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFFF6F9F8),
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                        letterSpacing: 0.2,
                      ),
                    ),
                    _tagChip(
                      text: 'Standart',
                      bg: const Color(0x2A55627A),
                      border: const Color(0x7A7387A8),
                      fg: const Color(0xFFE8FFF2),
                    ),
                    _tagChip(
                      text: 'Ücretsiz',
                      bg: const Color(0x334B647F),
                      border: const Color(0x8D6F8DB3),
                      fg: const Color(0xFFEFFFF8),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _avatarGrid(presets: freePresets, crossAxisCount: crossAxisCount),
          if (widget.showPremium) ...[
            const SizedBox(height: 12),
            _avatarSection(
              title: 'Premium',
              subtitle: 'Coin ile açılır',
              presets: premiumPresets,
              crossAxisCount: crossAxisCount,
              premiumHeader: true,
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _avatarGrid({
    required List<AvatarPreset> presets,
    required int crossAxisCount,
  }) {
    return GridView.builder(
      itemCount: presets.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.92,
      ),
      itemBuilder: (_, index) => _avatarTile(presets[index]),
    );
  }

  Widget _tagChip({
    required String text,
    required Color bg,
    required Color border,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.15,
        ),
      ),
    );
  }

  // 🔥 SENİN ESKİ KODUN (DÜZELTİLDİ)
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
                    : const Color(0x33384A60),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: premiumHeader
                      ? const Color(0x66FFD27D)
                      : const Color(0x667A8EA8),
                ),
              ),
              child: Text(
                subtitle,
                style: TextStyle(
                  color: premiumHeader
                      ? const Color(0xFFFFD27D)
                      : const Color(0xFFDCE5F2),
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
            childAspectRatio: 0.84,
          ),
          itemBuilder: (_, index) => _avatarTile(presets[index]),
        ),
      ],
    );
  }

  Widget _avatarTile(AvatarPreset preset) {
    final selected = selectedAvatarRef == preset.id;

    final hasEnoughCoins = widget.userCoins >= preset.unlockCost;

    final isLockedPremium =
        preset.isPremium &&
        !widget.ownedPremiumAvatarRefs.contains(preset.id) &&
        !hasEnoughCoins;

    final isOwned = widget.ownedPremiumAvatarRefs.contains(preset.id);
    final isPremiumLocked = preset.isPremium && !isOwned;

    return InkWell(
      onTap: () {
        // 🔥 premium kilit kontrolü
        if (preset.isPremium &&
            !widget.ownedPremiumAvatarRefs.contains(preset.id)) {
          if (widget.userCoins < preset.unlockCost) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("${preset.unlockCost} coin gerekli")),
            );
            return;
          }

          // 🔥 BURASI ÖNEMLİ
          // satın al (şimdilik local)
          widget.ownedPremiumAvatarRefs.add(preset.id);
        }

        setState(() {
          selectedAvatarRef = preset.id;
        });

        // 🔥 seç → geri dön
        Navigator.pop(context, preset.imageUrl);
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: preset.isPremium
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0x9A4F2E10), Color(0x7635160B)],
                )
              : null,
          color: preset.isPremium ? null : const Color(0x4F243B33),
          border: Border.all(
            color: selected
                ? const Color(0xFFE8C36A)
                : (preset.isPremium
                      ? const Color(0x66FFD27D)
                      : const Color(0x447A8EA8)),
            width: selected ? 2.2 : 1.0,
          ),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x66E9C46A),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  height: double.infinity,
                  color: const Color(0xFF1A212B),
                  padding: const EdgeInsets.all(4),
                  child: Image.asset(
                    preset.imageUrl,
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0x33000000)],
                  ),
                ),
              ),
            ),

            if (isPremiumLocked)
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
