import 'dart:ui';

import 'package:flutter/material.dart';
import 'lobby_shimmer_loaders.dart';

class LobbyLeagueList extends StatelessWidget {
  final List<Map<String, dynamic>> leagues;
  final dynamic selectedLeagueId;
  final Map<String, int> leagueActivePlayers;
  final Map<String, int> leagueActiveTables;
  final Function(Map<String, dynamic>) onSelect;
  final int userCoin;
  final int userRating;
  final bool loading;
  const LobbyLeagueList({
    super.key,
    required this.leagues,
    required this.selectedLeagueId,
    required this.leagueActivePlayers,
    required this.leagueActiveTables,
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = MediaQuery.of(context).size;
        final isTablet = size.shortestSide >= 600;

        if (isTablet) {
          /// 🔥 TABLET → ALT ALTA (büyük kartlar)
          return Column(
            children: List.generate(leagues.length, (i) {
              return AnimatedLeagueItem(
                index: i,
                child: SizedBox(
                  width: double.infinity,
                  child: _leagueItem(leagues[i], isBig: true),
                ),
              );
            }),
          );
        }

        /// 🔥 MOBILE → 2x2 + 1
        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: AnimatedLeagueItem(
                    index: 0,
                    child: _leagueItem(leagues[0]),
                  ),
                ),
                Expanded(
                  child: AnimatedLeagueItem(
                    index: 1,
                    child: _leagueItem(leagues[1]),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: AnimatedLeagueItem(
                    index: 2,
                    child: _leagueItem(leagues[2]),
                  ),
                ),
                Expanded(
                  child: AnimatedLeagueItem(
                    index: 3,
                    child: _leagueItem(leagues[3]),
                  ),
                ),
              ],
            ),
            AnimatedLeagueItem(
              index: 4,
              child: SizedBox(
                width: double.infinity,
                child: _leagueItem(leagues[4], isBig: true),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _leagueItem(Map league, {bool isBig = false}) {
    final l = Map<String, dynamic>.from(league);

    final selected = l['id'] == selectedLeagueId;

    final color = _leagueColorById(l['id']);

    return GestureDetector(
      onTap: () => onSelect(l),

      child: AnimatedScale(
        scale: selected ? 1.04 : 1.0,
        duration: const Duration(milliseconds: 180),

        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),

          /// 🔥 GOLD BORDER (gradient)
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: selected
                  ? [
                      Color(0xFFC8A94E),
                      Color(0xFFE7C66A),
                      Color(0xFFFFF3A0),
                      Color(0xFFE7C66A),
                    ]
                  : [Color(0x55C8A94E), Color(0x88E7C66A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),

            boxShadow: [
              if (selected)
                BoxShadow(
                  color: const Color(0xFFFFD76A).withOpacity(0.4),
                  blurRadius: 30,
                  spreadRadius: 2,
                ),
            ],
          ),

          /// 🔥 BORDER KALINLIĞI
          padding: EdgeInsets.all(selected ? 2.2 : 1.2),

          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: isBig ? 65 : 56,

            padding: EdgeInsets.symmetric(
              horizontal: l['id'] == 'elite' ? 2 : 8,
              vertical: 6,
            ),

            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16), // 🔥 18 - padding

              gradient: LinearGradient(
                colors: selected
                    ? [Color(0xFF184A34), Color(0xFF071A12)]
                    : [Color(0xFF0F2A1E), Color(0xFF071A12)],
              ),

              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 8),
                const BoxShadow(
                  color: Color(0xFF0A3A28),
                  blurRadius: 30,
                  spreadRadius: -10,
                ),
              ],
            ),

