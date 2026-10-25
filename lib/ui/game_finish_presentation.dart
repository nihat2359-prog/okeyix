import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:okeyix/core/format.dart';

/// Presentation only: result amounts and exit behavior belong to the game.
class GameFinishPresentation extends StatefulWidget {
  final bool winner, spectator, okeyFinish, doubleFinish, leaving;
  final int amount;
  final String winnerName;
  final VoidCallback onLeave;
  const GameFinishPresentation({
    super.key,
    required this.winner,
    required this.amount,
    required this.onLeave,
    this.spectator = false,
    this.okeyFinish = false,
    this.doubleFinish = false,
    this.leaving = false,
    this.winnerName = '',
  });

  @override
  State<GameFinishPresentation> createState() => _GameFinishPresentationState();
}

class _GameFinishPresentationState extends State<GameFinishPresentation>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _celebration;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _celebration = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      if (widget.winner &&
          !widget.spectator &&
          !MediaQuery.disableAnimationsOf(context)) {
        _celebration.forward();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _celebration.reset();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _celebration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final win = widget.winner && !widget.spectator;
    final gold = win ? const Color(0xFFF3D68D) : const Color(0xFFD8DBE2);
    final title = widget.spectator
        ? '${widget.winnerName} kazandı'
        : win
        ? 'KAZANDIN'
        : 'KAYBETTİN';
    final badge = widget.spectator
        ? 'EL SONUCU'
        : win
        ? widget.okeyFinish
              ? 'OKEYLİ BİTİŞ'
              : widget.doubleFinish
              ? 'ÇİFTE BİTİŞ'
              : 'GÜZEL OYUN'
        : 'YENİ EL, YENİ BİR ŞANS';
    return Stack(
      children: [
        if (win)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  key: const ValueKey('finish-coins'),
                  painter: _VictoryCoins(
                    _celebration,
                    special: widget.okeyFinish || widget.doubleFinish,
                  ),
                ),
              ),
            ),
          ),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, bounds) {
              final compact = bounds.maxHeight < 400;
              return Stack(
                children: [
                  Positioned(
                    top: compact ? 2 : 10,
                    left: 16,
                    right: 16,
                    child: IgnorePointer(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: math.min(520, bounds.maxWidth * .86),
                            maxHeight: bounds.maxHeight * .23,
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Column(
                              children: [
                                Text(
                                  badge,
                                  style: TextStyle(
                                    color: gold.withValues(alpha: .75),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 2,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      title,
                                      style: TextStyle(
                                        color: gold,
                                        fontFamily: 'Montserrat',
                                        fontSize: compact ? 23 : 29,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1,
                                        shadows: const [
                                          Shadow(
                                            color: Colors.black,
                                            offset: Offset(0, 2),
                                            blurRadius: 3,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 18),
                                    const SizedBox(width: 16),
                                    if (win)
                                      const Padding(
                                        padding: EdgeInsets.only(right: 6),
                                        child: CustomPaint(
                                          size: Size(23, 23),
                                          painter: _ResultCoin(),
                                        ),
                                      ),
                                    Text(
                                      '${widget.amount >= 0 ? '+' : '−'}${Format.coin(widget.amount.abs())}',
                                      key: const ValueKey('finish-amount'),
                                      style: TextStyle(
                                        color: gold,
                                        fontFamily: 'Montserrat',
                                        fontSize: compact ? 25 : 32,
                                        fontWeight: FontWeight.w800,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: compact ? 8 : 18),
                      child: SizedBox(
                        width: math.min(236, bounds.maxWidth * .55),
                        height: 48,
                        child: Material(
                          color: Colors.transparent,
                          child: Ink(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                stops: [0, .12, .52, 1],
                                colors: [
                                  Color(0xFF3D5045),
                                  Color(0xF5253C32),
                                  Color(0xF5162A23),
                                  Color(0xFF0C1915),
                                ],
                              ),
                              border: Border.all(
                                color: const Color(0xD9CBA65E),
                                width: 1.1,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0xAA000000),
                                  offset: Offset(0, 4),
                                  blurRadius: 9,
                                ),
                                BoxShadow(
                                  color: Color(0x294D3B19),
                                  offset: Offset(0, 1),
                                  blurRadius: 2,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: InkWell(
                              key: const ValueKey('finish-leave'),
                              onTap: widget.leaving ? null : widget.onLeave,
                              borderRadius: BorderRadius.circular(14),
                              splashColor: const Color(0x33E0BD76),
                              highlightColor: const Color(0x18E0BD76),
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(7),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(9),
                                            gradient: const LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [Color(0xFFF3D89A), Color(0xFFB58A43)],
                                            ),
                                            border: Border.all(color: const Color(0xFFFFE8AE), width: .6),
                                          ),
                                          child: Icon(
                                            widget.leaving
                                                ? Icons.hourglass_top_rounded
                                                : Icons.logout_rounded,
                                            color: const Color(0xFF26362B),
                                            size: 17,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          widget.leaving
                                              ? 'Ayrılıyor...'
                                              : 'Masadan Ayrıl',
                                          style: const TextStyle(
                                            color: Color(0xFFF3E5C5),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: .3,
                                          ),
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
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ResultCoin extends CustomPainter {
  final double opacity;
  const _ResultCoin({this.opacity = 1});
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero), r = size.shortestSide / 2;
    canvas.drawCircle(
      c.translate(0, 1.4),
      r - 1,
      Paint()..color = const Color(0xFF775022).withValues(alpha: opacity),
    );
    canvas.drawCircle(
      c,
      r - 1,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFFFF0B9).withValues(alpha: opacity),
            const Color(0xFFD2A548).withValues(alpha: opacity),
            const Color(0xFF916025).withValues(alpha: opacity),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawCircle(
      c,
      r * .69,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8
        ..color = const Color(0xFF9A6B2F).withValues(alpha: opacity),
    );
    final mark = Path()
      ..moveTo(c.dx, c.dy - r * .45)
      ..lineTo(c.dx + r * .27, c.dy)
      ..lineTo(c.dx, c.dy + r * .45)
      ..lineTo(c.dx - r * .27, c.dy)
      ..close();
    canvas.drawPath(
      mark,
      Paint()..color = const Color(0xFFFFE4A2).withValues(alpha: opacity),
    );
  }

  @override
  bool shouldRepaint(covariant _ResultCoin oldDelegate) => false;
}

class _VictoryCoins extends CustomPainter {
  final Animation<double> animation;
  final bool special;
  _VictoryCoins(this.animation, {required this.special})
    : super(repaint: animation);
  @override
  void paint(Canvas canvas, Size size) {
    final value = animation.value;
    if (value <= 0 || value >= 1) return;
    final count = special ? 38 : 24;
    for (var i = 0; i < count; i++) {
      final t = ((value - (i % 6) * .025) / .84).clamp(0.0, 1.0);
      if (t <= 0 || t >= 1) continue;
      final direction = (i.isEven ? -1.0 : 1.0);
      final speed = .24 + (i % 7) * .07;
      final x = size.width * (.5 + direction * speed * t);
      final y = size.height * (.64 - (1.3 + (i % 5) * .16) * t + 1.65 * t * t);
      final radius = 6.0 + (i % 4) * 2.3;
      final opacity = math.min(t * 10, (1 - t) * 5).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(direction * t * 4 + i);
      canvas.scale(.55 + .45 * (math.cos(t * 8 + i)).abs(), 1);
      canvas.translate(-radius, -radius);
      _ResultCoin(opacity: opacity).paint(canvas, Size(radius * 2, radius * 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _VictoryCoins oldDelegate) =>
      animation != oldDelegate.animation || special != oldDelegate.special;
}
