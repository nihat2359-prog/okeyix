import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class SkyPlanesOverlay extends StatefulWidget {
  final double skyHeightFactor;
  final int planeCount;
  final double horizontalInset;

  const SkyPlanesOverlay({
    super.key,
    this.skyHeightFactor = 0.36,
    this.planeCount = 4,
    this.horizontalInset = 0,
  });

  @override
  State<SkyPlanesOverlay> createState() => _SkyPlanesOverlayState();
}

/// Small three-quarter airliner; shaded metal and navigation lights, no exhaust flame.
class SkyAirlinerPainter extends CustomPainter {
  final double blink;
  const SkyAirlinerPainter({required this.blink});
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 42);
    final steel = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFE0E8EF), Color(0xFF8197AA), Color(0xFF43576B)],
      ).createShader(const Rect.fromLTWH(0, 6, 100, 30));
    final farWing = Path()
      ..moveTo(51, 19)
      ..lineTo(35, 7)
      ..lineTo(43, 8)
      ..lineTo(71, 19)
      ..close();
    canvas.drawPath(farWing, steel);
    final fin = Path()
      ..moveTo(10, 19)
      ..lineTo(7, 3)
      ..quadraticBezierTo(12, 3, 17, 6)
      ..lineTo(29, 19)
      ..close();
    canvas.drawPath(
      fin,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF394C64), Color(0xFF93A6B6)],
        ).createShader(const Rect.fromLTWH(7, 3, 22, 16)),
    );
    canvas.drawLine(
      const Offset(12, 7),
      const Offset(22, 17),
      Paint()
        ..color = const Color(0xFFB7C9D6)
        ..strokeWidth = 1.1,
    );
    final body = Path()
      ..moveTo(3, 18)
      ..cubicTo(25, 15, 70, 15, 86, 17)
      ..quadraticBezierTo(93, 18, 98, 21)
      ..quadraticBezierTo(98, 24, 86, 24)
      ..lineTo(9, 24)
      ..quadraticBezierTo(5, 23, 3, 18)
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF3F5F4), Color(0xFFBFCBD4), Color(0xFF667E91)],
          stops: [0, .48, 1],
        ).createShader(const Rect.fromLTWH(3, 15, 95, 10)),
    );
    canvas.drawPath(
      Path()
        ..moveTo(86, 18)
        ..lineTo(91, 19)
        ..lineTo(93, 21)
        ..lineTo(85, 20)
        ..close(),
      Paint()..color = const Color(0xFF263C50),
    );
    final windows = Paint()..color = const Color(0xFF365166);
    for (double x = 28; x < 82; x += 4.4) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 18.5, 1.5, 1.8),
          const Radius.circular(.5),
        ),
        windows,
      );
    }
    final nearWing = Path()
      ..moveTo(50, 21)
      ..lineTo(29, 37)
      ..lineTo(43, 34)
      ..lineTo(70, 22)
      ..close();
    canvas.drawPath(nearWing, steel);
    canvas.drawLine(
      const Offset(50, 22),
      const Offset(31, 36),
      Paint()
        ..color = const Color(0xFFDBE5EA)
        ..strokeWidth = .7,
    );
    canvas.drawPath(
      Path()
        ..moveTo(17, 22)
        ..lineTo(3, 29)
        ..lineTo(13, 28)
        ..lineTo(30, 23)
        ..close(),
      steel,
    );
    final engine = Rect.fromLTWH(49, 27, 13, 5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(engine, const Radius.circular(2)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFC9D3DB), Color(0xFF40586D)],
        ).createShader(engine),
    );
    canvas.drawOval(
      const Rect.fromLTWH(59, 27.2, 3, 4.5),
      Paint()..color = const Color(0xFF1D3040),
    );
    // Wingtip red/green lights are quiet; white strobe flashes briefly.
    canvas.drawCircle(
      const Offset(30, 36),
      .9,
      Paint()..color = const Color(0xFFE76D68),
    );
    canvas.drawCircle(
      const Offset(36, 8),
      .75,
      Paint()..color = const Color(0xFF8AC5AF),
    );
    if (blink > .88) {
      canvas.drawCircle(
        const Offset(6, 20),
        1.1,
        Paint()..color = Color.fromRGBO(238, 247, 255, (blink - .88) / .12),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SkyAirlinerPainter oldDelegate) =>
      oldDelegate.blink != blink;
}

class _SkyPlanesOverlayState extends State<SkyPlanesOverlay>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  double _elapsedSeconds = 0;
  int _lastFrameMicros = 0;
  double _elapsedBeforePause = 0;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _ticker = createTicker((elapsed) {
      if (!mounted) return;
      final micros = elapsed.inMicroseconds;
      // 30 FPS cap: ambient efekt için yeterli, CPU/GPU yükünü düşürür.
      if (micros - _lastFrameMicros < 33333) return;
      _lastFrameMicros = micros;
      setState(() {
        _elapsedSeconds = _elapsedBeforePause + micros / 1000000.0;
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncTicker();
  }

  void _syncTicker() {
    final visible = _foreground && TickerMode.of(context);
    if (visible && !_ticker.isActive) {
      _elapsedBeforePause = _elapsedSeconds;
      _lastFrameMicros = 0;
      _ticker.start();
    } else if (!visible && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true,
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final skyHeight = constraints.maxHeight * widget.skyHeightFactor;
            final count = widget.planeCount.clamp(2, 8);
            final inset = widget.horizontalInset.clamp(0, width / 3);
            final trackLeft = inset;
            final trackRight = width - inset;
            final trackWidth = (trackRight - trackLeft).clamp(1.0, width);

            return SizedBox.expand(
              child: Stack(
                children: List.generate(count, (i) {
                  final lane = i / math.max(1, count - 1);
                  // 2 hat kullanırken alt hattı fazla aşağı düşürme.
                  final laneFactor = count == 2
                      ? (i == 0 ? 0.10 : 0.34)
                      : (0.09 + (lane * 0.52));
                  final laneY = laneFactor * skyHeight;
                  final depth = 0.75 + (lane * 0.5);
                  final dir = i.isEven ? 1.0 : -1.0;
                  final speed =
                      0.045 + (i * 0.010); // çok daha yavaş, uzaktan süzülme
                  final phase = ((_elapsedSeconds * speed) + (i * 0.19)) % 1.0;
                  final x = dir > 0
                      ? (trackLeft + trackWidth * phase)
                      : (trackRight - trackWidth * phase);
                  final wobble =
                      math.sin((_elapsedSeconds * 0.7 * math.pi) + i) * 3.0;

                  final planeSize = 14.5 * depth;
                  final opacity = (0.30 + (0.16 * depth)).clamp(0.26, 0.55);
                  final blink =
                      (0.40 +
                              0.60 *
                                  ((math.sin(
                                            (_elapsedSeconds * 3.2) + (i * 1.7),
                                          ) +
                                          1) /
                                      2))
                          .clamp(0.0, 1.0);

                  return Positioned(
                    left: x,
                    top: laneY + wobble,
                    child: Opacity(
                      opacity: opacity,
                      child: Transform.flip(
                        flipX: dir < 0,
                        child: SizedBox(
                          width: planeSize * 1.8,
                          height: planeSize * .85,
                          child: CustomPaint(
                            painter: SkyAirlinerPainter(blink: blink),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            );
          },
        ),
      ),
    );
  }
}
