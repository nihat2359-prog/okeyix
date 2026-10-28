import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../components/cached_decoration.dart';

class PreviewComponent extends PositionComponent
    with HasVisibility, CachedDecoration {
  PreviewComponent({required Vector2 size}) {
    this.size = size;
    anchor = Anchor.center;
  }

  @override
  void renderDecoration(Canvas canvas) {
    // A small contact shadow marks the landing point without drawing a second
    // tile-shaped card behind the real tile. It stays inside the existing bounds.
    final shadow = Rect.fromCenter(
      center: Offset(size.x * .5, size.y * .88),
      width: size.x * .72,
      height: size.y * .09,
    );
    canvas.drawOval(shadow, Paint()
      ..color = const Color(0x38000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
  }
}
