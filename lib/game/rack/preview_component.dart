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
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));

    final fill = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x2AF2C14E), Color(0x12F2C14E)],
      ).createShader(rect);
    canvas.drawRRect(rrect, fill);

    final outerGlow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0x99F2C14E);
    canvas.drawRRect(rrect, outerGlow);

    final innerEdge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xCCFFF4D0);
    canvas.drawRRect(rrect.deflate(2), innerEdge);

    final topShineRect = Rect.fromLTWH(0, 0, size.x, size.y * 0.42);
    final topShine = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)],
      ).createShader(topShineRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(topShineRect, const Radius.circular(12)),
      topShine,
    );
  }
}
