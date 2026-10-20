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
                                    Container(
                                      width: 1,
                                      height: 24,
                                      color: gold.withValues(alpha: .35),
                                    ),
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
                                const SizedBox(height: 4),
                                Container(
                                  width: 160,
                                  height: 1,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.transparent,
                                        gold.withValues(alpha: .6),
                                        Colors.transparent,
                                      ],
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
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: compact ? 8 : 18),
                      child: SizedBox(
                        width: math.min(218, bounds.maxWidth * .55),
                        height: 46,
                        child: Material(
                          color: Colors.transparent,
                          child: Ink(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(23),
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0xE52C333B), Color(0xED10171E)],
                              ),
                              border: Border.all(
                                color: const Color(0x99D7BA7B),
                                width: .8,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x55000000),
                                  offset: Offset(0, 3),
                                  blurRadius: 5,
                                ),
                              ],
                            ),
                            child: InkWell(
                              key: const ValueKey('finish-leave'),
                              onTap: widget.leaving ? null : widget.onLeave,
                              borderRadius: BorderRadius.circular(23),
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
                                        Icon(
                                          widget.leaving
                                              ? Icons.hourglass_top_rounded
                                              : Icons.logout_rounded,
                                          color: const Color(0xFFE2C68C),
                                          size: 16,
                                        ),
                                        const SizedBox(width: 9),
                                        Text(
                                          widget.leaving
                                              ? 'Ayrılıyor...'
                                              : 'Masadan Ayrıl',
                                          style: const TextStyle(
                                            color: Color(0xFFF3E5C5),
                                            fontSize: 13,
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
