import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../okey_game.dart';
import 'package:okeyix/game/rack/rack_config.dart';
import 'package:flame/events.dart';
import '../rack/tile_component.dart';

class DiscardSlotComponent extends PositionComponent
    with HasGameReference<OkeyGame>, TapCallbacks, DragCallbacks {
  final int playerIndex;
  TileComponent? currentTile;
  SpriteComponent? tileSprite;

  DiscardSlotComponent({required this.playerIndex, required Vector2 position}) {
    this.position = position;
    size = Vector2(RackConfig.tileWidth, RackConfig.tileHeight);
    anchor = Anchor.center;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Premium arka plan (şimdilik yarı transparan)
    add(
      RectangleComponent(
        size: size,
        paint: Paint()..color = const Color(0x800E1318),
        anchor: Anchor.center,
        position: size / 2,
      ),
    );

    // Hafif border
    add(
      RectangleComponent(
        size: size,
        paint: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFF2A323C),
        anchor: Anchor.center,
        position: size / 2,
      ),
    );
  }

  void setDiscard(Sprite sprite) {
    tileSprite?.removeFromParent();

    tileSprite = SpriteComponent(
      sprite: sprite,
      size: size,
      anchor: Anchor.center,
      position: size / 2,
    );

    add(tileSprite!);
  }

  @override
  void onTapUp(TapUpEvent event) {
    super.onTapUp(event);
    try {
      final gameRef = findGame() as OkeyGame;
      gameRef.takeFromDiscardTap(this);
    } catch (_) {}
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    try {
      final gameRef = findGame() as OkeyGame;
      gameRef.takeFromDiscardDrag(this, absolutePosition);
    } catch (_) {}
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    super.onDragUpdate(event);
    final gameRef = findGame() as OkeyGame;
    gameRef.updateSourceDrawDrag(event.localDelta);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    try {
      final gameRef = findGame() as OkeyGame;
      gameRef.endSourceDrawDrag();
    } catch (_) {}
  }
}
