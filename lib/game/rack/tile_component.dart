import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:okeyix/engine/models/tile.dart';
import 'package:okeyix/services/user_state.dart';
import 'package:okeyix/game/theme_flags.dart';
import '../okey_game.dart';
import 'rack_config.dart';
import 'dart:math' as math;
import 'dart:async' as async;

enum TileColorType { red, blue, black, yellow }

extension TileColorTypeStyle on TileColorType {
  Color get color {
    switch (this) {
      case TileColorType.red:
        return const Color(0xFFD12B3F); // cooler crimson red
      case TileColorType.blue:
        return const Color(0xFF1E5CC6); // deep blue
      case TileColorType.black:
        return const Color(0xFF1A1A1A); // soft black
      case TileColorType.yellow:
        if (UserState.colorBlindMode) {
          return const Color(0xFF2E8B57);
        }
        return const Color(0xFF8D7300); // league-title gold
    }
  }
}

class TileComponent extends PositionComponent
    with HasGameReference<FlameGame>, DragCallbacks, TapCallbacks {
  final TileModel tile;

  late SpriteComponent baseSprite;
  late TextComponent numberText;
  late SpriteComponent backSprite;
  late PositionComponent backFrameFx;
  bool isFaceDown = false;
  Vector2? dragOffset;
  Vector2 originalPosition = Vector2.zero();
  Vector2? currentTarget;
  int? currentSlotIndex;
  int? originalSlotIndex;
  bool isLocked = false;
  DateTime? _lastTap;
  async.Timer? _liftHoldTimer;
  Vector2? _liftHoldAnchor;

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
    // Keep tiles above rack visuals so dealt tiles never hide behind the rack.
    priority = 20;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final gameRef = game;
    final baseImage = await gameRef.images.load('tile_base.png');
    final backImage = await gameRef.images.load('tile_back.png');

    // BACK SPRITE (ters yÃ¼z)
    backSprite = SpriteComponent(
      sprite: Sprite(backImage),
      size: size,
      anchor: Anchor.center,
      position: size / 2,
    );
    backFrameFx = TileBackFrameFx(size: size, position: size / 2);

    // BASE SPRITE
    baseSprite = SpriteComponent(
      sprite: Sprite(baseImage),
      size: size,
      anchor: Anchor.center,
      position: size / 2,
    );

    // EÄŸer gerÃ§ek okeyse ters baÅŸlat
    if (isJoker) {
      isFaceDown = true;
      add(backSprite);
      add(backFrameFx);
      if (ThemeFlags.useCinematicTheme && ThemeFlags.useCinematicTiles) {
        add(TileBackCinematicFx(size: size, position: size / 2));
      }
    } else {
      add(baseSprite);
      if (ThemeFlags.useCinematicTheme && ThemeFlags.useCinematicTiles) {
        add(TileFrontCinematicFx(size: size, position: size / 2));
      }
    }

    // EÄŸer sahte okeyse â­ Ã§iz
    if (isFakeJoker) {
      add(baseSprite);
      if (ThemeFlags.useCinematicTheme && ThemeFlags.useCinematicTiles) {
        add(TileFrontCinematicFx(size: size, position: size / 2));
      }

      final centerPos = Vector2(size.x / 2, size.y * 0.32);

      // Premium altÄ±n zemin
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

      // YÄ±ldÄ±z (ÅŸampanya tonu)
      add(
        StarComponent(
          radius: 14,
          paint: Paint()..color = const Color(0xFFFFF4C2),
          position: centerPos,
        ),
      );

      return;
    }

    // EÄŸer gerÃ§ek okey ama ters ise iÃ§erik Ã§izme
    if (isJoker && isFaceDown) return;

    // NORMAL TAÅ Ä°Ã‡ERÄ°ÄÄ°

    final inkColor = _getInkColor();
    final badgeColors = _getInkColor();

    // Surface polish and bevel for a more premium tile body.
    add(TileSurfaceFx(size: size, position: size / 2));

    final numberPos = Vector2(size.x / 2, size.y * 0.345);

    // Premium soft aura layer (kept subtle for readability).
    final glowText = TextComponent(
      text: value.toString(),
      textRenderer: TextPaint(
        style: TextStyle(
          fontFamily: 'Montserrat',
          fontWeight: FontWeight.w800,
          fontSize: 56,
          letterSpacing: -0.4,
          color: const Color(0xFFE7C66A).withOpacity(0.32),
          shadows: [
            Shadow(
              offset: const Offset(0, 0),
              blurRadius: 4.5,
              color: const Color(0xFFE7C66A).withOpacity(0.35),
            ),
          ],
        ),
      ),
      anchor: Anchor.center,
      position: numberPos,
      priority: 1,
    );
    add(glowText);

    // Main number fill (crisp foreground).
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
            Shadow(
              offset: const Offset(0, 0),
              blurRadius: 0.7,
              color: Colors.black.withOpacity(0.18),
            ),
          ],
        ),
      ),
      anchor: Anchor.center,
      position: numberPos,
      priority: 2,
    );
    add(numberText);

    // Color gem instead of a flat dot.
    add(
      TileGemBadge(
        radius: 10.5,
        center: Vector2(size.x / 2, size.y * 0.71),
        coreColor: badgeColors,
        rimColor: badgeColors,
      ),
    );
  }

  @override
  void onTapDown(TapDownEvent event) {
    final gameRef = _tryGame();
    gameRef?.clearGroupSelectionIfDifferent(this);

    final now = DateTime.now();

    if (_lastTap != null &&
        now.difference(_lastTap!) < const Duration(milliseconds: 320)) {
      _onDoubleTap();
    }

    _lastTap = now;
  }

  void _onDoubleTap() {
    final gameRef = game as OkeyGame;

    gameRef.onTileDoubleTap(this);
  }

  void playInvalidFinishHighlight() {
    if (!isMounted) return;
    final startPos = position.clone();
    final startScale = scale.clone();
    final startPriority = priority;
    priority = 120;

    children
        .whereType<MoveEffect>()
        .toList()
        .forEach((e) => e.removeFromParent());
    children
        .whereType<ScaleEffect>()
        .toList()
        .forEach((e) => e.removeFromParent());
    children
        .whereType<_InvalidFinishFx>()
        .toList()
        .forEach((e) => e.removeFromParent());

    add(_InvalidFinishFx(size: size, position: size / 2));

    add(
      SequenceEffect(
        [
          MoveEffect.by(
            Vector2(0, -16),
            EffectController(duration: 0.11, curve: Curves.easeOutCubic),
          ),
          ScaleEffect.to(
            Vector2(1.08, 1.08),
            EffectController(duration: 0.11, curve: Curves.easeOutBack),
          ),
          MoveEffect.to(
            startPos,
            EffectController(duration: 0.15, curve: Curves.easeInCubic),
          ),
          ScaleEffect.to(
            startScale,
            EffectController(duration: 0.12, curve: Curves.easeInOut),
          ),
        ],
        onComplete: () {
          if (!isMounted) return;
          if (priority == 120) {
            priority = startPriority;
          }
        },
      ),
    );
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
      add(backFrameFx);
      if (ThemeFlags.useCinematicTheme && ThemeFlags.useCinematicTiles) {
        add(TileBackCinematicFx(size: size, position: size / 2));
      }
    } else {
      add(baseSprite);
      onLoad(); // tekrar Ã¶n yÃ¼zÃ¼ Ã§iz
    }
  }

  @override
  void onTapUp(TapUpEvent event) {
    _liftHoldTimer?.cancel();
    _liftHoldTimer = null;
    _liftHoldAnchor = null;
    final gameRef = _tryGame();
    if (gameRef != null && gameRef.isGroupDragAnchor(this)) {
      gameRef.cancelActiveGroupDragSelection();
    }
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
    _liftHoldTimer?.cancel();
    _liftHoldTimer = null;
    _liftHoldAnchor = null;
    if (isLocked) {
      event.handled = true;
      return;
    }
    final gameRef = _tryGame();
    if (gameRef == null) return;

    if (gameRef.isGroupDragAnchor(this)) {
      priority = 100;
      gameRef.startActiveGroupDrag(this);
      return;
    }

    gameRef.clearGroupSelectionIfDifferent(this);

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

    if (gameRef.isGroupDragAnchor(this)) {
      gameRef.updateActiveGroupDrag(this, event.localDelta / zoom);
      return;
    }

    position += event.localDelta / zoom;
    gameRef.updatePreview(position);
    _tryActivateGroupByLiftHold(gameRef);
  }

  @override
  Future<void> onDragEnd(DragEndEvent event) async {
    super.onDragEnd(event);
    _liftHoldTimer?.cancel();
    _liftHoldTimer = null;
    _liftHoldAnchor = null;
    try {
      final gameRef = _tryGame();
      if (gameRef == null) return;

      if (gameRef.isGroupDragAnchor(this)) {
        gameRef.endActiveGroupDrag(this);
        priority = 20;
        gameRef.clearPreview();
        gameRef.clearTemporaryShift();
        return;
      }

      final worldPos = absolutePosition;
      if (gameRef.isPointNearIndicator(worldPos)) {
        final claimed = await gameRef.tryClaimIndicatorBonus(this);
        if (claimed) {
          // Gosterge bonusu alindiysa tas rack'e geri doner.
          _restoreToOriginalSlot();
        } else {
          // Gosterge islemi degilse ayni birakmada bitis dene.
          final finished = await gameRef.finishWithTile(this);
          if (!finished) {
            _restoreToOriginalSlot();
          } else {
            gameRef.scheduleTileRemoval(this);
          }
        }
        priority = 20;
        gameRef.clearPreview();
        gameRef.clearTemporaryShift();
        return;
      }
      // 0) Kapali desteye birakildiysa bitirme denemesi
      if (gameRef.isPointNearClosedPile(worldPos)) {
        final accepted = await gameRef.finishWithTile(this);

        if (!accepted) {
          _restoreToOriginalSlot();
        } else {
          gameRef.scheduleTileRemoval(this);
        }
        priority = 20;
        gameRef.clearPreview();
        gameRef.clearTemporaryShift();
        return;
      }

      // 1) Discard alanÄ±na bÄ±rakÄ±ldÄ± mÄ±? (hitbox toleranslÄ±)
      if (gameRef.bottomRightDiscard.containsPoint(worldPos) ||
          gameRef.isPointNearBottomDiscard(worldPos)) {
        final canDiscardNow =
            gameRef.hasDrawnThisTurn || gameRef.getMyHandCount() == 15;
        if (canDiscardNow) {
          _handleDiscard(gameRef); // ğŸ”¥ await YOK
        } else {
          _restoreToOriginalSlot();
        }
        priority = 20;
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

      priority = 20;
      gameRef.clearPreview();
      gameRef.clearTemporaryShift();
    } catch (_) {
      final gameRef = _tryGame();
      if (gameRef != null) {
        _restoreToOriginalSlot();
        priority = 20;
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

  void _tryActivateGroupByLiftHold(OkeyGame gameRef) {
    if (gameRef.isGroupDragAnchor(this)) return;

    final lift = originalPosition.y - position.y;
    // Grup secimi sadece hafif kaldirma + bekleme ile aktif olsun.
    // Cok yukariya cekilen normal drag senaryosunda tetiklenmesin.
    const minLift = 14.0;
    const maxLift = 34.0;
    final inLiftWindow = lift >= minLift && lift <= maxLift;
    if (!inLiftWindow) {
      _liftHoldTimer?.cancel();
      _liftHoldTimer = null;
      _liftHoldAnchor = null;
      return;
    }

    if (_liftHoldTimer == null) {
      _liftHoldAnchor = position.clone();
      _liftHoldTimer = async.Timer(const Duration(milliseconds: 380), () {
        final gameRef2 = _tryGame();
        if (gameRef2 == null) return;
        final anchor = _liftHoldAnchor;
        if (anchor == null) return;
        final liftNow = originalPosition.y - position.y;
        final liftedNow = liftNow >= minLift && liftNow <= maxLift;
        final stable = position.distanceTo(anchor) <= 10;
        if (!liftedNow || !stable) return;
        if (gameRef2.tryActivateGroupDrag(this)) {
          gameRef2.startActiveGroupDrag(this);
        }
      });
      return;
    }

    final anchor = _liftHoldAnchor;
    if (anchor != null && position.distanceTo(anchor) > 10) {
      _liftHoldTimer?.cancel();
      _liftHoldTimer = null;
      _liftHoldAnchor = null;
    }
  }

  // =============================
  Color _getInkColor() {
    switch (tile.color) {
      case TileColor.red:
        return const Color(0xFFD12B3F);

      case TileColor.blue:
        return const Color(0xFF2F5BFF);

      case TileColor.black:
        return const Color(0xFF1A1A1A);

      case TileColor.yellow:
        if (UserState.colorBlindMode) {
          return const Color(0xFF2E8B57);
        }
        return const Color(0xFF8D7300);
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

  }
}

class TileBackFrameFx extends PositionComponent {
  TileBackFrameFx({required Vector2 size, required Vector2 position}) {
    this.size = size;
    this.position = position;
    anchor = Anchor.center;
  }

  @override
  void render(Canvas canvas) {
    // Intentionally empty: removed tile border frame rendering.
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

class TileFrontCinematicFx extends PositionComponent {
  TileFrontCinematicFx({required Vector2 size, required Vector2 position}) {
    this.size = size;
    this.position = position;
    anchor = Anchor.center;
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));

    final aura = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0x202AD8FF), Color(0x08FFFFFF), Color(0x22FF5BF1)],
      ).createShader(rect);
    canvas.drawRRect(rrect, aura);

    final topSheen = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x33FFFFFF), Color(0x00FFFFFF)],
        stops: [0.0, 0.42],
      ).createShader(rect);
    canvas.drawRRect(rrect, topSheen);
  }
}

