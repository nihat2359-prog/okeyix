import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import "package:okeyix/engine/models/tile.dart";
import 'package:okeyix/game/rack/rack_config.dart';
import '../okey_game.dart'; // bunu ekle
import 'package:okeyix/services/tile_theme_service.dart';
import 'package:okeyix/game/tile_theme.dart';
import 'package:okeyix/services/user_state.dart';

class IndicatorComponent extends PositionComponent
    with HasGameReference<OkeyGame> {
  final TileModel tile;
  late SpriteComponent _base;
  late TextComponent _number;
  late CircleComponent _dot;
  late CircleComponent _dotEdge;

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
      _base = SpriteComponent(
        sprite: Sprite(baseImage),
        size: size,
        anchor: Anchor.center,
        position: size / 2,
      ),
    );

    final color = _getColor(tile.color);

    // Numara
    add(
      _number = TextComponent(
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

    add(
      _dotEdge = CircleComponent(
        radius: 11.5,
        paint: Paint()..color = Colors.transparent,
        anchor: Anchor.center,
        position: Vector2(size.x / 2, size.y * 0.74),
      ),
    );
    // Renk noktası
    add(
      _dot = CircleComponent(
        radius: 10,
        paint: Paint()..color = color,
        anchor: Anchor.center,
        position: Vector2(size.x / 2, size.y * 0.74),
      ),
    );
    _applyTheme();
  }

  @override
  void onMount() {
    super.onMount();
    TileThemeService.selected.addListener(_applyTheme);
    _applyTheme();
  }

  @override
  void onRemove() {
    TileThemeService.selected.removeListener(_applyTheme);
    super.onRemove();
  }

  void _applyTheme() {
    _base.paint.colorFilter = TileThemeService.palette.filter;
    final color = _getColor(tile.color);
    _number.textRenderer = TextPaint(
      style: TextStyle(
        fontSize: 48,
        fontWeight: FontWeight.bold,
        color: color,
        shadows: TileThemeService.palette.inkShadows(
          tile.color,
          colorBlind: UserState.colorBlindMode,
        ),
      ),
    );
    _dot.paint.color = color;
    _dotEdge.paint.color =
        TileThemeService.palette.inkOutline(
          tile.color,
          colorBlind: UserState.colorBlindMode,
        ) ??
        Colors.transparent;
  }

  Color _getColor(TileColor color) {
    if (TileThemeService.selected.value != TileThemeId.porcelain) {
      return TileThemeService.palette.ink(
        color,
        colorBlind: UserState.colorBlindMode,
      );
    }
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
