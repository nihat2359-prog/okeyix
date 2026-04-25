import 'dart:ui';

import 'package:flutter/material.dart';
import 'lobby_shimmer_loaders.dart';

class LobbyLeagueList extends StatelessWidget {
  final List<Map<String, dynamic>> leagues;
  final dynamic selectedLeagueId;
  final Map<String, int> leagueActivePlayers;
  final Function(Map<String, dynamic>) onSelect;
  final int userCoin;
  final int userRating;
  final bool loading;
  const LobbyLeagueList({
    super.key,
    required this.leagues,
    required this.selectedLeagueId,
    required this.leagueActivePlayers,
    required this.onSelect,
    required this.userCoin,
    required this.userRating,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const LobbyLoading();
    }

    if (leagues.isEmpty) {
      return const Center(
        child: Text(
          "No leagues available",
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
      );
    }
    return _buildLeagueGrid();
  }

  Widget _buildLeagueGrid() {
    if (leagues.length < 5) return const SizedBox();

    return Column(
      children: [
        /// ROW 1
        Row(
          children: [
            Expanded(child: _leagueItem(leagues[0])),

            Expanded(child: _leagueItem(leagues[1])),
          ],
        ),

        /// ROW 2
        Row(
          children: [
            Expanded(child: _leagueItem(leagues[2])),

            Expanded(child: _leagueItem(leagues[3])),
          ],
        ),

        /// ROW 3 (ŞAMPİYON)
        SizedBox(
          width: double.infinity,
          child: _leagueItem(leagues[4], isBig: true),
        ),
      ],
    );
  }

  Widget _leagueItem(Map league, {bool isBig = false}) {
    final l = Map<String, dynamic>.from(league);

    final selected = l['id'] == selectedLeagueId;
    final activePlayers = leagueActivePlayers[l['id']] ?? 0;
    //final activeTables = leagueActiveTables[l['id']] ?? 0;
    final activeTables = 0;
    final color = _leagueColorById(l['id']);

    return GestureDetector(
      onTap: () => onSelect(l),

      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: isBig ? 58 : 58,

        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        padding: EdgeInsets.symmetric(
          horizontal: l['id'] == 'elite' ? 2 : 8, // 🔥 BURASI
          vertical: 6,
        ),

        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: selected ? const Color(0x221E3A28) : const Color(0x22111111),
          border: Border.all(
            color: selected ? color : const Color(0x33FFFFFF),
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.35),
                    blurRadius: isBig ? 20 : 14,
                  ),
                ]
              : null,
        ),

        child: l['id'] == 'elite'
            ? _eliteCard(l, color, isBig)
            : _normalCard(l, color, isBig),
      ),
    );
  }

  Widget _leagueTitle(String text, Color color, {bool isBig = false}) {
    return Center(
      child: ShaderMask(
        shaderCallback: (bounds) {
          return LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFFFF3C4), // ✨ sıcak highlight (beyaz değil!)
              color, // ana gold
              const Color(0xFF7A5A1A), // 🔥 koyu gold (kontrast)
            ],
          ).createShader(bounds);
        },
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: isBig ? 16 : 14,
            letterSpacing: 0.6,
            color: Colors.white,

            shadows: [
              // 🔥 bu en kritik
              Shadow(
                color: Colors.black.withOpacity(0.9),
                offset: const Offset(0, 2),
                blurRadius: 6,
              ),

              // hafif sıcak glow
              Shadow(
                color: const Color(0xFFFFD54F).withOpacity(0.4),
                blurRadius: 8,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _leagueColorById(String id) {
    switch (id) {
      case 'standard': // Acemiler
        return const Color(0xFFFFD54F); // neon green

      case 'bronze': // Çıraklar
        return const Color(0xFFFFD54F); // canlı bronze (turuncuya yakın)

      case 'silver': // Kalfalar
        return const Color(0xFFFFD54F); // açık silver (parlak)

      case 'gold': // Ustalar
        return const Color(0xFFFFD54F); // vivid gold

      case 'elite': // Şampiyonlar
        return const Color(0xFFFFD54F); // premium neon gold (🔥)

      default:
        return const Color(0xFFFFD54F);
    }
  }

  Widget _leagueMiniBadge(Map l) {
    final id = l['id'];

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20), // biraz düşürdük
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            /// ❌ artık background yok
            color: Colors.transparent,

            borderRadius: BorderRadius.circular(12),

            /// 🔥 çok hafif çizgi bırak (opsiyonel ama öneririm)
            border: Border.all(color: Colors.white.withOpacity(0.06), width: 1),
          ),
          child: Center(
            child: Icon(
              _leagueIcon(id),
              size: 12,
              color: const Color(0xFFE0C48F),
            ),
          ),
        ),
      ),
    );
  }

  Widget _eliteCard(Map l, Color color, bool isBig) {
    final activePlayers = leagueActivePlayers[l['id']] ?? 0;
    final activeTables = 0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        /// 🏆 SOL ARKA PLAN ICON
        Positioned(
          left: 8,
          top: 0,
          bottom: 0,
          child: Center(
            child: Opacity(
              opacity: 0.32, // 🔥 transparan (çok önemli)
              child: Icon(
                Icons.emoji_events,
                size: 40,
                color: const Color(0xFFE0C48F),
              ),
            ),
          ),
        ),

        /// 🔥 ANA CONTENT (ORTALI)
        Center(
          child: Padding(
            padding: EdgeInsets.only(left: isBig ? 50 : 40), // 🔥 boşluk
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _leagueTitle(l['name'] ?? '', color, isBig: isBig),

                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.people, size: 14, color: Colors.white60),
                    const SizedBox(width: 4),
                    Text(
                      "$activePlayers",
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),

                    const SizedBox(width: 6),
                    const Text("•", style: TextStyle(color: Colors.white38)),
                    const SizedBox(width: 6),

                    const Icon(
                      Icons.table_bar,
                      size: 14,
                      color: Colors.white60,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      "$activeTables",
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _normalCard(Map l, Color color, bool isBig) {
    final selected = l['id'] == selectedLeagueId;
    final activePlayers = leagueActivePlayers[l['id']] ?? 0;
    final activeTables = 0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        /// ANA KART
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// LIG ADI (ORTALI)
            _leagueTitle(l['name'] ?? '', color, isBig: isBig),

            const Spacer(),

            /// ALT BİLGİ
            Row(
              children: [
                Expanded(
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        /// 👥 OYUNCU
                        Row(
                          children: [
                            const Icon(
                              Icons.people,
                              size: 14,
                              color: Colors.white60,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              "$activePlayers",
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(width: 6),

                        /// AYIRICI
                        const Text(
                          "•",
                          style: TextStyle(color: Colors.white38),
                        ),

                        const SizedBox(width: 6),

                        /// 🪑 MASA
                        Row(
                          children: [
                            const Icon(
                              Icons.table_bar,
                              size: 14,
                              color: Colors.white60,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              "$activeTables",
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),

        /// 🔥 BADGE (SAĞ ÜST)
        Positioned(top: -3, right: -3, child: _leagueMiniBadge(l)),
      ],
    );
  }

  IconData _leagueIcon(String id) {
    switch (id) {
      case 'standard':
        return Icons.star;
      case 'bronze':
        return Icons.extension; // puzzle hissi
      case 'silver':
        return Icons.build; // kalfa
      case 'gold':
        return Icons.workspace_premium; // usta
      case 'elite':
        return Icons.emoji_events; // şampiyon
      default:
        return Icons.circle;
    }
  }
}
