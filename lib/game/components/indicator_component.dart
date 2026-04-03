import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import "package:okeyix/engine/models/tile.dart";
import 'package:okeyix/game/rack/rack_config.dart';
import '../okey_game.dart'; // bunu ekle

class IndicatorComponent extends PositionComponent
    with HasGameReference<OkeyGame> {
  final TileModel tile;

  IndicatorComponent({required this.tile, required Vector2 position}) {
    this.position = position;
    size = Vector2(RackConfig.tileWidth, RackConfig.tileHeight);
    anchor = Anchor.center;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final gameRef = findGame() as OkeyGame;
    final baseImage = await gameRef.images.load('tile_base.png');

    add(
      SpriteComponent(
        sprite: Sprite(baseImage),
        size: size,
        anchor: Anchor.center,
        position: size / 2,
      ),
    );

    final color = _getColor(tile.color);

    // Numara
    add(
      TextComponent(
        text: tile.value.toString(),
        textRenderer: TextPaint(
          style: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        anchor: Anchor.center,
        position: Vector2(size.x / 2, size.y * 0.36),
      ),
    );

    // Renk noktası
    add(
      CircleComponent(
        radius: 10,
        paint: Paint()..color = color,
        anchor: Anchor.center,
        position: Vector2(size.x / 2, size.y * 0.74),
      ),
    );
  }

  Color _getColor(TileColor color) {
    switch (color) {
      case TileColor.red:
        return Colors.red.shade800;
      case TileColor.blue:
        return Colors.blue.shade800;
      case TileColor.black:
        return Colors.black;
      case TileColor.yellow:
        return const Color(0xFFFFD400);
    }
  }
}
