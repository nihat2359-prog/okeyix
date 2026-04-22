import 'package:flutter/material.dart';
import '../main.dart';
import '../services/profile_service.dart';
import 'gift_explosion_widget.dart';

class GiftOverlay {
  static final List<OverlayEntry> _entries = [];

  static void show({
    required String senderId,
    required String senderName,
    required String emoji,
    required String giftName,
  }) {
    final overlay = overlayKey.currentState;
    if (overlay == null) return;

    late OverlayEntry entry; // 🔥 ÖNCE TANIMLA

    entry = OverlayEntry(
      builder: (_) => SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 10,
              right: 12,
              child: Material(
                color: Colors.transparent,
                child: GiftExplosionWidget(
                  senderName: senderName,
                  emoji: emoji,
                  giftName: giftName,

                  // 👤 PROFİL AÇ
                  onTapUser: () {
                    ProfileService.showUserCard({
                      "id": senderId,
                      "username": senderName,
                    });
                  },

                  // ❌ KAPAT
                  onClose: () {
                    entry.remove();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );

    overlay.insert(entry);
  }
}
