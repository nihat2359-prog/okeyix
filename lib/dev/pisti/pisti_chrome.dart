import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'pisti_cards.dart';
import 'pisti_model.dart';
import '../../ui/lobby/lobby_avatar.dart';
import '../../ui/game_world.dart';

class PistiSurface extends CustomPainter {
  const PistiSurface();
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = const Color(0xff071b13));
    final table = Rect.fromCenter(
      center: Offset(size.width * .54, size.height * .44),
      width: size.width * .92,
      height: size.height * 1.66,
    );
    canvas.drawOval(
      table,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(.1, -.2),
          radius: .85,
          colors: [Color(0xff245c40), Color(0xff143e2b), Color(0xff0b291d)],
        ).createShader(table),
    );
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8
      ..color = const Color(0x226b9875);
    canvas.drawOval(table.deflate(8), line);
    canvas.drawOval(table.deflate(15), line..color = const Color(0x096b9875));
    // Fine, deterministic woven marks; no ticker or per-frame noise generation.
    final grain = Paint()
      ..color = const Color(0x059ac69e)
      ..strokeWidth = .65;
    for (double y = 7; y < size.height; y += 8) {
      for (double x = 7; x < size.width; x += 13) {
        final shift = ((x.toInt() * 7 + y.toInt() * 3) % 5).toDouble();
        canvas.drawLine(
          Offset(x + shift, y),
          Offset(x + shift + 2, y + 1),
          grain,
        );
      }
    }
    final center = Offset(size.width * .535, size.height * .465);
    for (final radius in [size.height * .29, size.height * .34]) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -.55,
        1.1,
        false,
        line..color = const Color(0x128ab591),
      );
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        math.pi - .55,
        1.1,
        false,
        line,
      );
    }
    canvas.drawLine(
      Offset(0, size.height * .56),
      Offset(size.width * .155, size.height * .56),
      line..color = const Color(0x194c785a),
    );
    canvas.drawCircle(
      Offset(size.width * .155, size.height * .56),
      2,
      Paint()..color = const Color(0xff507b5c),
    );
  }

  @override
  bool shouldRepaint(PistiSurface old) => false;
}

