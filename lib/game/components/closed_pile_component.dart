import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import '../okey_game.dart';
import 'cached_decoration.dart';
import '../../services/tile_theme_service.dart';
import '../tile_theme.dart';
import '../../engine/models/tile.dart';

class ClosedPileComponent extends PositionComponent
    with HasGameReference<OkeyGame>, TapCallbacks, DragCallbacks {
  late Sprite backSprite;
  final _decoration = ClosedPileDecoration();
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
          fontSize: 48,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
          color: Color(0xFF253A63),
          shadows: [
            Shadow(
              offset: Offset(0, 1.0),
              blurRadius: 1.2,
              color: Colors.black38,
            ),
            Shadow(
              offset: Offset(0, -0.35),
              blurRadius: 0.4,
              color: Colors.white30,
            ),
          ],
        ),
      ),
      anchor: Anchor.center,
      position: ClosedPileDecoration.topTileCenter(size),
    );

    add(countText!);
    _applyTheme();
  }

  @override
  void onMount() {
    super.onMount();
    TileThemeService.selected.addListener(_applyTheme);
    _applyTheme();
  }

  void _applyTheme() {
    final palette = TileThemeService.palette;
    backSprite.paint.colorFilter = palette.filter;
    _decoration.palette = palette;
    final text = countText;
    if (text != null) {
      final style = (text.textRenderer as TextPaint).style;
      text.textRenderer = TextPaint(
        style: style.copyWith(
          color: palette.id == TileThemeId.porcelain
              ? const Color(0xFF253A63)
              : palette.ink(TileColor.black),
        ),
      );
    }
  }

  @override
  void render(Canvas canvas) {
    final gameRef = findGame() as OkeyGame;
    if (gameRef.isFinishOpen) return;
    _decoration.size.setFrom(size);
    _decoration.backSprite = backSprite;
    _decoration.render(canvas);
    super.render(canvas);
  }

  @override
  void onRemove() {
    TileThemeService.selected.removeListener(_applyTheme);
    _decoration.onRemove();
    super.onRemove();
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

/// Fixed artwork only; count text and game interaction remain on the parent.
class ClosedPileDecoration extends PositionComponent with CachedDecoration {
  static const layers = 4;
  static const stepX = 2.2;
  static const stepY = -2.0;
  static Vector2 topTileCenter(Vector2 size) =>
      size / 2 + Vector2((layers - 1) * stepX, (layers - 1) * stepY);
  late Sprite backSprite;
  TileThemePalette palette = TileThemeService.palette;
  @override
  Object get decorationKey {
    final paint = backSprite.paint;
    return (
      palette.id,
      backSprite,
      backSprite.image,
      backSprite.src,
      paint.color,
      paint.blendMode,
      paint.colorFilter,
      paint.imageFilter,
      paint.maskFilter,
      paint.shader,
      paint.filterQuality,
      paint.isAntiAlias,
      paint.invertColors,
      paint.style,
      paint.strokeWidth,
      paint.strokeCap,
      paint.strokeJoin,
      paint.strokeMiterLimit,
    );
  }

  @override
  void renderDecoration(Canvas canvas) {
    // Stack efekti render içinde
    for (int i = 0; i < layers; i++) {
      final pos = Vector2(i * stepX, i * stepY);
      backSprite.render(canvas, size: size, position: pos);
      _renderBackFrame(canvas, pos);
    }
  }

  void _renderBackFrame(Canvas canvas, Vector2 pos) {
    final rect = Rect.fromLTWH(pos.x, pos.y, size.x, size.y);
    final borderRect = rect.deflate(0.6);
    final borderRRect = RRect.fromRectAndRadius(
      borderRect,
      const Radius.circular(11.4),
    );

    final outerShadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..color = const Color(0x8F4A525C);
    canvas.drawRRect(borderRRect, outerShadow);

    final outerCore = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: palette.id == TileThemeId.porcelain
            ? const [Color(0xFFF5F8FC), Color(0xFFC8D0DA), Color(0xFF9BA3AE)]
            : [
                Color.lerp(palette.surface, Colors.white, .3)!,
                palette.surface,
                palette.shadow,
              ],
        stops: [0.0, 0.56, 1.0],
      ).createShader(rect);
    canvas.drawRRect(borderRRect.deflate(0.7), outerCore);

    final edgeSpecular = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xD9FFFFFF), Color(0x1AFFFFFF)],
      ).createShader(rect);
    canvas.drawRRect(borderRRect.deflate(1.6), edgeSpecular);

    final innerCore = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = const Color(0x8A7D8792);
    canvas.drawRRect(borderRRect.deflate(2.7), innerCore);
  }
}
