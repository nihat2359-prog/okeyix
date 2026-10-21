import 'dart:math' as math;
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

/// Separate transparent presentation game: no hit detection or gameplay state.
class TableGiftFlightGame extends FlameGame {
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    pauseEngine();
  }

  @override
  Color backgroundColor() => Colors.transparent;
  Future<void> fly({
    required String gift,
    required Offset from,
    required Offset to,
    required bool self,
  }) async {
    final sprite = await loadSprite('hediyeler/$gift.png');
    if (!isMounted) return;
    resumeEngine();
    final component = _GiftFlight(sprite, from, to, self);
    await add(component);
    await component.removed;
    pauseEngine();
  }
}

class _GiftFlight extends SpriteComponent {
  _GiftFlight(Sprite sprite, this.from, this.to, this.self)
    : super(sprite: sprite, anchor: Anchor.center) {
    size =
        sprite.originalSize *
        (84 / math.max(sprite.originalSize.x, sprite.originalSize.y));
    position = Vector2(from.dx, from.dy);
  }
  final Offset from, to;
  final bool self;
  double elapsed = 0;
  @override
  void update(double dt) {
    super.update(dt);
    elapsed += dt;
    final t = (elapsed / (self ? .55 : 1.05)).clamp(0.0, 1.0);
    final eased = Curves.easeInOutCubic.transform(t);
    final point = Offset.lerp(from, to, eased)!;
    position.setValues(
      point.dx,
      point.dy - (self ? 10 : 32) * 4 * eased * (1 - eased),
    );
    scale = Vector2.all(1 - (1 - 48 / 84) * Curves.easeOutCubic.transform(t));
    if (t >= 1) removeFromParent();
  }
}
