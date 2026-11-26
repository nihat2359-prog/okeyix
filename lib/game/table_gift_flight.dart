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
    final component = _GiftFlight(sprite, from, to, self);
    if (!isMounted) return;
    resumeEngine();
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
    _advanceFlight(this, from, to, self, elapsed);
  }
}

void _advanceFlight(
  PositionComponent component,
  Offset from,
  Offset to,
  bool self,
  double elapsed,
) {
  final t = (elapsed / (self ? .55 : 1.05)).clamp(0.0, 1.0);
  final point = tableGiftFlightPoint(from, to, t, self: self);
  component.position.setValues(point.dx, point.dy);
  component.scale = Vector2.all(
    1 - (1 - 48 / 84) * Curves.easeOutCubic.transform(t),
  );
  if (t >= 1) component.removeFromParent();
}

/// Bend across the travel direction, never backwards into the sender's avatar.
/// A fixed upward arc can reverse short downward flights on landscape screens.
Offset tableGiftFlightPoint(
  Offset from,
  Offset to,
  double progress, {
  bool self = false,
}) {
  final t = progress.clamp(0.0, 1.0);
  final eased = Curves.easeInOutCubic.transform(t);
  final point = Offset.lerp(from, to, eased)!;
  final delta = to - from;
  final distance = delta.distance;
  if (distance < .001) return point;
  final normal = Offset(delta.dy / distance, -delta.dx / distance);
  final bend = math.min(self ? 10.0 : 32.0, distance * .22);
  return point + normal * (bend * 4 * eased * (1 - eased));
}
