import 'package:flutter/material.dart';
import '../avatar_preset.dart';

class LobbyAvatar extends StatelessWidget {
  final String username;
  final String? avatarUrl;
  final double size;
  final bool blocked;

  const LobbyAvatar({
    super.key,
    required this.username,
    this.avatarUrl,
    this.size = 26,
    this.blocked = false,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedAvatar = (avatarUrl ?? '').trim();
    final canUseNetworkImage = normalizedAvatar.startsWith('http');
    final canUseAssetImage = normalizedAvatar.startsWith('assets/');
    final hasPreset = isKnownAvatarPreset(normalizedAvatar);

    ImageProvider? image;

    if (canUseNetworkImage) {
      image = NetworkImage(normalizedAvatar);
    } else if (canUseAssetImage) {
      image = AssetImage(normalizedAvatar);
    } else if (hasPreset) {
      final preset = avatarPresetByRef(normalizedAvatar);
      image = AssetImage(preset.imageUrl);
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size * 2,
          height: size * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFE2B650), width: 1.6),
            image: image != null
                ? DecorationImage(
                    image: image,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.high,
                  )
                : null,
          ),
          child: image == null ? _fallback(username, size) : null,
        ),
        if (blocked)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.all(1),
              decoration: const BoxDecoration(
                color: Color(0xFFB32929),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.block_rounded,
                size: 11,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }

  Widget _fallback(String username, double size) {
    return Center(
      child: Text(
        username.isEmpty ? '?' : username[0].toUpperCase(),
        style: TextStyle(
          color: const Color(0xFF1A241F),
          fontSize: size * 0.85,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
