import 'package:flame/collisions.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';

import 'package:flame/components.dart';
import 'okey_game.dart';

class Stage extends Component with HasGameReference<OkeyGame> {
  @override
  Future<void> onLoad() async {
    final image = await game.images.load('rack.png');

    final rack = PositionComponent(
      size: Vector2(1380, 400),
      position: Vector2(810, 900 - 180),
      anchor: Anchor.center,
    );

    rack.add(
      SpriteComponent(
        sprite: Sprite(image),
        size: rack.size,
        anchor: Anchor.center,
        position: rack.size / 2,
      ),
    );

    final seri = GoldActionHitArea(
      position: Vector2(200, 800),
      size: Vector2(160, 60),
      onTap: () => game.arrangeSerial(),
    );

    final cifte = GoldActionHitArea(
      position: Vector2(390, 800),
      size: Vector2(160, 60),
      onTap: () => game.arrangePairs(),
    );

    final git = GoldActionHitArea(
      position: Vector2(1250, 810),
      size: Vector2(160, 60),
      onTap: () => game.requestDoubleMode(),
    );
    rack.priority = 0;
    add(rack);
    add(seri);
    add(cifte);
    add(git);
  }
}

class GoldActionHitArea extends PositionComponent with TapCallbacks {
  final VoidCallback onTap;

  GoldActionHitArea({
    required Vector2 position,
    required Vector2 size,
    required this.onTap,
  }) : super(
         position: position,
         size: size,
         anchor: Anchor.topLeft, // 🔥 KRİTİK
         priority: 10,
       );

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    add(
      RectangleHitbox(
        size: size,
        anchor: Anchor.topLeft, // 🔥 KRİTİK
      ),
    );

    // debug
    add(
      RectangleComponent(
        size: size,
        anchor: Anchor.topLeft,
        paint: Paint()..color = const Color(0x00000000),
      ),
    );
  }

  @override
  void onTapDown(TapDownEvent event) {
    onTap();
  }
}
