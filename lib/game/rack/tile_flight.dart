import 'package:flame/components.dart';
import 'package:flutter/animation.dart';

/// A visual-only path in world coordinates. Slot ownership is independent.
class TileFlight {
  final Vector2 start;
  final Vector2 end;
  final Vector2 control;
  final double duration;
  final Curve curve;
  final Vector2? velocity;
  double elapsed;

  TileFlight({
    required Vector2 start,
    required Vector2 end,
    required this.duration,
    required this.curve,
    this.velocity,
    this.elapsed = 0,
  }) : start = start.clone(), end = end.clone(),
       control = (start + end) / 2 - Vector2(0, 42);

  double get progress => (elapsed / duration).clamp(0.0, 1.0);
  bool get completed => elapsed >= duration;

  Vector2 get position {
    // Linear time preserves the release velocity at the start of a drag throw.
    final t = velocity == null ? curve.transform(progress) : progress;
    final u = 1 - t;
    final releaseVelocity = velocity;
    if (releaseVelocity != null) {
      final c1 = start + releaseVelocity * (duration / 3);
      final c2 = end - (end - start) * .12;
      return start * (u * u * u) + c1 * (3 * u * u * t) +
          c2 * (3 * u * t * t) + end * (t * t * t);
    }
    return start * (u * u) + control * (2 * u * t) + end * (t * t);
  }

  TileFlight copy() => TileFlight(start: start, end: end,
      duration: duration, curve: curve, velocity: velocity?.clone(), elapsed: elapsed);
}