class PistiPlayerBadge extends StatelessWidget {
  const PistiPlayerBadge({
    super.key,
    required this.seat,
    required this.score,
    required this.cards,
    required this.active,
    required this.compact,
    required this.thinking,
    this.name,
    this.avatarUrl,
    this.online = false,
    this.secondsLeft,
    this.isBot = false,
  });
  final PistiSeat seat;
  final int score, cards;
  final bool active, compact, thinking;
  final String? name;
  final String? avatarUrl;
  final bool online;
  final int? secondsLeft;
  final bool isBot;
  @override
  Widget build(BuildContext context) {
    final local = seat == PistiSeat.player;
    final accent = local ? pistiCoral : const Color(0xffb1c8ed);
    return LayoutBuilder(
      builder: (context, bounds) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: bounds.maxWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: compact ? 34 : 42,
                    height: compact ? 34 : 42,
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: active ? accent : const Color(0xff46546e),
                        width: active ? 1.5 : .8,
                      ),
                    ),
                    child: ClipOval(
                      child: name != null
                          ? LobbyAvatar(
                              username: name!,
                              avatarUrl: avatarUrl,
                              size: compact ? 29 : 37,
                            )
                          : Image.asset(
                              'assets/images/avatars/${local ? 'avatar2' : 'avatar6'}.png',
                              fit: BoxFit.cover,
                            ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            name ?? (local ? 'Deniz' : 'Ada'),
                            style: TextStyle(
                              color: pistiPaper,
                              fontWeight: FontWeight.w700,
                              fontSize: compact ? 13 : 15,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            children: [
                              Container(
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: active
                                      ? accent
                                      : const Color(0xff62728c),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                active
                                    ? (isBot
                                          ? 'BOT DÜŞÜNÜYOR'
                                          : secondsLeft != null
                                          ? '${local ? 'SIRA SENDE' : 'RAKİBİN SIRASI'} · $secondsLeft sn'
                                          : thinking
                                          ? 'DÜŞÜNÜYOR'
                                          : 'SIRA SENDE')
                                    : (local
                                          ? 'SEN'
                                          : online
                                          ? (name?.contains(' · BOT') == true
                                                ? 'BOT RAKİP'
                                                : 'ARKADAŞIN')
                                          : 'YEREL RAKİP'),
                                style: TextStyle(
                                  color:
                                      active &&
                                          !isBot &&
                                          secondsLeft != null &&
                                          secondsLeft! <= 5
                                      ? pistiCoral
                                      : active
                                      ? accent
                                      : pistiMuted,
                                  fontSize: secondsLeft != null
                                      ? (compact ? 9 : 10)
                                      : (compact ? 7 : 8),
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: .6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 6 : 9),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Text(
                        '$score',
                        key: ValueKey(score),
                        style: TextStyle(
                          color: pistiPaper,
                          fontSize: compact ? 24 : 30,
                          height: 1,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'PUAN',
                      style: TextStyle(
                        color: pistiMuted,
                        fontSize: compact ? 7 : 8,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '$cards',
                      style: TextStyle(
                        color: const Color(0xffcad5e6),
                        fontSize: compact ? 12 : 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      'kart',
                      style: TextStyle(
                        color: pistiMuted,
                        fontSize: compact ? 8 : 9,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PistiMoment extends StatelessWidget {
  const PistiMoment({
    super.key,
    required this.progress,
    required this.bonus,
    required this.player,
  });
  final double progress;
  final int bonus;
  final bool player;
  @override
  Widget build(BuildContext context) {
    final envelope = math.sin(math.pi * progress).clamp(0.0, 1.0);
    return IgnorePointer(
      child: Opacity(
        opacity: envelope,
        child: Transform.scale(
          scale: .9 + .1 * Curves.easeOutCubic.transform(progress),
          child: CustomPaint(
            painter: _PistiInkBloom(progress),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    player ? 'TAM İSABET' : 'GÜZEL HAMLE',
                    style: const TextStyle(
                      color: pistiPaper,
                      fontSize: 9,
                      letterSpacing: 3.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'PİŞTİ',
                    style: TextStyle(
                      color: pistiCoral,
                      fontSize: 42,
                      height: .95,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4 - progress * 2,
                      shadows: const [
                        Shadow(color: Color(0xff071a12), blurRadius: 20),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '+$bonus',
                    style: const TextStyle(
                      color: pistiPaper,
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PistiInkBloom extends CustomPainter {
  const _PistiInkBloom(this.progress);
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    final bounds = (Offset.zero & size).inflate(22);
    canvas.drawOval(
      bounds,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xff102f22), Color(0xf9102f22), Color(0x00102f22)],
          stops: [0, .64, 1],
        ).createShader(bounds),
    );
    final arc = Paint()
      ..color = pistiCoral.withValues(alpha: .48)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8;
    final ring = (Offset.zero & size).deflate(3);
    canvas.drawArc(ring, -math.pi * .9, math.pi * .8 * progress, false, arc);
    canvas.drawArc(ring, math.pi * .1, math.pi * .8 * progress, false, arc);
  }

  @override
  bool shouldRepaint(_PistiInkBloom old) => old.progress != progress;
}

class PistiResult extends StatelessWidget {
  const PistiResult({
    super.key,
    required this.game,
    required this.onReplay,
    this.names = const ['DENİZ', 'ADA'],
    this.online = false,
    this.replayEnabled = true,
    this.titleOverride,
  });
  final PistiGame game;
  final VoidCallback onReplay;
  final List<String> names;
  final bool online, replayEnabled;
  final String? titleOverride;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: online
            ? const [Color(0xff183527), Color(0xff07120d)]
            : const [Color(0xff071a12), Color(0xff071a12)],
      ),
    ),
    child: LayoutBuilder(
      builder: (context, c) {
        final compact = c.maxHeight < 330;
        final yours = game.score(PistiSeat.player),
            theirs = game.score(PistiSeat.opponent);
        final title =
            titleOverride ??
            (yours == theirs
                ? 'Dengeler eşit.'
                : yours > theirs
                ? 'Masa senin.'
                : 'Bir el daha?');
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: c.maxWidth * .09,
            vertical: compact ? 35 : 48,
          ),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: LayoutBuilder(
                  builder: (context, stage) {
                    final height = math.min(stage.maxHeight * .75, 164.0);
                    return Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: height * 1.35,
                          height: height * 1.35,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xff354664),
                              width: .8,
                            ),
                          ),
                        ),
                        for (var i = 0; i < 3; i++)
                          Transform.translate(
                            offset: Offset(
                              (i - 1) * height * .23,
                              (i - 1).abs() * 9,
                            ),
                            child: Transform.rotate(
                              angle: (i - 1) * .17,
                              child: SizedBox(
                                width: height * .70,
                                height: height,
                                child: PistiCardView(
                                  card: [
                                    const PistiCard(PistiSuit.clubs, 2),
                                    const PistiCard(PistiSuit.diamonds, 10),
                                    const PistiCard(PistiSuit.spades, 1),
                                  ][i],
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          bottom: 0,
                          child: Text(
                            '${game.won[PistiSeat.player]!.length} KART · ${game.pistis[PistiSeat.player]} PİŞTİ',
                            style: const TextStyle(
                              color: pistiMuted,
                              fontSize: 9,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(width: 28),
              Expanded(
                flex: 5,
                child: _fitResultPanel(
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        online ? 'MAÇ TAMAMLANDI' : 'EL TAMAMLANDI',
                        style: TextStyle(
                          color: online ? worldGold : pistiCoral,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2.5,
                        ),
                      ),
                      SizedBox(height: compact ? 8 : 13),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          title,
                          style: TextStyle(
                            color: pistiPaper,
                            fontSize: compact ? 30 : 42,
                            height: 1,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1.5,
                          ),
                        ),
                      ),
                      SizedBox(height: compact ? 12 : 22),
                      Row(
                        children: [
                          Flexible(
                            child: _resultScore(names[0], yours, compact),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Text(
                              '—',
                              style: TextStyle(
                                color: const Color(0xff54627c),
                                fontSize: compact ? 20 : 28,
                              ),
                            ),
                          ),
                          Flexible(
                            child: _resultScore(names[1], theirs, compact),
                          ),
                        ],
                      ),
                      SizedBox(height: compact ? 14 : 24),
                      SizedBox(
                        height: compact ? 38 : 46,
                        child: FilledButton.icon(
                          key: const ValueKey('pisti-replay'),
                          onPressed: replayEnabled ? onReplay : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: online ? worldGold : pistiCoral,
                            foregroundColor: const Color(0xff182239),
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.replay_rounded, size: 18),
                          label: Text(
                            online ? 'Rövanş iste' : 'Yeniden dağıt',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
  Widget _fitResultPanel(Widget child) => LayoutBuilder(
    builder: (_, bounds) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: SizedBox(width: bounds.maxWidth, child: child),
    ),
  );
  Widget _resultScore(String name, int points, bool compact) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: pistiMuted,
          fontSize: 8,
          letterSpacing: 1.5,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        '$points',
        style: TextStyle(
          color: pistiPaper,
          fontSize: compact ? 30 : 42,
          height: 1,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}
