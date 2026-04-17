import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import '../okey_game.dart';
import 'rack_config.dart';
import 'dart:math' as math;

enum TileColorType { red, blue, black, yellow }

extension TileColorTypeStyle on TileColorType {
  Color get color {
    switch (this) {
      case TileColorType.red:
        return const Color(0xFFB3261E); // brick red
      case TileColorType.blue:
        return const Color(0xFF1E5CC6); // deep blue
      case TileColorType.black:
        return const Color(0xFF1A1A1A); // soft black
      case TileColorType.yellow:
        return const Color(0xFFC49A00); // amber gold
    }
  }
}

class TileComponent extends PositionComponent
    with HasGameReference<FlameGame>, DragCallbacks, TapCallbacks {
  final int value;
  final TileColorType colorType;
  final bool isJoker;
  final bool isFakeJoker;
  late SpriteComponent baseSprite;
  late TextComponent numberText;
  late SpriteComponent backSprite;
  bool isFaceDown = false;
  Vector2? dragOffset;
  Vector2 originalPosition = Vector2.zero();
  int? currentSlotIndex;
  int? originalSlotIndex;
  bool isLocked = false;
  TileComponent({
    required this.value,
    required this.colorType,
    required Vector2 position,
    this.isJoker = false,
    this.isFakeJoker = false,
  }) {
    this.position = position;
    size = Vector2(RackConfig.tileWidth, RackConfig.tileHeight);
    anchor = Anchor.center;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final gameRef = game;
    final baseImage = await gameRef.images.load('tile_base.png');
    final backImage = await gameRef.images.load('tile_back.png');

    // BACK SPRITE (ters yüz)
    backSprite = SpriteComponent(
      sprite: Sprite(backImage),
      size: size,
      anchor: Anchor.center,
      position: size / 2,
    );

    // BASE SPRITE
    baseSprite = SpriteComponent(
      sprite: Sprite(baseImage),
      size: size,
      anchor: Anchor.center,
      position: size / 2,
    );

    // Eğer gerçek okeyse ters başlat
    if (isJoker) {
      isFaceDown = true;
      add(backSprite);
    } else {
      add(baseSprite);
    }

    // Eğer sahte okeyse ⭐ çiz
    if (isFakeJoker) {
      add(baseSprite);

      final centerPos = Vector2(size.x / 2, size.y * 0.32);

      // Premium altın zemin
      add(
        CircleComponent(
          radius: 26,
          paint: Paint()
            ..shader =
                RadialGradient(
                  colors: const [
                    Color(0xFFF2D16B), // inner highlight
                    Color(0xFFC9A227), // outer gold
                  ],
                ).createShader(
                  Rect.fromCircle(
                    center: Offset(centerPos.x, centerPos.y),
                    radius: 26,
                  ),
                ),
          anchor: Anchor.center,
          position: centerPos,
        ),
      );

      // Metal kenar
      add(
        CircleComponent(
          radius: 26,
          paint: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = const Color(0xFF8C6B12),
          anchor: Anchor.center,
          position: centerPos,
        ),
      );

      // Yıldız (şampanya tonu)
      add(
        StarComponent(
          radius: 14,
          paint: Paint()..color = const Color(0xFFFFF4C2),
          position: centerPos,
        ),
      );

      return;
    }

    // Eğer gerçek okey ama ters ise içerik çizme
    if (isJoker && isFaceDown) return;

    // NORMAL TAŞ İÇERİĞİ

    final inkColor = _getInkColor();
    final badgeColors = _getBadgeColors();

    // Surface polish and bevel for a more premium tile body.
    add(TileSurfaceFx(size: size, position: size / 2));

    // Number emboss shadow.
    add(
      TextComponent(
        text: value.toString(),
        textRenderer: TextPaint(
          style: TextStyle(
            fontSize: 49,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.0,
            color: const Color(0x50000000),
          ),
        ),
        anchor: Anchor.center,
        position: Vector2(size.x / 2 + 1.4, size.y * 0.345 + 2.0),
      ),
    );

    // Number crisp edge.
    add(
      TextComponent(
        text: value.toString(),
        textRenderer: TextPaint(
          style: TextStyle(
            fontSize: 49,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.0,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2
              ..color = const Color(0xE6FFFFFF),
          ),
        ),
        anchor: Anchor.center,
        position: Vector2(size.x / 2, size.y * 0.345),
      ),
    );

    // Main number fill.
    numberText = TextComponent(
      text: value.toString(),
      textRenderer: TextPaint(
        style: TextStyle(
          fontSize: 47,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.8,
          color: inkColor,
        ),
      ),
      anchor: Anchor.center,
      position: Vector2(size.x / 2, size.y * 0.345),
    );
    add(numberText);

    // Color gem instead of a flat dot.
    add(
      TileGemBadge(
        radius: 10.5,
        center: Vector2(size.x / 2, size.y * 0.74),
        coreColor: badgeColors[0],
        rimColor: badgeColors[1],
      ),
    );
  }

  void toggleFace() {
    if (!isJoker) return;

    isFaceDown = !isFaceDown;

    removeAll(children);

    if (isFaceDown) {
      add(backSprite);
    } else {
      add(baseSprite);
      onLoad(); // tekrar ön yüzü çiz
    }
  }

  @override
  void onTapUp(TapUpEvent event) {
    if (isJoker) {
      toggleFace();
    }
  }

  // =============================
  // DRAG LOGIC
  // =============================

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (isLocked) {
      event.handled = true;
      return;
    }
    final gameRef = _tryGame();
    if (gameRef == null) return;
    originalPosition = position.clone();
    dragOffset = event.localPosition;
    priority = 100;

    originalSlotIndex = currentSlotIndex;
    if (currentSlotIndex != null) {
      gameRef.freeSlot(currentSlotIndex!);
      currentSlotIndex = null;
    }
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    super.onDragUpdate(event);
    final gameRef = _tryGame();
    if (gameRef == null) return;
    final zoom = gameRef.cameraComponent.viewfinder.zoom;

    position += event.localDelta / zoom;

    gameRef.updatePreview(position);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    try {
      final gameRef = _tryGame();
      if (gameRef == null) return;
      final worldPos = absolutePosition;
      // 0) Kapali desteye birakildiysa bitirme denemesi
      if (gameRef.isPointNearClosedPile(worldPos)) {
        final accepted = gameRef.finishWithTile(this);
        if (!accepted) {
          _restoreToOriginalSlot();
        } else {
          gameRef.scheduleTileRemoval(this);
        }
        priority = 0;
        gameRef.clearPreview();
        gameRef.clearTemporaryShift();
        return;
      }

      // 1) Discard alanına bırakıldı mı? (hitbox toleranslı)
      if (gameRef.bottomRightDiscard.containsPoint(worldPos) ||
          gameRef.isPointNearBottomDiscard(worldPos)) {
        final canDiscardNow =
            gameRef.hasDrawnThisTurn ||
            (gameRef.occupiedSlots.length + 1 == 15);
        if (canDiscardNow) {
          final accepted = gameRef.discardTile(this);
          if (!accepted) {
            _restoreToOriginalSlot();
          } else {
            gameRef.scheduleTileRemoval(this);
          }
        } else {
          _restoreToOriginalSlot();
        }
        priority = 0;
        gameRef.clearPreview();
        gameRef.clearTemporaryShift();
        return;
      }

      // 2) Normal rack logic
      final index = gameRef.getNearestSlotIndex(position);

      if (index != null) {
        gameRef.insertIntoRow(index, this);
        if (currentSlotIndex == null) {
          _restoreToOriginalSlot();
        }
      } else {
        _restoreToOriginalSlot();
      }

      priority = 0;
      gameRef.clearPreview();
      gameRef.clearTemporaryShift();
    } catch (_) {
      final gameRef = _tryGame();
      if (gameRef != null) {
        _restoreToOriginalSlot();
        priority = 0;
        gameRef.clearPreview();
        gameRef.clearTemporaryShift();
      }
    }
  }

  void _restoreToOriginalSlot() {
    final slot = originalSlotIndex;
    if (slot != null) {
      final gameRef = _tryGame();
      if (gameRef == null) return;
      currentSlotIndex = slot;
      gameRef.occupySlot(slot, this);
      position = gameRef.slotPositions[slot];
      return;
    }
    position = originalPosition;
  }

  OkeyGame? _tryGame() {
    if (!isMounted) return null;
    final g = game;
    return g is OkeyGame ? g : null;
  }

  @override
  bool containsLocalPoint(Vector2 point) {
    if (isLocked) return false;
    return super.containsLocalPoint(point);
  }

  // =============================

  Color _getInkColor() {
    switch (colorType) {
      case TileColorType.red:
        return const Color(0xFFA3171B);
      case TileColorType.blue:
        return const Color(0xFF1B4FB5);
      case TileColorType.black:
        return const Color(0xFF151515);
      case TileColorType.yellow:
        return const Color(0xFF9F7600);
    }
  }

  List<Color> _getBadgeColors() {
    switch (colorType) {
      case TileColorType.red:
        return [const Color(0xFFC62828), const Color(0xFF6B1111)];
      case TileColorType.blue:
        return [const Color(0xFF2B6DE8), const Color(0xFF173D83)];
      case TileColorType.black:
        return [const Color(0xFF2C2C2C), const Color(0xFF0E0E0E)];
      case TileColorType.yellow:
        return [const Color(0xFFD8A719), const Color(0xFF7C5D00)];
    }
  }
}

