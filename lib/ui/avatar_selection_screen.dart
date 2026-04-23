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
  const AvatarSelectionScreen({
    super.key,
    required this.ownedPremiumAvatarRefs,
    required this.userCoins,
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

    final crossAxisCount = isLandscape ? 6 : 4;

    final freeWomen = freeAvatarPresetsByGender('female');
    final freeMen = freeAvatarPresetsByGender('male');
    final premiumWomen = premiumAvatarPresetsByGender('female');
    final premiumMen = premiumAvatarPresetsByGender('male');

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // 🔥 BLUR ARKA PLAN
          SafeArea(
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xEE13291F), Color(0xEE0C1712)],
                ),
                color: const Color(0xFF0F2F2A).withOpacity(0.90),
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
                  // 🔥 HEADER
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          "Avatar Seç",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white70),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // 🔥 LIST
                  Expanded(
                    child: ListView(
                      children: [
                        _avatarSection(
                          title: 'Standart Kadın Avatarları',
                          subtitle: 'Ücretsiz',
                          presets: freeWomen,
                          crossAxisCount: crossAxisCount,
                        ),
                        const SizedBox(height: 12),
                        _avatarSection(
                          title: 'Standart Erkek Avatarları',
                          subtitle: 'Ücretsiz',
                          presets: freeMen,
                          crossAxisCount: crossAxisCount,
                        ),
                        const SizedBox(height: 12),
                        _avatarSection(
                          title: 'Premium Kadın Avatarları',
                          subtitle: 'Coin ile açılır',
                          presets: premiumWomen,
                          crossAxisCount: crossAxisCount,
                          premiumHeader: true,
                        ),
                        const SizedBox(height: 12),
                        _avatarSection(
                          title: 'Premium Erkek Avatarları',
                          subtitle: 'Coin ile açılır',
                          presets: premiumMen,
                          crossAxisCount: crossAxisCount,
                          premiumHeader: true,
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
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  preset.imageUrl,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.cover, // 🔥 EN KRİTİK
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
