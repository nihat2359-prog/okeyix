import 'package:flutter/material.dart';
import 'package:okeyix/screens/game_rules_screen.dart';

class LobbySideMenu extends StatelessWidget {
  final bool open;
  final VoidCallback? onDailyReward;
  final VoidCallback onClose,
      onSupport,
      onAnnouncements,
      onProfileCard,
      onSettings,
      onLogout;
  final Widget Function({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool danger,
  })
  menuButtonBuilder;
  final Color goldBorderColor;
  final double goldBorderWidth;

  const LobbySideMenu({
    super.key,
    required this.open,
    this.onDailyReward,
    required this.onClose,
    required this.onSupport,
    required this.onAnnouncements,
    required this.onProfileCard,
    required this.onSettings,
    required this.onLogout,
    required this.menuButtonBuilder,
    required this.goldBorderColor,
    required this.goldBorderWidth,
  });

  @override
  Widget build(BuildContext context) {
    if (!open) return const SizedBox.shrink();
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey('menu-backdrop'),
              onTap: onClose,
              child: const ColoredBox(color: Color(0x77050A11)),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 330,
                    maxHeight: 520,
                  ),
                  child: Stack(children: [
                    Padding(padding: const EdgeInsets.only(right: 40), child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xF21D232C), Color(0xED0A1018)],
                        ),
                        border: Border.all(
                          color: goldBorderColor.withValues(alpha: .5),
                          width: goldBorderWidth.clamp(.7, 1),
                        ),
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, bounds) => Column(
                                children:
                                    [
                                          menuButtonBuilder(
                                            icon: Icons.support_agent_outlined,
                                            label: 'Destek / Şikayet Gönder',
                                            onTap: onSupport,
                                          ),
                                          menuButtonBuilder(
                                            icon: Icons
                                                .notifications_none_rounded,
                                            label: 'Sistem Duyuruları',
                                            onTap: onAnnouncements,
                                          ),
                                          menuButtonBuilder(
                                            icon: Icons.badge_outlined,
                                            label: 'Profil Kartım',
                                            onTap: onProfileCard,
                                          ),
                                          menuButtonBuilder(
                                            icon: Icons.menu_book_outlined,
                                            label: 'Oyun Rehberi',
                                            onTap: () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    const GameRulesScreen(),
                                              ),
                                            ),
                                          ),
                                          if (onDailyReward != null) menuButtonBuilder(
                                            icon: Icons.redeem_rounded,
                                            label: 'Günlük Hediyeler',
                                            onTap: onDailyReward!,
                                          ),
                                          menuButtonBuilder(
                                            icon: Icons.tune_rounded,
                                            label: 'Ayarlar',
                                            onTap: onSettings,
                                          ),
                                        ]
                                        .map(
                                          (button) => Expanded(
                                            child: SizedBox.expand(
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                alignment: Alignment.centerLeft,
                                                child: SizedBox(
                                                  width: bounds.maxWidth,
                                                  child: button,
                                                ),
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Divider(color: Color(0x227C8798), height: 1),
                          const SizedBox(height: 6),
                          menuButtonBuilder(
                            icon: Icons.logout_rounded,
                            label: 'Çıkış Yap',
                            onTap: onLogout,
                            danger: true,
                          ),
                        ],
                      ),
                    ),
                    )),
                    Positioned(top: 0, right: 0,
                      child: Material(color: const Color(0xF21D232C),
                        shape: const CircleBorder(side: BorderSide(color: Color(0x667D704B))),
                        child: IconButton(
                          key: const ValueKey('menu-close'),
                          tooltip: 'Menüyü kapat', onPressed: onClose,
                          icon: const Icon(Icons.close_rounded, color: Color(0xFFD8CEB8), size: 22),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
