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

  static const _assetFolder = 'assets/images/lobby/leagues/';
  static const _assetNames = <String>[
    'acemiler',
    'ciraklar',
    'kalfalar',
    'ustalar',
    'sampiyonlar',
  ];

  static const _themes = <_LeagueTheme>[
    _LeagueTheme(Color(0xFFB56C2C), Color(0xFFF9CF7A), Color(0xFF402310)),
    _LeagueTheme(Color(0xFF7389A9), Color(0xFFE6F2FF), Color(0xFF162A42)),
    _LeagueTheme(Color(0xFFAF8B2F), Color(0xFFFFE39A), Color(0xFF263624)),
    _LeagueTheme(Color(0xFF9253C8), Color(0xFFE9B7FF), Color(0xFF27173E)),
    _LeagueTheme(Color(0xFF3CBA83), Color(0xFFFFE1A1), Color(0xFF13362D)),
  ];

  @override
  Widget build(BuildContext context) {
    if (loading) return const LobbyLoading();
    if (leagues.isEmpty) {
      return const Center(
        child: Text(
          'No leagues available',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, bounds) {
        final gap = (bounds.maxHeight * .025).clamp(3.0, 7.0);
        final count = leagues.length < 5 ? leagues.length : 5;
        return Column(
          children: [
            for (var row = 0; row < 3; row++) ...[
              if (row > 0) SizedBox(height: gap),
              Expanded(
                child: Row(
                  children: [
                    for (var col = 0; col < (row == 2 ? 1 : 2); col++) ...[
                      if (col > 0) SizedBox(width: gap),
                      Expanded(
                        child: row * 2 + col < count
                            ? _card(
                                leagues[row * 2 + col],
                                row * 2 + col,
                                row == 2,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _card(Map<String, dynamic> league, int index, bool wide) {
    final theme = _themes[index.clamp(0, 4)];
    final selected = league['id'] == selectedLeagueId;
    final players = leagueActivePlayers[league['id']] ?? 0;
    final tables = leagueActiveTables[league['id']] ?? 0;
    final unlocked =
        userCoin >= ((league['min_coin'] as num?)?.toInt() ?? 0) &&
        userRating >= ((league['min_rating'] as num?)?.toInt() ?? 0);

    return LayoutBuilder(
      builder: (context, box) {
        return Semantics(
          selected: selected,
          button: true,
          label:
              '${league['name']}, $players oyuncu, $tables masa, ${unlocked ? 'Açık' : 'Kilitli'}',
          child: Tooltip(
            message: unlocked
                ? '${league['name']}'
                : 'Gereken: ${league['min_coin']} coin · ${league['min_rating']} puan',
            child: Material(
              key: ValueKey('league-${league['id']}'),
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onSelect(Map<String, dynamic>.from(league)),
                borderRadius: BorderRadius.circular(13),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color.lerp(
                          theme.dark,
                          theme.base,
                          selected ? .32 : .12,
                        )!,
                        const Color(0xFF111921),
                      ],
                    ),
                    border: Border.all(
                      color: selected
                          ? theme.light
                          : theme.base.withOpacity(.46),
                      width: selected ? 1.8 : .9,
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: theme.base.withOpacity(.18),
                              blurRadius: 12,
                            ),
                          ]
                        : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(
                          '$_assetFolder${_assetNames[index]}_arka_plan.png',
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                          errorBuilder: (_, __, ___) =>
                              ColoredBox(color: theme.dark),
                        ),
                        // Keep text readable even over detailed background artwork.
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.black.withOpacity(.02),
                                Colors.black.withOpacity(.17),
                                Colors.black.withOpacity(.62),
                              ],
                              stops: const [0, .42, 1],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(4),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: SizedBox(
                              width: wide ? 280 : 150,
                              height: 64,
                              child: Row(
                                children: [
                                  Image.asset(
                                    '$_assetFolder${_assetNames[index]}_kupa.png',
                                    width: wide ? 56 : 36,
                                    height: 56,
                                    fit: BoxFit.contain,
                                    filterQuality: FilterQuality.medium,
                                    errorBuilder: (_, _, _) => _trophy(
                                      theme,
                                      wide ? 56 : 36,
                                      index == 4,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Flexible(
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              league['name']?.toString() ?? '',
                                              style: TextStyle(
                                                color: selected
                                                    ? theme.light
                                                    : const Color(0xFFF0E5D3),
                                                fontSize: wide ? 20 : 14,
                                                fontWeight: FontWeight.w900,
                                                shadows: const [
                                                  Shadow(
                                                    color: Colors.black87,
                                                    blurRadius: 4,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Flexible(
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.people_alt_rounded,
                                                  size: 11,
                                                  color: theme.light,
                                                ),
                                                const SizedBox(width: 3),
                                                Text(
                                                  '$players',
                                                  style: const TextStyle(
                                                    color: Color(0xFFE2E8DF),
                                                    fontSize: 11,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Icon(
                                                  Icons
                                                      .table_restaurant_rounded,
                                                  size: 11,
                                                  color: theme.light,
                                                ),
                                                const SizedBox(width: 3),
                                                Text(
                                                  '$tables',
                                                  style: const TextStyle(
                                                    color: Color(0xFFE2E8DF),
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  Icon(
                                    unlocked
                                        ? (selected
                                              ? Icons.check_circle_rounded
                                              : Icons.chevron_right_rounded)
                                        : Icons.lock_outline_rounded,
                                    size: 14,
                                    color: theme.light,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _trophy(_LeagueTheme theme, double size, bool champion) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [theme.base.withOpacity(.30), theme.dark.withOpacity(.12)],
        ),
      ),
      child: ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [theme.light, theme.base, theme.light],
        ).createShader(bounds),
        child: Icon(
          champion
              ? Icons.workspace_premium_rounded
              : Icons.emoji_events_rounded,
          size: size * .82,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _LeagueTheme {
  final Color base;
  final Color light;
  final Color dark;
  const _LeagueTheme(this.base, this.light, this.dark);
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
                Color(0xFF4D978A),
                Color(0xFFE7C66A),
                Color(0xFFC5F3E9),
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

class _SubtleNoisePainter extends CustomPainter {
  final double noiseOpacity;

  const _SubtleNoisePainter({required this.noiseOpacity});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withOpacity(noiseOpacity);
    for (int i = 0; i < 28; i++) {
      final dx = (size.width / 27) * i;
      final dy = (size.height / 9) * (i % 9);
      canvas.drawCircle(Offset(dx, dy), 0.6, p);
    }
  }

  @override
  bool shouldRepaint(covariant _SubtleNoisePainter oldDelegate) {
    return oldDelegate.noiseOpacity != noiseOpacity;
  }
}

class TrophyStyle {
  final double size;
  final List<Color> colors;
  final double glow;

  TrophyStyle({required this.size, required this.colors, required this.glow});
}
