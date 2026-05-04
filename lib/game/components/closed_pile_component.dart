import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import '../okey_game.dart';

class ClosedPileComponent extends PositionComponent
    with HasGameReference<OkeyGame>, TapCallbacks, DragCallbacks {
  late Sprite backSprite;
  TextComponent? countText;

  int _currentCount;
  int _lastTapTime = 0;
  ClosedPileComponent({required Vector2 position, required int initialCount})
    : _currentCount = initialCount {
    this.position = position;
    anchor = Anchor.center;
    size = Vector2(100, 140);
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
    final gameRef = findGame() as OkeyGame;
    if (gameRef.isFinishOpen) return;
    // Stack efekti render içinde
    for (int i = 0; i < 3; i++) {
      backSprite.render(canvas, size: size, position: Vector2(i * 3, -i * 3));
    }

    super.render(canvas);
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);

    final gameRef = findGame() as OkeyGame;
    gameRef.drawFromClosedPileDrag(absolutePosition);
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

    final gameRef = findGame() as OkeyGame;
    gameRef.endSourceDrawDrag(); // 🔥 sadece bu
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);

    final now = DateTime.now().millisecondsSinceEpoch;

    if (now - _lastTapTime < 250) {
      final gameRef = findGame() as OkeyGame;
      gameRef.drawFromClosedPile();
    }

    _lastTapTime = now;
  }

  void updateCount(int newCount) {
    _currentCount = newCount;

    countText?.text = newCount.toString();
  }

  void setHidden(bool hidden) {
    if (hidden) {
      countText?.removeFromParent(); // 🔥 text'i kaldır
    } else {
      if (countText != null && !countText!.isMounted) {
        add(countText!); // 🔥 geri ekle
      }
    }
  }
}

class RackActionsComponent extends PositionComponent {
  RackActionsComponent()
    : super(
        size: Vector2(600, 60), // 🔥 GENİŞ ALAN
        anchor: Anchor.center,
      );

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    add(_action("Seri Diz", Vector2(-200, 0)));
    add(_action("Çifte Diz", Vector2(0, 0)));
    add(_action("Çifte Git", Vector2(200, 0)));
  }

  TextComponent _action(String text, Vector2 pos) {
    return TextComponent(
      text: text,
      position: pos,
      anchor: Anchor.center,
      textRenderer: TextPaint(
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.white.withOpacity(0.9),
        ),
      ),
    );
  }
}
