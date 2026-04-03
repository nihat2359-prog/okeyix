import 'package:flame/components.dart';
import 'package:flutter/material.dart';

class PreviewComponent extends PositionComponent with HasVisibility {
  PreviewComponent({required Vector2 size}) {
    this.size = size;
    anchor = Anchor.center;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final rect = Rect.fromLTWH(0, 0, size.x, size.y);

    final paint = Paint()
      ..color = const Color.fromARGB(255, 243, 216, 181)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(10)));

    final dashed = _createDashedPath(path, 10, 6);

    canvas.drawPath(dashed, paint);
  }

  Path _createDashedPath(Path source, double dashWidth, double dashSpace) {
    final dest = Path();

    for (final metric in source.computeMetrics()) {
      double distance = 0;

      while (distance < metric.length) {
        final next = distance + dashWidth;

        dest.addPath(metric.extractPath(distance, next), Offset.zero);

        distance = next + dashSpace;
      }
    }

    return dest;
  }
}
