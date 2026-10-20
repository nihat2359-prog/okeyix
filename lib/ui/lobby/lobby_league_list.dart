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
        final padding = box.maxWidth < 150 || box.maxHeight < 70 ? 6.0 : 10.0;
        final trophySize = (box.maxWidth * (wide ? .16 : .18)).clamp(
          22.0,
          (box.maxHeight * .64).clamp(22.0, wide ? 56.0 : 40.0),
        );
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
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      selected
                          ? const Color(0x8C202127)
                          : const Color(0x7013161D),
                      const Color(0x99101319),
                    ],
                  ),
                  border: Border.all(
                    color: selected
                        ? const Color(0xCCD8B877)
                        : const Color(0x38CBD0DC),
                    width: 1,
                  ),
                ),
                child: InkWell(
                  onTap: () => onSelect(Map<String, dynamic>.from(league)),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: EdgeInsets.all(padding),
                    child: Row(
                      children: [
                        SizedBox(
                          width: trophySize,
                          height: trophySize,
                          child: CustomPaint(
                            painter: _LeagueCupPainter(theme, wide),
                          ),
                        ),
                        SizedBox(width: wide ? 12 : 6),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Flexible(
                                flex: 3,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          league['name']?.toString() ?? '',
                                          style: TextStyle(
                                            color: const Color(0xFFF1E9D8),
                                            fontSize: wide ? 17 : 13,
                                            height: 1.15,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    if (!unlocked)
                                      const Icon(
                                        Icons.lock_outline_rounded,
                                        size: 13,
                                        color: Color(0xFF9EAEA4),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 5),
                              Flexible(
                                flex: 2,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.people_alt_outlined,
                                        size: 12,
                                        color: theme.light,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        '$players',
                                        style: const TextStyle(
                                          color: Color(0xFFC3D0C9),
                                          fontSize: 11,
                                        ),
                                      ),
                                      SizedBox(width: wide ? 16 : 8),
                                      Icon(
                                        Icons.table_restaurant_outlined,
                                        size: 12,
                                        color: theme.light,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        '$tables',
                                        style: const TextStyle(
                                          color: Color(0xFFC3D0C9),
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
}

/// One metalwork language across all five tiers. No image backgrounds or glow.
class _LeagueCupPainter extends CustomPainter {
  final _LeagueTheme theme;
  final bool champion;
  const _LeagueCupPainter(this.theme, this.champion);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48, size.height / 56);
    canvas.drawOval(
      const Rect.fromLTWH(8, 51, 32, 3),
      Paint()..color = const Color(0x55000000),
    );
    final rim = Paint()
      ..color = theme.base
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(12, 10)
        ..lineTo(5, 10)
        ..cubicTo(3, 25, 10, 29, 17, 28),
      rim,
    );
    canvas.drawPath(
      Path()
        ..moveTo(36, 10)
        ..lineTo(43, 10)
        ..cubicTo(45, 25, 38, 29, 31, 28),
      rim,
    );
    final metal = Paint()
      ..shader = LinearGradient(
        colors: [
          theme.dark,
          theme.base,
          theme.light,
          theme.base,
          theme.dark,
          theme.light,
        ],
        stops: const [0, .16, .32, .56, .86, 1],
      ).createShader(const Rect.fromLTWH(10, 6, 28, 45));
    final bowl = Path()
      ..moveTo(11, 8)
      ..lineTo(37, 8)
      ..lineTo(34, 25)
      ..quadraticBezierTo(32, 34, 24, 35)
      ..quadraticBezierTo(16, 34, 14, 25)
      ..close();
    canvas.drawPath(bowl, metal);
    canvas.drawPath(
      bowl,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .7
        ..color = theme.light.withValues(alpha: .7),
    );
    // Curved fluting and a narrow specular strip follow the bowl's volume.
    final engraving = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .65
      ..color = theme.dark.withValues(alpha: .55);
    for (final x in [17.0, 24.0, 31.0]) {
      canvas.drawPath(
        Path()
          ..moveTo(x, 11)
          ..quadraticBezierTo(x, 27, 24 + (x - 24) * .4, 32),
        engraving,
      );
    }
    canvas.drawPath(
      Path()
        ..moveTo(15, 11)
        ..quadraticBezierTo(16, 27, 21, 31),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = theme.light.withValues(alpha: .8),
    );
    canvas.drawOval(const Rect.fromLTWH(10.5, 5.5, 27, 5), metal);
    canvas.drawOval(
      const Rect.fromLTWH(13, 6.5, 22, 2.3),
      Paint()..color = theme.dark,
    );
    canvas.drawArc(
      const Rect.fromLTWH(10.5, 5.5, 27, 5),
      0,
      3.14159,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .9
        ..color = theme.light,
    );
    final handleHighlight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8
      ..strokeCap = StrokeCap.round
      ..color = theme.light;
    canvas.drawPath(
      Path()
        ..moveTo(10, 11)
        ..lineTo(6, 11)
        ..cubicTo(5, 20, 9, 25, 13, 25),
      handleHighlight,
    );
    canvas.drawPath(
      Path()
        ..moveTo(38, 11)
        ..lineTo(42, 11)
        ..cubicTo(43, 20, 39, 25, 35, 25),
      handleHighlight,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(21, 33, 6, 10),
        const Radius.circular(1),
      ),
      metal,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(13, 43, 22, 5),
        const Radius.circular(2),
      ),
      metal,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(10, 49, 28, 3),
        const Radius.circular(1),
      ),
      metal,
    );
    canvas.drawLine(
      const Offset(12, 8),
      const Offset(36, 8),
      Paint()
        ..color = theme.light
        ..strokeWidth = 2,
    );
    final star = Path();
    const points = [
      Offset(24, 15),
      Offset(26, 20),
      Offset(31, 20),
      Offset(27, 24),
      Offset(28, 29),
      Offset(24, 26),
      Offset(20, 29),
      Offset(21, 24),
      Offset(17, 20),
      Offset(22, 20),
    ];
    star.addPolygon(points, true);
    canvas.drawOval(
      const Rect.fromLTWH(17, 16, 14, 14),
      Paint()..color = theme.dark.withValues(alpha: .85),
    );
    canvas.drawOval(
      const Rect.fromLTWH(17, 16, 14, 14),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .7
        ..color = theme.light,
    );
    canvas.save();
    canvas.translate(0, .8);
    canvas.drawPath(star, Paint()..color = theme.dark);
    canvas.restore();
    canvas.save();
    canvas.translate(24, 22);
    canvas.scale(.72);
    canvas.translate(-24, -22);
    canvas.drawPath(star, Paint()..color = theme.light);
    canvas.restore();
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(18, 44, 12, 3),
        const Radius.circular(.5),
      ),
      Paint()..color = theme.dark,
    );
    canvas.drawLine(
      const Offset(20, 45.5),
      const Offset(28, 45.5),
      Paint()
        ..color = theme.light
        ..strokeWidth = .65,
    );
    if (champion) {
      canvas.drawLine(const Offset(7, 36), const Offset(11, 43), rim);
      canvas.drawLine(const Offset(41, 36), const Offset(37, 43), rim);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LeagueCupPainter oldDelegate) =>
      oldDelegate.theme != theme || oldDelegate.champion != champion;
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