            child: l['id'] == 'elite'
                ? _eliteCard(l, color, isBig)
                : _normalCard(l, color, isBig),
          ),
        ),
      ),
    );
  }

  Widget _leagueTitle(String text, Color color, {bool isBig = false}) {
    final fontSize = isBig ? 22.0 : 16.0;

    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          /// 🔥 ALT GÖLGE (depth)
          Transform.translate(
            offset: const Offset(0, 2),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: fontSize,
                letterSpacing: 0.7,
                color: Colors.black.withOpacity(0.9),
              ),
            ),
          ),

          /// 🔥 ANA METAL GOLD (white YOK)
          ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (bounds) => const LinearGradient(
              colors: [
                Color(0xFF7A5A1F), // 🔥 koyu altın (alt)
                Color(0xFFCFAE54), // 🔥 ana
                Color(0xFFE7C66A), // 🔥 parlak altın
                Color(0xFFCFAE54),
                Color(0xFF7A5A1F), // 🔥 tekrar koyu
              ],
              stops: [0.0, 0.35, 0.55, 0.75, 1.0],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ).createShader(bounds),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: fontSize,
                letterSpacing: 0.7,
                color: Colors.white, // shader için
              ),
            ),
          ),

          /// 🔥 GOLD GLOW (çok hafif)
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: fontSize,
              letterSpacing: 0.7,
              color: Colors.transparent,
              shadows: [
                Shadow(
                  color: const Color(0xFFE7C66A).withOpacity(0.35),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
        ],
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

  Widget _eliteCard(Map l, Color color, bool isBig) {
    final activePlayers = leagueActivePlayers[l['id']] ?? 0;
    final activeTables = leagueActiveTables[l['id']] ?? 0;

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
              opacity: 1, // 🔥 transparan (çok önemli)
              child: _goldTrophyIcon(size: 50),
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
                    const Icon(
                      Icons.people,
                      size: 14,
                      color: Color(0xFFFFD76A),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      "$activePlayers",
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 14,
                      ),
                    ),

                    const SizedBox(width: 6),
                    const Text("•", style: TextStyle(color: Colors.white38)),
                    const SizedBox(width: 6),

                    const Icon(
                      Icons.table_bar,
                      size: 14,
                      color: Color(0xFFFFD76A),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      "$activeTables",
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 14,
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

  Widget _goldTrophyIcon({double size = 50}) {
    return Stack(
      alignment: Alignment.center,
      children: [
        /// 🔥 ALT GÖLGE (derinlik)
        Transform.translate(
          offset: const Offset(0, 2),
          child: Icon(
            Icons.emoji_events,
            size: size,
            color: Colors.black.withOpacity(0.9),
          ),
        ),

        /// 🔥 ANA METAL GOLD
        ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => const LinearGradient(
            colors: [
              Color(0xFF7A5A1F), // koyu altın
              Color(0xFFCFAE54), // ana
              Color(0xFFE7C66A), // parlak
              Color(0xFFCFAE54),
              Color(0xFF7A5A1F),
            ],
            stops: [0.0, 0.35, 0.55, 0.75, 1.0],
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
          ).createShader(bounds),
          child: Icon(
            Icons.emoji_events,
            size: size,
            color: Colors.white, // shader için
          ),
        ),

        /// 🔥 GOLD GLOW
        Icon(
          Icons.emoji_events,
          size: size,
          color: Colors.transparent,
          shadows: [
            Shadow(
              color: const Color(0xFFE7C66A).withOpacity(0.5),
              blurRadius: 14,
            ),
          ],
        ),
      ],
    );
  }

  Widget _normalCard(Map l, Color color, bool isBig) {
    final selected = l['id'] == selectedLeagueId;
    final activePlayers = leagueActivePlayers[l['id']] ?? 0;
    final activeTables = leagueActiveTables[l['id']] ?? 0;

    return Row(
      children: [
        /// 🔥 SOL KUPA
        _leagueTrophy(l['id'], selected),

        /// 🔥 CONTENT
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _leagueTitle(l['name'] ?? '', color, isBig: isBig),

              Row(
                children: [
                  Expanded(
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.people,
                                size: 12,
                                color: Color(0xFFD4B85F),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                "$activePlayers",
                                style: const TextStyle(
                                  color: Color(0xFFB9C3BD),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(width: 2),

                          const Text(
                            "•",
                            style: TextStyle(color: Color(0x66FFFFFF)),
                          ),

                          const SizedBox(width: 2),

                          Row(
                            children: [
                              const Icon(
                                Icons.table_bar,
                                size: 12,
                                color: Color(0xFFD4B85F),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                "$activeTables",
                                style: const TextStyle(
                                  color: Color(0xFFB9C3BD),
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
        ),
      ],
    );
  }

  TrophyStyle _trophyStyle(String id) {
    switch (id) {
      case 'standard':
        return TrophyStyle(
          size: 20,
          colors: [
            Color(0xFF9CA3AF), // açık gri
            Color(0xFFD1D5DB),
          ],
          glow: 0,
        );

      case 'bronze': // artık bronze değil, darker silver
        return TrophyStyle(
          size: 24,
          colors: [
            Color(0xFF6B7280), // orta gri
            Color(0xFF9CA3AF),
            Color(0xFFD1D5DB),
          ],
          glow: 0,
        );

      case 'silver':
        return TrophyStyle(
          size: 28,
          colors: [
            Color(0xFF4B5563), // koyu steel
            Color(0xFF9CA3AF),
            Color(0xFFE5E7EB),
          ],
          glow: 2,
        );

      case 'gold': // ustalar (platinum hissi)
        return TrophyStyle(
          size: 32,
          colors: [
            Color(0xFF374151), // daha koyu
            Color(0xFF9CA3AF),
            Color(0xFFE5E7EB),
          ],
          glow: 4,
        );

      default:
        return TrophyStyle(
          size: 22,
          colors: [Color(0xFFCFAE54), Color(0xFFE7C66A)],
          glow: 0,
        );
    }
  }

  Widget _leagueTrophy(String id, bool selected) {
    final style = _trophyStyle(id);

    return SizedBox(
      width: 26,
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            /// 🔥 glow
            if (style.glow > 0)
              Icon(
                Icons.emoji_events,
                size: style.size,
                color: Colors.transparent,
                shadows: [
                  Shadow(
                    color: style.colors.last.withOpacity(0.5),
                    blurRadius: style.glow,
                  ),
                ],
              ),

            /// 🔥 gradient kupa
            ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (bounds) => LinearGradient(
                colors: style.colors,
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
              ).createShader(bounds),
              child: Icon(
                Icons.emoji_events,
                size: style.size,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AnimatedLeagueItem extends StatefulWidget {
  final Widget child;
  final int index;

  const AnimatedLeagueItem({
    super.key,
    required this.child,
    required this.index,
  });

  @override
  State<AnimatedLeagueItem> createState() => _AnimatedLeagueItemState();
}

class _AnimatedLeagueItemState extends State<AnimatedLeagueItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _opacity;
  late Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();

    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _opacity = Tween(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut));

    _offset = Tween(
      begin: const Offset(0, 0.08), // 🔥 aşağıdan gelsin
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

    Future.delayed(Duration(milliseconds: widget.index * 80), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}

class GoldBorderPainter extends CustomPainter {
  final double radius;
  final bool selected;

  GoldBorderPainter({required this.radius, required this.selected});

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = selected ? 2.2 : 1.2;

    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );

    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = LinearGradient(
        colors: selected
            ? [
                Color(0xFFC8A94E),
                Color(0xFFE7C66A),
                Color(0xFFFFF3A0),
                Color(0xFFE7C66A),
              ]
            : [Color(0x55C8A94E), Color(0x88E7C66A)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Offset.zero & size);

    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant GoldBorderPainter oldDelegate) {
    return oldDelegate.selected != selected;
  }
}

class TrophyStyle {
  final double size;
  final List<Color> colors;
  final double glow;

  TrophyStyle({required this.size, required this.colors, required this.glow});
}
