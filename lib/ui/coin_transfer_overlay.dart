import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A bounded, one-shot flight. Painting alone listens to the controller.
class CoinTransferOverlay extends StatelessWidget {
  final Animation<double> progress;
  final Offset source, destination;
  const CoinTransferOverlay({
    super.key,
    required this.progress,
    required this.source,
    required this.destination,
  });

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(
        painter: _TransferPainter(progress, source, destination),
        child: const SizedBox.expand(),
      ),
    ),
  );
}

class _TransferPainter extends CustomPainter {
  final Animation<double> progress;
  final Offset source, destination;
  _TransferPainter(this.progress, this.source, this.destination)
    : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    final value = progress.value;
    if (value <= 0 || value >= 1) return;
    for (var i = 0; i < 8; i++) {
      final t = ((value - i * .035) / .72).clamp(0.0, 1.0);
      if (t <= 0 || t >= 1) continue;
      final eased = Curves.easeInOutCubic.transform(t);
      final start = source + Offset((i % 3 - 1) * 15, (i % 2) * 10);
      final control = Offset(
        (start.dx + destination.dx) / 2 + 35,
        start.dy - 60,
      );
      final point =
          start * ((1 - eased) * (1 - eased)) +
          control * (2 * (1 - eased) * eased) +
          destination * (eased * eased);
      final radius = 6.0 * (1 - .45 * eased);
      final opacity = (math.min(t * 8, (1 - t) * 10)).clamp(0.0, 1.0);
      final rect = Rect.fromCircle(center: point, radius: radius);
      canvas.drawCircle(
        point.translate(0, 1),
        radius,
        Paint()
          ..color = const Color(0xAA65471B).withValues(alpha: opacity * .65),
      );
      canvas.drawCircle(
        point,
        radius,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFFFEDB7).withValues(alpha: opacity),
              const Color(0xFFC7973D).withValues(alpha: opacity),
            ],
          ).createShader(rect),
      );
      canvas.drawCircle(
        point,
        radius * .7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .7
          ..color = const Color(0xFF8D6329).withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TransferPainter old) =>
      old.progress != progress ||
      old.source != source ||
      old.destination != destination;
}
