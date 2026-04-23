import 'dart:ui';

import 'package:flutter/material.dart';
import '../avatar_preset.dart';

class LobbyAvatar extends StatelessWidget {
  final String username;
  final String? avatarUrl;
  final double size;
  final bool blocked;
  final bool enablePreview;
  const LobbyAvatar({
    super.key,
    required this.username,
    this.avatarUrl,
    this.size = 26,
    this.blocked = false,
    this.enablePreview = false,
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

    final avatarContent = Stack(
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

    if (enablePreview && image != null) {
      final safeImage = image;
      return GestureDetector(
        behavior: HitTestBehavior.opaque, // 🔥 çok önemli
        onTap: () => _showAvatarPreview(context, safeImage),
        child: avatarContent,
      );
    }

    return avatarContent;
  }

  void _showAvatarPreview(BuildContext context, ImageProvider image) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.55), // 🔥 transparan arka plan
      builder: (_) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 60, // 🔥 sağ-sol boşluk
            vertical: 40, // 🔥 üst-alt boşluk
          ),
          child: Stack(
            children: [
              // 🔥 MODAL PANEL
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1B2E28).withOpacity(0.95),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFE2B650),
                    width: 0.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE2B650).withOpacity(0.25),
                      blurRadius: 25,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(14),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),

                  // 🔥 ZOOM
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 3,
                    child: Image(image: image, fit: BoxFit.cover),
                  ),
                ),
              ),

              // 🔥 CLOSE BUTTON
              Positioned(
                right: 6,
                top: 6,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFE2B650)),
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
