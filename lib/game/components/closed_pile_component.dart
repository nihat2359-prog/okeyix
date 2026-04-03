import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import '../okey_game.dart';

class ClosedPileComponent extends PositionComponent
    with HasGameReference<OkeyGame>, TapCallbacks, DragCallbacks {
  late Sprite backSprite;
  TextComponent? countText;

  int _currentCount;

  ClosedPileComponent({required Vector2 position, required int initialCount})
    : _currentCount = initialCount {
    this.position = position;
    anchor = Anchor.center;
    size = Vector2(90, 140);
    priority = 50;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final gameRef = findGame() as OkeyGame;
    final backImage = await gameRef.images.load('tile_back.png');
    backSprite = Sprite(backImage);

    countText = TextComponent(
      text: _currentCount.toString(),
      textRenderer: TextPaint(
        style: const TextStyle(
          fontSize: 44,
          fontWeight: FontWeight.w900,
          color: Color(0xFF1B2A49),
          shadows: [
            Shadow(offset: Offset(1, 1), blurRadius: 1, color: Colors.white24),
            Shadow(
              offset: Offset(-1, -1),
              blurRadius: 2,
              color: Colors.black45,
            ),
          ],
        ),
      ),
      anchor: Anchor.center,
      position: size / 2,
    );

    add(countText!);
  }

  @override
  void render(Canvas canvas) {
    // Stack efekti render içinde
    for (int i = 0; i < 3; i++) {
      backSprite.render(canvas, size: size, position: Vector2(i * 3, -i * 3));
    }

    super.render(canvas);
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    try {
      final gameRef = findGame() as OkeyGame;
      gameRef.drawFromClosedPileDrag(absolutePosition);
    } catch (_) {}
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    final gameRef = findGame() as OkeyGame;
    super.onDragUpdate(event);
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

  @override
  void onTapUp(TapUpEvent event) {
    try {
      final gameRef = findGame() as OkeyGame;
      gameRef.drawFromClosedPile();
    } catch (_) {}
  }

  void updateCount(int newCount) {
    _currentCount = newCount;

    countText?.text = newCount.toString();
  }
}
