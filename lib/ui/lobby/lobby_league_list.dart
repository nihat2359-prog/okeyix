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

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      physics: const BouncingScrollPhysics(),
      itemCount: leagues.length,
      itemBuilder: (context, i) {
        final league = leagues[i];

        final selected = league['id'] == selectedLeagueId;
        final activePlayers = leagueActivePlayers[league['id']] ?? 0;
        final entryCoin = league['entry_coin'] ?? 0;
        final minRating = league['min_rating'] ?? 0;
        final locked = userCoin < entryCoin || userRating < minRating;
        final color = _leagueColor(league['icon']?.toString() ?? '');

        return GestureDetector(
          onTap: locked ? null : () => onSelect(league),

          child: Opacity(
            opacity: locked ? 0.55 : 1,

            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),

              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),

              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),

                color: selected
                    ? const Color(0x221E3A28)
                    : const Color(0x22111111),

                border: Border.all(
                  color: selected ? color : const Color(0x33FFFFFF),
                  width: selected ? 2 : 1,
                ),

                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: color.withOpacity(0.45),
                          blurRadius: 18,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),

              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  /// ANA KART
                  Row(
                    children: [
                      const SizedBox(width: 50), // 👈 boşluk bırakıyoruz

                      const SizedBox(width: 14),

                      /// TEXTS
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            /// LEAGUE NAME
                            Text(
                              league['name'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                letterSpacing: 0.3,
                              ),
                            ),

                            const SizedBox(height: 6),

                            /// STATS
                            Row(
                              children: [
                                _stat(
                                  Icons.monetization_on,
                                  entryCoin,
                                  2500,
                                  Colors.amber,
                                ),

                                const SizedBox(width: 12),

                                _stat(
                                  Icons.star,
                                  minRating,
                                  2500,
                                  Colors.orange,
                                ),

                                const SizedBox(width: 12),

                                _stat1(
                                  Icons.people,
                                  "$activePlayers",
                                  Colors.white70,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      /// 🔥 BADGE (DIŞARI TAŞAN)
                    ],
                  ),
                  Positioned(
                    left: -6,
                    top: -22, // 👈 yukarı taşıma
                    child: _leagueBadgeWidget(
                      league['name'] ?? '',
                      color,
                      selected,
                    ),
                  ),

                  /// LOCK OVERLAY (AAA placement)
                  if (locked)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xCC000000),
                        ),
                        child: const Icon(
                          Icons.lock,
                          size: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _stat1(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white70,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _stat(IconData icon, int value, int max, Color color) {
    final progress = (value / max).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              value.toString(),
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          width: 60,
          height: 7,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x331D2C24), Color(0x66455E52)],
            ),
            border: Border.all(color: const Color(0x3DFFFFFF), width: 0.6),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                FractionallySizedBox(
                  widthFactor: progress,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          color.withOpacity(0.55),
                          color,
                          color.withOpacity(0.88),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: color.withOpacity(0.55),
                          blurRadius: 8,
                          spreadRadius: 0.8,
                        ),
                      ],
                    ),
                  ),
                ),
                if (progress > 0)
                  FractionallySizedBox(
                    widthFactor: progress,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        height: 1.4,
                        color: Colors.white.withOpacity(0.28),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
  Widget _leagueBadgeWidget(String name, Color color, bool selected) {
    return SizedBox(
      width: 66,
      height: 66,
      child: Stack(
        alignment: Alignment.center,
        children: [
          /// Glow ring
          if (selected)
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.55),
                    blurRadius: 18,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),

          /// Badge image
          Image.asset(
            _leagueBadge(name),
            width: 66,
            height: 66,
            fit: BoxFit.contain,
          ),
        ],
      ),
    );
  }

  Color _leagueColor(String type) {
    switch (type) {
      case "workspace":
        return const Color(0xFFCD7F32); // bronze

      case "military":
        return const Color(0xFFC0C0C0); // silver

      case "emoji":
        return const Color(0xFFE7B95A); // gold

      case "auto":
        return const Color(0xFF8A63FF); // elite

      default:
        return const Color(0xFFE7B95A);
    }
  }

  String _leagueBadge(String name) {
    final n = name.toLowerCase();

    if (n.contains("Standart")) return "assets/images/lobby/standart.png";
    if (n.contains("bronz")) return "assets/images/lobby/bronz.png";
    if (n.contains("gümüş")) return "assets/images/lobby/gumus.png";
    if (n.contains("altın")) return "assets/images/lobby/altin.png";
    if (n.contains("elit")) return "assets/images/lobby/elit.png";

    return "assets/images/lobby/standart.png";
  }
}

