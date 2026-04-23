class AvatarPreset {
  final String id;
  final String label;
  final String imageUrl;
  final String gender;
  final bool isPremium;
  final int unlockCost;
  final bool isCustom;

  const AvatarPreset({
    required this.id,
    required this.label,
    required this.imageUrl,
    required this.gender,
    this.isPremium = false,
    this.unlockCost = 0,
    this.isCustom = false,
  });
}

const List<AvatarPreset> avatarPresets = <AvatarPreset>[
  AvatarPreset(
    id: 'kadin_01',
    label: 'Kadin Genc',
    imageUrl: 'assets/images/avatars/avatar13.png',
    gender: 'female',
  ),
  AvatarPreset(
    id: 'kadin_02',
    label: 'Kadin Havali',
    imageUrl: 'assets/images/avatars/avatar6.png',
    gender: 'female',
  ),
  AvatarPreset(
    id: 'kadin_03',
    label: 'Kadin Sik',
    imageUrl: 'assets/images/avatars/avatar7.png',
    gender: 'female',
  ),
  AvatarPreset(
    id: 'kadin_04',
    label: 'Kadin Olgun',
    imageUrl: 'assets/images/avatars/avatar12.png',
    gender: 'female',
  ),
  AvatarPreset(
    id: 'kadin_05',
    label: 'Kadin Ortulu',
    imageUrl: 'assets/images/avatars/avatar15.png',
    gender: 'female',
  ),
  AvatarPreset(
    id: 'kadin_06',
    label: 'Kadin Modern',
    imageUrl: 'assets/images/avatars/avatar5.png',
    gender: 'female',
  ),
  AvatarPreset(
    id: 'erkek_01',
    label: 'Erkek Genc',
    imageUrl: 'assets/images/avatars/avatar8.png',
    gender: 'male',
  ),
  AvatarPreset(
    id: 'erkek_02',
    label: 'Erkek Havali',
    imageUrl: 'assets/images/avatars/avatar11.png',
    gender: 'male',
  ),
  AvatarPreset(
    id: 'erkek_03',
    label: 'Erkek Sik',
    imageUrl: 'assets/images/avatars/avatar10.png',
    gender: 'male',
  ),
  AvatarPreset(
    id: 'erkek_04',
    label: 'Erkek Olgun',
    imageUrl: 'assets/images/avatars/avatar2.png',
    gender: 'male',
  ),
  AvatarPreset(
    id: 'erkek_05',
    label: 'Erkek Enerjik',
    imageUrl: 'assets/images/avatars/avatar3.png',
    gender: 'male',
  ),
  AvatarPreset(
    id: 'erkek_06',
    label: 'Erkek Modern',
    imageUrl: 'assets/images/avatars/avatar1.png',
    gender: 'male',
  ),
  AvatarPreset(
    id: 'erkek_07',
    label: 'Erkek Cool',
    imageUrl: 'assets/images/avatars/avatar9.png',
    gender: 'male',
  ),
  AvatarPreset(
    id: 'erkek_08',
    label: 'Erkek Yasli',
    imageUrl: 'assets/images/avatars/avatar4.png',
    gender: 'male',
  ),
  AvatarPreset(
    id: 'erkek_09',
    label: 'Erkek Karizmatik',
    imageUrl: 'assets/images/avatars/avatar14.png',
    gender: 'male',
  ),
  AvatarPreset(
    id: 'erkek_10',
    label: 'Erkek Dinamik',
    imageUrl: 'assets/images/avatars/avatar16.png',
    gender: 'male',
  ),
  AvatarPreset(
    id: 'premium_kadin_01',
    label: 'Premium Kadin 1',
    imageUrl: 'assets/images/avatars/premium/premium_kadin_01.png',
    gender: 'female',
    isPremium: true,
    unlockCost: 2500,
  ),
  AvatarPreset(
    id: 'premium_kadin_02',
    label: 'Premium Kadin 2',
    imageUrl: 'assets/images/avatars/premium/premium_kadin_02.png',
    gender: 'female',
    isPremium: true,
    unlockCost: 2500,
  ),
  AvatarPreset(
    id: 'premium_kadin_03',
    label: 'Premium Kadin 3',
    imageUrl: 'assets/images/avatars/premium/premium_kadin_03.png',
    gender: 'female',
    isPremium: true,
    unlockCost: 2500,
  ),
  AvatarPreset(
    id: 'premium_kadin_04',
    label: 'Premium Kadin 4',
    imageUrl: 'assets/images/avatars/premium/premium_kadin_04.png',
    gender: 'female',
    isPremium: true,
    unlockCost: 2500,
  ),
  AvatarPreset(
    id: 'premium_erkek_01',
    label: 'Premium Erkek 1',
    imageUrl: 'assets/images/avatars/premium/premium_erkek_01.png',
    gender: 'male',
    isPremium: true,
    unlockCost: 2500,
  ),
  AvatarPreset(
    id: 'premium_erkek_02',
    label: 'Premium Erkek 2',
    imageUrl: 'assets/images/avatars/premium/premium_erkek_02.png',
    gender: 'male',
    isPremium: true,
    unlockCost: 2500,
  ),
  AvatarPreset(
    id: 'premium_erkek_03',
    label: 'Premium Erkek 3',
    imageUrl: 'assets/images/avatars/premium/premium_erkek_03.png',
    gender: 'male',
    isPremium: true,
    unlockCost: 2500,
  ),
  AvatarPreset(
    id: 'premium_erkek_04',
    label: 'Premium Erkek 4',
    imageUrl: 'assets/images/avatars/premium/premium_erkek_04.png',
    gender: 'male',
    isPremium: true,
    unlockCost: 2500,
  ),
];

final List<String> avatarPresetIds = <String>[
  for (final preset in avatarPresets) preset.id,
];

AvatarPreset avatarPresetByRef(String? ref) {
  if (ref != null && ref.isNotEmpty) {
    for (final preset in avatarPresets) {
      if (preset.id == ref || preset.imageUrl == ref) {
        return preset;
      }
    }

    // 🔥 BURASI KRİTİK
    if (ref.startsWith('http')) {
      return buildCustomAvatar(ref);
    }
  }

  return avatarPresets.first;
}

AvatarPreset buildCustomAvatar(String url) {
  return AvatarPreset(
    id: url, // 🔥 unique olması için
    label: 'Custom',
    imageUrl: url,
    gender: 'all',
    isCustom: true,
  );
}

bool isKnownAvatarPreset(String? ref) {
  if (ref == null || ref.isEmpty) return false;
  for (final preset in avatarPresets) {
    if (preset.id == ref || preset.imageUrl == ref) return true;
  }
  return false;
}

String normalizeAvatarForStorage(String ref) {
  return avatarPresetByRef(ref).imageUrl;
}

String defaultAvatarPresetForSeat(int seatIndex) {
  return avatarPresets[seatIndex % avatarPresets.length].imageUrl;
}

List<AvatarPreset> freeAvatarPresetsByGender(String gender) {
  return avatarPresets
      .where((p) => !p.isPremium && p.gender == gender)
      .toList(growable: false);
}

List<AvatarPreset> premiumAvatarPresetsByGender(String gender) {
  return avatarPresets
      .where((p) => p.isPremium && p.gender == gender)
      .toList(growable: false);
}
