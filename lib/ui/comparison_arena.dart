import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:okeyix/models/player_comparison.dart';
import 'package:okeyix/ui/lobby/lobby_avatar.dart';

const comparisonGold = Color(0xFFE8CA8C);
const comparisonJade = Color(0xFF9BD6BC);

class ComparisonArena extends StatelessWidget {
  const ComparisonArena({super.key, required this.data, this.story = false});
  final PlayerComparison data;
  final bool story;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final compact = bounds.maxHeight < 150 && !story;
      final avatar = story ? 40.0 : (bounds.maxHeight * .23).clamp(23.0, 50.0);
      final tied = data.leftWins == data.rightWins;
      return Row(
        children: [
          Expanded(
            flex: 3,
            child: _player(
              data.left,
              avatar,
              comparisonGold,
              data.leftWins > data.rightWins,
            ),
          ),
          Expanded(
            flex: 4,
            child: LayoutBuilder(
              builder: (context, space) => FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: space.maxWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (!compact)
                        Text(
                          'BİRBİRİNİZE KARŞI',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: comparisonGold,
                            fontSize: story ? 9 : 10,
                            letterSpacing: 1.4,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Expanded(
                            child: _score(
                              data.leftWins,
                              tied ? const Color(0xFFE7E7DB) : comparisonGold,
                              compact,
                            ),
                          ),
                          SizedBox(
                            width: story ? 28 : 42,
                            height: story ? 28 : 34,
                            child: CustomPaint(
                              painter: const _VsEmblem(),
                              child: Center(
                                child: Text(
                                  'VS',
                                  style: TextStyle(
                                    color: comparisonGold,
                                    fontSize: story ? 11 : 13,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: _score(
                              data.rightWins,
                              tied
                                  ? const Color(0xFFE7E7DB)
                                  : data.rightWins > data.leftWins
                                  ? comparisonGold
                                  : comparisonJade,
                              compact,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      if (!story) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: SizedBox(
                            height: 4,
                            child: data.meetings == 0
                                ? const ColoredBox(color: Color(0xFF43504B))
                                : Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if (data.leftWins > 0)
                                        Expanded(
                                          flex: data.leftWins,
                                          child: const ColoredBox(
                                            color: comparisonGold,
                                          ),
                                        ),
                                      if (data.rightWins > 0)
                                        Expanded(
                                          flex: data.rightWins,
                                          child: const ColoredBox(
                                            color: comparisonJade,
                                          ),
                                        ),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              data.meetings == 0
                                  ? '—'
                                  : '%${(data.leftShare * 100).toStringAsFixed(0)}',
                              style: const TextStyle(
                                color: comparisonGold,
                                fontSize: 9,
                              ),
                            ),
                            Text(
                              data.meetings == 0
                                  ? '—'
                                  : '%${((1 - data.leftShare) * 100).toStringAsFixed(0)}',
                              style: const TextStyle(
                                color: comparisonJade,
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                      ],
                      Text(
                        data.resultLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: story ? 9 : 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: _player(
              data.right,
              avatar,
              comparisonJade,
              data.rightWins > data.leftWins,
            ),
          ),
        ],
      );
    },
  );

  Widget _score(int value, Color color, bool compact) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        '$value',
        style: TextStyle(
          fontSize: story
              ? 38
              : compact
              ? 38
              : 68,
          color: color,
          fontWeight: FontWeight.w900,
          height: 1.05,
          shadows: [
            Shadow(color: color.withValues(alpha: .15), blurRadius: 12),
          ],
        ),
      ),
    ),
  );

  Widget _player(
    ComparedPlayer player,
    double radius,
    Color color,
    bool leading,
  ) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 5),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: radius * 2 + 6,
          height: radius * 2 + 6,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: leading ? comparisonGold : const Color(0xFF70837C),
              width: leading ? 1.6 : .8,
            ),
            boxShadow: [
              if (leading)
                BoxShadow(
                  color: comparisonGold.withValues(alpha: .24),
                  blurRadius: 22,
                ),
            ],
          ),
          child: ClipOval(
            child: ColoredBox(
              color: const Color(0xFF172820),
              child: LobbyAvatar(
                username: player.name,
                avatarUrl: player.avatar,
                size: radius,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          player.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: story
                ? 11
                : radius < 35
                ? 13
                : 16,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          player.league ?? 'Lig bilgisi yok',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color, fontSize: 10),
        ),
      ],
    ),
  );
}

class _VsEmblem extends CustomPainter {
  const _VsEmblem();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(math.pi / 4);
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: size.shortestSide * .72,
      height: size.shortestSide * .72,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()..color = const Color(0xFF2F3326),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = comparisonGold.withValues(alpha: .65),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _VsEmblem oldDelegate) => false;
}

class ComparisonTotals extends StatelessWidget {
  const ComparisonTotals({super.key, required this.data});
  final PlayerComparison data;
  @override
  Widget build(BuildContext context) {
    final a = data.left.stats;
    final b = data.right.stats;
    final values = [
      ('Galibiyet', a.wins.toDouble(), b.wins.toDouble(), false, false),
      ('Mağlubiyet', a.losses.toDouble(), b.losses.toDouble(), true, false),
      ('Kazanma oranı', a.winRate, b.winRate, false, true),
      (
        'Normal bitiş',
        a.normalWins.toDouble(),
        b.normalWins.toDouble(),
        false,
        false,
      ),
      (
        'Okeyli bitiş',
        a.okeyWins.toDouble(),
        b.okeyWins.toDouble(),
        false,
        false,
      ),
      (
        'Çiftli bitiş',
        a.doubleWins.toDouble(),
        b.doubleWins.toDouble(),
        false,
        false,
      ),
    ];
    return LayoutBuilder(
      builder: (context, bounds) => Column(
        children: [
          for (var row = 0; row < 2; row++) ...[
            if (row > 0) const SizedBox(height: 5),
            Expanded(
              child: Row(
                children: [
                  for (var col = 0; col < 3; col++) ...[
                    if (col > 0) const SizedBox(width: 6),
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final item = values[row * 3 + col];
                          final comparable =
                              (!item.$4 && !item.$5) ||
                              (a.total > 0 && b.total > 0);
                          final leftBetter =
                              comparable &&
                              (item.$4 ? item.$2 < item.$3 : item.$2 > item.$3);
                          final rightBetter =
                              comparable &&
                              (item.$4 ? item.$3 < item.$2 : item.$3 > item.$2);
                          String value(double n) => item.$5
                              ? '%${n.toStringAsFixed(1)}'
                              : n.toInt().toString();
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xC0182928),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0x336B7154),
                                width: .6,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  item.$1,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 11,
                                  ),
                                ),
                                Expanded(
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            value(item.$2),
                                            style: TextStyle(
                                              color: leftBetter
                                                  ? comparisonGold
                                                  : Colors.white70,
                                              fontSize: 22,
                                              fontWeight: leftBetter
                                                  ? FontWeight.w900
                                                  : FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const Text(
                                        '·',
                                        style: TextStyle(color: Colors.white24),
                                      ),
                                      Expanded(
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerRight,
                                          child: Text(
                                            value(item.$3),
                                            style: TextStyle(
                                              color: rightBetter
                                                  ? comparisonJade
                                                  : Colors.white70,
                                              fontSize: 22,
                                              fontWeight: rightBetter
                                                  ? FontWeight.w900
                                                  : FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