class TileBackCinematicFx extends PositionComponent {
  TileBackCinematicFx({required Vector2 size, required Vector2 position}) {
    this.size = size;
    this.position = position;
    anchor = Anchor.center;
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));

    final glow = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0x2B26CFFF), Color(0x00000000), Color(0x20FF4BE6)],
      ).createShader(rect);
    canvas.drawRRect(rrect, glow);
  }
}

class _InvalidFinishFx extends PositionComponent {
  double _elapsed = 0;

  _InvalidFinishFx({required Vector2 size, required Vector2 position}) {
    this.size = size;
    this.position = position;
    anchor = Anchor.center;
    priority = 130;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    if (_elapsed >= 0.9) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));
    final p = (_elapsed / 0.9).clamp(0.0, 1.0);
    final pulse = (1.0 - p) * (0.6 + 0.4 * math.sin(_elapsed * 24).abs());

    final fill = Paint()
      ..color = const Color(0x66FF6B6B).withOpacity(pulse * 0.42);
    canvas.drawRRect(rrect, fill);

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = const Color(0xFFFF8A80).withOpacity(pulse * 0.95);
    canvas.drawRRect(rrect.deflate(1.0), glow);

    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = const Color(0xFFFFE082).withOpacity(pulse * 0.9);
    canvas.drawRRect(rrect.deflate(3.0), inner);
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



