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
  bool hidden = false;
  DiscardSlotComponent({required this.playerIndex, required Vector2 position}) {
    this.position = position;
    size = Vector2(RackConfig.tileWidth, RackConfig.tileHeight);
    anchor = Anchor.center;
  }

  @override
  Future<void> onLoad() async {
    if (hidden) return;
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

  @override
  void render(Canvas canvas) {
    if (hidden) return;
    super.render(canvas);
  }

  @override
  void update(double dt) {
    if (hidden) return;
    super.update(dt);
  }

  void setHidden(bool value) {
    hidden = value;

    for (final c in children) {
      c.removeFromParent(); // 🔥 kesin çözüm
    }
  }

  void setDiscard(Sprite sprite) {
    if (hidden) return;
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
    if (hidden) return;
    super.onTapUp(event);
    if (!isMounted) return;
    game.takeFromDiscardTap(this);
  }

  @override
  void onDragStart(DragStartEvent event) {
    if (hidden) return;
    super.onDragStart(event);
    if (!isMounted) return;
    game.takeFromDiscardDrag(this, absolutePosition);
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (hidden) return;
    super.onDragUpdate(event);
    if (!isMounted) return;
    game.updateSourceDrawDrag(event.localDelta);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    if (hidden) return;
    super.onDragEnd(event);
    if (!isMounted) return;
    game.endSourceDrawDrag();
  }
}
