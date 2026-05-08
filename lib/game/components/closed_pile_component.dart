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
          fontFamily: 'Montserrat',
          fontSize: 44,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: Color(0xFF1B2A49),
          shadows: [
            Shadow(offset: Offset(0, 1.2), blurRadius: 1.2, color: Colors.black26),
            Shadow(
              offset: Offset(0, -0.5),
              blurRadius: 0.5,
              color: Colors.white24,
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
      final pos = Vector2(i * 3, -i * 3);
      backSprite.render(canvas, size: size, position: pos);
      _renderBackFrame(canvas, pos);
    }

    super.render(canvas);
  }

  void _renderBackFrame(Canvas canvas, Vector2 pos) {
    final rect = Rect.fromLTWH(pos.x, pos.y, size.x, size.y);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));

    final silverShadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.8
      ..color = const Color(0x995E636A);
    canvas.drawRRect(rrect.deflate(0.8), silverShadow);

    final silverCore = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFEDEFF2), Color(0xFFC9CED4), Color(0xFFA8AFB7)],
        stops: [0.0, 0.52, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect.deflate(1.6), silverCore);

    final silverHighlight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.95
      ..color = const Color(0xCCFFFFFF);
    canvas.drawRRect(rrect.deflate(2.8), silverHighlight);

    final silverInnerShadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = const Color(0x889299A3);
    canvas.drawRRect(rrect.deflate(3.7), silverInnerShadow);
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
