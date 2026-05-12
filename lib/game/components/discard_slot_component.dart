import 'dart:async' as async;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:okeyix/game/rack/rack_config.dart';

import '../okey_game.dart';
import '../rack/tile_component.dart';

class DiscardSlotComponent extends PositionComponent
    with HasGameReference<OkeyGame>, TapCallbacks, DragCallbacks {
  final int playerIndex;
  TileComponent? currentTile;
  SpriteComponent? tileSprite;
  bool hidden = false;
  DateTime? _lastTapDownAt;
  async.Timer? _doubleTapResetTimer;

  DiscardSlotComponent({required this.playerIndex, required Vector2 position}) {
    this.position = position;
    size = Vector2(RackConfig.tileWidth, RackConfig.tileHeight);
    anchor = Anchor.center;
  }

  @override
  Future<void> onLoad() async {
    if (hidden) return;
    await super.onLoad();
    add(_PremiumDiscardFrame(size: size, position: size / 2));
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
      c.removeFromParent();
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
  void onTapDown(TapDownEvent event) {
    if (hidden) return;
    super.onTapDown(event);
    if (!isMounted) return;
    final now = DateTime.now();
    final isDouble =
        _lastTapDownAt != null &&
        now.difference(_lastTapDownAt!).inMilliseconds <= 480;
    _lastTapDownAt = now;

    _doubleTapResetTimer?.cancel();
    _doubleTapResetTimer = async.Timer(const Duration(milliseconds: 520), () {
      _lastTapDownAt = null;
    });

    if (isDouble) {
      _lastTapDownAt = null;
      _doubleTapResetTimer?.cancel();
      game.takeFromDiscardTap(this);
    }
  }

  @override
  void onDragStart(DragStartEvent event) {
    if (hidden) return;
    super.onDragStart(event);
    if (!isMounted) return;
    _lastTapDownAt = null;
    _doubleTapResetTimer?.cancel();
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

class _PremiumDiscardFrame extends PositionComponent {
  _PremiumDiscardFrame({required Vector2 size, required Vector2 position})
    : super(size: size, position: position, anchor: Anchor.center);

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    final outer = RRect.fromRectAndRadius(rect, const Radius.circular(13));
    final inner = RRect.fromRectAndRadius(
      rect.deflate(5),
      const Radius.circular(10),
    );

    final body = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0x5A1C2A24), Color(0x28101713)],
      ).createShader(rect);
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..color = const Color(0xB39F7640);
    final innerBorder = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x5EE5CB90);
    final gloss = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x26FFF0C7), Color(0x00FFF0C7)],
      ).createShader(Rect.fromLTWH(0, 0, size.x, size.y * 0.5));

    canvas.drawRRect(outer, body);
    canvas.drawRRect(outer, gloss);
    canvas.drawRRect(outer, border);
    canvas.drawRRect(inner, innerBorder);

    final accent = Paint()
      ..color = const Color(0x88E5CB90)
      ..strokeWidth = 1.2;
    const cut = 8.0;
    canvas.drawLine(const Offset(4, 4), const Offset(4 + cut, 4), accent);
    canvas.drawLine(const Offset(4, 4), const Offset(4, 4 + cut), accent);
    canvas.drawLine(
      Offset(size.x - 4, 4),
      Offset(size.x - 4 - cut, 4),
      accent,
    );
    canvas.drawLine(
      Offset(size.x - 4, 4),
      Offset(size.x - 4, 4 + cut),
      accent,
    );
    canvas.drawLine(
      Offset(4, size.y - 4),
      Offset(4 + cut, size.y - 4),
      accent,
    );
    canvas.drawLine(
      Offset(4, size.y - 4),
      Offset(4, size.y - 4 - cut),
      accent,
    );
    canvas.drawLine(
      Offset(size.x - 4, size.y - 4),
      Offset(size.x - 4 - cut, size.y - 4),
      accent,
    );
    canvas.drawLine(
      Offset(size.x - 4, size.y - 4),
      Offset(size.x - 4, size.y - 4 - cut),
      accent,
    );
  }
}
