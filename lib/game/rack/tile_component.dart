import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:okeyix/engine/models/tile.dart';
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
  final TileModel tile;

  late SpriteComponent baseSprite;
  late TextComponent numberText;
  late SpriteComponent backSprite;
  bool isFaceDown = false;
  Vector2? dragOffset;
  Vector2 originalPosition = Vector2.zero();
  Vector2? currentTarget;
  int? currentSlotIndex;
  int? originalSlotIndex;
  bool isLocked = false;
  DateTime? _lastTap;

  int get value => tile.value;
  TileColor get color => tile.color;
  bool get isJoker => tile.isJoker;
  bool get isFakeJoker => tile.isFakeJoker;
  String get id => tile.id;

  TileComponent({required TileModel tile, required Vector2 position})
    : tile = tile,
      super() {
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
    final badgeColors = _getInkColor();

    // Surface polish and bevel for a more premium tile body.
    add(TileSurfaceFx(size: size, position: size / 2));

    // Number emboss shadow.

    // Main number fill.
    numberText = TextComponent(
      text: value.toString(),
      textRenderer: TextPaint(
        style: TextStyle(
          fontFamily: 'Montserrat',
          fontWeight: FontWeight.w700,
          fontSize: 56,
          letterSpacing: -0.4,

          color: inkColor,

          shadows: [
            // 🔥 alt gölge
            Shadow(
              offset: Offset(0, 1.2),
              blurRadius: 1.2,
              color: Colors.black.withOpacity(0.3),
            ),

            // 🔥 üst highlight
            Shadow(
              offset: Offset(0, -0.5),
              blurRadius: 0.5,
              color: Colors.white.withOpacity(0.15),
            ),
          ],
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
        coreColor: badgeColors,
        rimColor: badgeColors,
      ),
    );
  }

  @override
  void onTapDown(TapDownEvent event) {
    final now = DateTime.now();

    if (_lastTap != null &&
        now.difference(_lastTap!) < const Duration(milliseconds: 250)) {
      _onDoubleTap();
    }

    _lastTap = now;
  }

  void _onDoubleTap() {
    final gameRef = game as OkeyGame;

    gameRef.onTileDoubleTap(this);
  }

  Color _lighten(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness + amount).clamp(0, 1)).toColor();
  }

  Color _darken(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness - amount).clamp(0, 1)).toColor();
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
  Future<void> onDragEnd(DragEndEvent event) async {
    super.onDragEnd(event);
    try {
      final gameRef = _tryGame();
      if (gameRef == null) return;
      final worldPos = absolutePosition;
      // 0) Kapali desteye birakildiysa bitirme denemesi
      if (gameRef.isPointNearClosedPile(worldPos)) {
        final accepted = await gameRef.finishWithTile(this);

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
            gameRef.hasDrawnThisTurn || gameRef.getMyHandCount() == 15;
        if (canDiscardNow) {
          _handleDiscard(gameRef); // 🔥 await YOK
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

  Future<void> _handleDiscard(OkeyGame gameRef) async {
    final accepted = await gameRef.discardTile(this);

    if (!accepted) {
      _restoreToOriginalSlot();
    } else {
      gameRef.scheduleTileRemoval(this);
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
    switch (tile.color) {
      case TileColor.red:
        return const Color(0xFFD32F2F);

      case TileColor.blue:
        return const Color(0xFF2F5BFF);

      case TileColor.black:
        return const Color(0xFF1A1A1A);

      case TileColor.yellow:
        return const Color(0xFFF4A622);
    }
  }

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "color": color.index, // veya string
      "number": value,
      "is_joker": isJoker,
      "is_fake_joker": isFakeJoker,
    };
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
    canvas.drawCircle(
      Offset(-radius * 0.3, -radius * 0.35),
      radius * 0.28,
      gleam,
    );
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