class TileSurfaceFx extends PositionComponent {
  TileSurfaceFx({required Vector2 size, required Vector2 position}) {
    this.size = size;
    this.position = position;
    anchor = Anchor.center;
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));

    final topGloss = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)],
        stops: [0.0, 0.42],
      ).createShader(rect);
    canvas.drawRRect(rrect, topGloss);

    final edgeShadow = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x00000000), Color(0x22000000)],
        stops: [0.65, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect, edgeShadow);

    final innerStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x59FFFFFF);
    canvas.drawRRect(rrect.deflate(1.2), innerStroke);
  }
}

class TileGemBadge extends PositionComponent {
  final double radius;
  final Vector2 center;
  final Color coreColor;
  final Color rimColor;

  TileGemBadge({
    required this.radius,
    required this.center,
    required this.coreColor,
    required this.rimColor,
  }) {
    position = center;
    anchor = Anchor.center;
  }

  @override
  void render(Canvas canvas) {
    final outer = Paint()
      ..shader = RadialGradient(
        colors: [coreColor.withOpacity(0.96), rimColor],
        stops: const [0.35, 1.0],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius));
    canvas.drawCircle(Offset.zero, radius, outer);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = const Color(0x88FFFFFF);
    canvas.drawCircle(Offset.zero, radius - 0.9, ring);

    final gleam = Paint()..color = const Color(0xA6FFFFFF);
    canvas.drawCircle(Offset(-radius * 0.3, -radius * 0.35), radius * 0.28, gleam);
  }
}

class StarComponent extends PositionComponent {
  final double radius;
  final Paint paint;

  StarComponent({
    required this.radius,
    required this.paint,
    required Vector2 position,
  }) {
    this.position = position;
    anchor = Anchor.center;
  }

  @override
  void render(Canvas canvas) {
    final path = Path();
    const int points = 5;
    final double angle = (2 * 3.1415926535) / points;

    for (int i = 0; i < points; i++) {
      final x = radius * math.cos(i * angle - 3.1415926535 / 2);
      final y = radius * math.sin(i * angle - 3.1415926535 / 2);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    path.close();
    canvas.drawPath(path, paint);
  }
}
