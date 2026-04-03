class AvatarPreset {
  final String id;
  final String label;
  final String imageUrl;

  const AvatarPreset({
    required this.id,
    required this.label,
    required this.imageUrl,
  });
}

const List<AvatarPreset> avatarPresets = <AvatarPreset>[
  AvatarPreset(
    id: 'kadin_01',
    label: 'Kadın Genç',
    imageUrl: 'assets/images/avatars/avatar13.png',
  ),
  AvatarPreset(
    id: 'kadin_02',
    label: 'Kadın Havalı',
    imageUrl: 'assets/images/avatars/avatar6.png',
  ),
  AvatarPreset(
    id: 'kadin_03',
    label: 'Kadın Şık',
    imageUrl: 'assets/images/avatars/avatar7.png',
  ),
  AvatarPreset(
    id: 'kadin_04',
    label: 'Kadın Olgun',
    imageUrl: 'assets/images/avatars/avatar12.png',
  ),
  AvatarPreset(
    id: 'kadin_05',
    label: 'Kadın Örtülü',
    imageUrl: 'assets/images/avatars/avatar15.png',
  ),
  AvatarPreset(
    id: 'kadin_06',
    label: 'Kadın Modern',
    imageUrl: 'assets/images/avatars/avatar5.png',
  ),

  AvatarPreset(
    id: 'erkek_01',
    label: 'Erkek Genç',
    imageUrl: 'assets/images/avatars/avatar8.png',
  ),
  AvatarPreset(
    id: 'erkek_02',
    label: 'Erkek Havalı',
    imageUrl: 'assets/images/avatars/avatar11.png',
  ),
  AvatarPreset(
    id: 'erkek_03',
    label: 'Erkek Şık',
    imageUrl: 'assets/images/avatars/avatar10.png',
  ),
  AvatarPreset(
    id: 'erkek_04',
    label: 'Erkek Olgun',
    imageUrl: 'assets/images/avatars/avatar2.png',
  ),
  AvatarPreset(
    id: 'erkek_05',
    label: 'Erkek Enerjik',
    imageUrl: 'assets/images/avatars/avatar3.png',
  ),
  AvatarPreset(
    id: 'erkek_06',
    label: 'Erkek Modern',
    imageUrl: 'assets/images/avatars/avatar1.png',
  ),
  AvatarPreset(
    id: 'erkek_07',
    label: 'Erkek Cool',
    imageUrl: 'assets/images/avatars/avatar9.png',
  ),
  AvatarPreset(
    id: 'erkek_08',
    label: 'Erkek Yaşlı',
    imageUrl: 'assets/images/avatars/avatar2.png',
  ),
  AvatarPreset(
    id: 'erkek_09',
    label: 'Erkek Karizmatik',
    imageUrl: 'assets/images/avatars/avatar14.png',
  ),
  AvatarPreset(
    id: 'erkek_10',
    label: 'Erkek Dinamik',
    imageUrl: 'assets/images/avatars/avatar16.png',
  ),
];

const List<String> avatarPresetIds = <String>[
  'kadin_01',
  'kadin_02',
  'kadin_03',
  'kadin_04',
  'kadin_05',
  'kadin_06',
  'kadin_07',
  'kadin_08',
  'kadin_09',
  'kadin_10',
  'erkek_01',
  'erkek_02',
  'erkek_03',
  'erkek_04',
  'erkek_05',
  'erkek_06',
  'erkek_07',
  'erkek_08',
  'erkek_09',
  'erkek_10',
];

AvatarPreset avatarPresetByRef(String? ref) {
  if (ref != null && ref.isNotEmpty) {
    for (final preset in avatarPresets) {
      if (preset.id == ref || preset.imageUrl == ref) {
        return preset;
      }
    }
  }
  return avatarPresets.first;
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
