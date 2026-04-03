import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:okeyix/screens/game_rules_screen.dart';

class LobbySideMenu extends StatelessWidget {
  final bool open;

  final VoidCallback onClose;

  final VoidCallback onLeaderboard;
  final VoidCallback onFriends;
  final VoidCallback onMessages;
  final VoidCallback onSettings;
  final VoidCallback onLogout;

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
    required this.onClose,
    required this.onLeaderboard,
    required this.onFriends,
    required this.onMessages,
    required this.onSettings,
    required this.onLogout,
    required this.menuButtonBuilder,
    required this.goldBorderColor,
    required this.goldBorderWidth,
  });

  @override
  Widget build(BuildContext context) {
    if (!open) return const SizedBox();

    return Positioned.fill(
      child: Stack(
        children: [
          /// MENU PANEL
          Align(
            alignment: Alignment.centerLeft,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              offset: open ? Offset.zero : const Offset(-1.2, 0),

              child: SafeArea(
                child: Container(
                  width: 320,
                  margin: const EdgeInsets.fromLTRB(10, 8, 0, 8),

                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),

                    border: Border.all(
                      color: goldBorderColor,
                      width: goldBorderWidth,
                    ),

                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x8A000000),
                        blurRadius: 26,
                        offset: Offset(4, 10),
                      ),
                    ],
                  ),

                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),

                    child: BackdropFilter(
                      /// blur biraz düşürüldü
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),

                      child: Container(
                        padding: const EdgeInsets.all(16),

                        decoration: BoxDecoration(
                          /// daha transparan glass panel
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              const Color(0xFF173A2C).withOpacity(0.05),
                              const Color(0xFF0A1511).withOpacity(0.05),
                            ],
                          ),
                        ),

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            /// HEADER
                            Row(
                              children: [
                                const Icon(
                                  Icons.menu_rounded,
                                  color: Color(0xFFE2B650),
                                  size: 20,
                                ),

                                const Expanded(
                                  child: Text(
                                    "MENÜ",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ),

                                IconButton(
                                  onPressed: onClose,
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),

                            /// DIVIDER
                            Container(
                              height: 1,
                              color: Colors.white.withOpacity(0.12),
                            ),

                            /// MENU BUTTONS
                            menuButtonBuilder(
                              icon: Icons.emoji_events_rounded,
                              label: 'En İyi Oyuncular',
                              onTap: onLeaderboard,
                            ),

                            menuButtonBuilder(
                              icon: Icons.group_rounded,
                              label: 'Arkadaşlar',
                              onTap: onFriends,
                            ),

                            menuButtonBuilder(
                              icon: Icons.mail_rounded,
                              label: 'Mesajlar',
                              onTap: onMessages,
                            ),

                            menuButtonBuilder(
                              icon: Icons.menu_book,
                              label: 'Oyun Rehberi',
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => GameRulesScreen(),
                                  ),
                                );
                              },
                            ),

                            menuButtonBuilder(
                              icon: Icons.settings_rounded,
                              label: 'Ayarlar',
                              onTap: onSettings,
                            ),

                            const Spacer(),

                            /// DIVIDER
                            Container(
                              height: 1,
                              color: Colors.white.withOpacity(0.12),
                            ),

                            const SizedBox(height: 5),

                            /// LOGOUT
                            menuButtonBuilder(
                              icon: Icons.logout_rounded,
                              label: 'Çıkış Yap',
                              onTap: onLogout,
                              danger: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
