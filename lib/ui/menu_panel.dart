import 'dart:ui';
import 'package:flutter/material.dart';

class MenuPanel extends StatelessWidget {
  final bool isOpen;
  final VoidCallback onClose;
  final VoidCallback onExit;
  final VoidCallback onSettings;

  const MenuPanel({
    super.key,
    required this.isOpen,
    required this.onClose,
    required this.onExit,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      left: isOpen ? 0 : -320,
      top: 0,
      bottom: 0,
      width: 320,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xCC0F141A),
              border: Border(right: BorderSide(color: Color(0x22FFFFFF))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Menu",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: onClose,
                    ),
                  ],
                ),

                const SizedBox(height: 40),

                _menuButton(
                  icon: Icons.settings,
                  text: "Ayarlar",
                  onTap: onSettings,
                ),

                const SizedBox(height: 20),

                _menuButton(
                  icon: Icons.logout,
                  text: "Masadan Çık",
                  onTap: onExit,
                  danger: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuButton({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [Color(0x661A222A), Color(0x33141A20)],
          ),
          border: Border.all(
            color: danger ? Color(0x99FF0000) : const Color(0x22FFFFFF),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: danger ? Colors.red : Colors.white),
            const SizedBox(width: 12),
            Text(
              text,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: danger ? Colors.red : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
