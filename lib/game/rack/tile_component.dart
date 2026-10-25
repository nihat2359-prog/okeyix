import 'package:okeyix/game/observed_effect.dart';
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:okeyix/engine/models/tile.dart';
import 'package:okeyix/services/user_state.dart';
import 'package:okeyix/game/theme_flags.dart';
import '../okey_game.dart';
import 'rack_config.dart';
import '../components/cached_decoration.dart';
import 'dart:math' as math;
import 'dart:async' as async;
import 'package:okeyix/services/tile_theme_service.dart';

enum TileColorType { red, blue, black, yellow }

extension TileColorTypeStyle on TileColorType {
  Color get color {
    switch (this) {
      case TileColorType.red:
        return const Color(0xFFD12B3F); // cooler crimson red
      case TileColorType.blue:
        return const Color(0xFF1F5BFF); // classic vivid blue
      case TileColorType.black:
        return const Color(0xFF1A1A1A); // soft black
      case TileColorType.yellow:
        if (UserState.colorBlindMode) {
          return const Color(0xFF2E8B57);
        }
        return const Color(0xFFAA7B12);
    }
  }
}

class TileComponent extends PositionComponent
    with
        HasGameReference<FlameGame>,
        DragCallbacks,
        TapCallbacks,
        ActivityLifecycleObservation {
  bool renderInDragOverlay = false;
  bool _paintingDragOverlay = false;
  bool _awaitingDrawConfirmation = false;
  Object? _faceTheme;
  TextComponent? _numberGlow;
  TileGemBadge? _gemBadge;

  void showAwaitingDrawConfirmation() {
    _awaitingDrawConfirmation = true;
    if (isLoaded) {
      removeAll(children);
      _buildFace();
    }
  }

  @override
  void renderTree(Canvas canvas) {
    if (renderInDragOverlay && !_paintingDragOverlay) return;
    super.renderTree(canvas);
  }

  void paintOnDragOverlay(Canvas canvas) {
    _paintingDragOverlay = true;
    try {
      renderTree(canvas);
    } finally {
      _paintingDragOverlay = false;
    }
  }

  final TileModel tile;

  late SpriteComponent baseSprite;
  late TextComponent numberText;
  late SpriteComponent backSprite;
  late PositionComponent backFrameFx;
  bool isFaceDown = false;
  Vector2? dragOffset;
  Vector2 originalPosition = Vector2.zero();
  Vector2? currentTarget;
  Vector2? _rackMoveStart;
  double _rackMoveElapsed = 0;

  void stopRackMotion() {
    _rackMoveStart = null;
  }

  void moveOnRack(Vector2 target) {
    if (isLocked) return;
    currentTarget = target.clone();
    _rackMoveStart = position.clone();
    _rackMoveElapsed = 0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    final start = _rackMoveStart;
    final target = currentTarget;
    if (start == null || target == null) return;
    _rackMoveElapsed += dt;
    final progress = (_rackMoveElapsed / 0.16).clamp(0.0, 1.0);
    if (progress >= 1) {
      position.setFrom(target);
      stopRackMotion();
    } else {
      position.setFrom(
        start + (target - start) * Curves.easeOutBack.transform(progress),
      );
    }
  }
  int? currentSlotIndex;
  int? originalSlotIndex;
  bool isLocked = false;
  DateTime? _lastTap;
  bool _doubleTapInProgress = false;
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
    final gameRef = findGame();
    if (gameRef == null) return;
    await super.onLoad();
    final baseImage = await gameRef.images.load('tile_base.png');
    final backImage = await gameRef.images.load('tile_back.png');
    if (parent == null || isRemoving) return;

    // BACK SPRITE (ters yüz)
    backSprite = SpriteComponent(
      sprite: Sprite(backImage),
      size: size,
      anchor: Anchor.center,
      position: size / 2,
    );
    backSprite.paint.colorFilter = TileThemeService.palette.filter;
    backFrameFx = TileBackFrameFx(size: size, position: size / 2);

    // BASE SPRITE
    baseSprite = SpriteComponent(
      sprite: Sprite(baseImage),
      size: size,
      anchor: Anchor.center,
      position: size / 2,
    );
    baseSprite.paint.colorFilter = TileThemeService.palette.filter;

    // Eğer gerçek okeyse ters başlat
    isFaceDown = isJoker && !isFakeJoker;
    _faceTheme = (TileThemeService.selected.value, UserState.colorBlindMode);
    _buildFace();
  }

  @override
  void onMount() {
    super.onMount();
    TileThemeService.selected.addListener(_refreshTheme);
    _refreshTheme();
  }

  void _refreshTheme() {
    if (!isLoaded || isRemoving) return;
    final key = (TileThemeService.selected.value, UserState.colorBlindMode);
    if (_faceTheme == key) return;
    _faceTheme = key;
    baseSprite.paint.colorFilter = TileThemeService.palette.filter;
    backSprite.paint.colorFilter = TileThemeService.palette.filter;
    // Update only presentation paints. Keep children, cached ui.Pictures,
    // movement/scale effects, joker state and geometry intact.
    if (!_awaitingDrawConfirmation && !isFakeJoker && !(isJoker && isFaceDown)) {
      final ink = _getInkColor();
      final renderer = numberText.textRenderer as TextPaint;
      numberText.textRenderer = TextPaint(style: renderer.style.copyWith(color: ink,
        shadows: _inkShadows()));
      final glow = _numberGlow;
      if (glow != null) {
        final glowStyle = (glow.textRenderer as TextPaint).style;
        glow.textRenderer = TextPaint(style: glowStyle.copyWith(
          color: ink.withValues(alpha: .28),
          shadows: [Shadow(blurRadius: 4, color: ink.withValues(alpha: .30))],
        ));
      }
      _gemBadge?.coreColor = ink;
      _gemBadge?.rimColor = ink;
      _gemBadge?.outlineColor = TileThemeService.palette.inkOutline(tile.color,
        colorBlind: UserState.colorBlindMode);
    }
  }

  @override
  void onRemove() {
    TileThemeService.selected.removeListener(_refreshTheme);
    super.onRemove();
  }

  void _buildFace() {
    _numberGlow = null;
    _gemBadge = null;
    if (_awaitingDrawConfirmation) {
      add(baseSprite);
      add(TextComponent(
        text: '…',
        anchor: Anchor.center,
        position: size / 2,
        textRenderer: TextPaint(style: const TextStyle(
          fontSize: 36, color: Color(0xFF6D716C),
        )),
      ));
      return;
    }
    if (isJoker && isFaceDown) {
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

    // Eğer sahte okeyse ⭐ çiz
    if (isFakeJoker) {
      add(baseSprite);
      if (ThemeFlags.useCinematicTheme && ThemeFlags.useCinematicTiles) {
        add(TileFrontCinematicFx(size: size, position: size / 2));
      }

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
    final isYellowInk = tile.color == TileColor.yellow;

    // Surface polish and bevel for a more premium tile body.
    add(TileSurfaceFx(size: size, position: size / 2));

    final numberPos = Vector2(size.x / 2, size.y * 0.345);

    if (!isYellowInk) {
      final glowText = TextComponent(
        text: value.toString(),
        textRenderer: TextPaint(
          style: TextStyle(
            fontFamily: 'Montserrat',
            fontWeight: FontWeight.w800,
            fontSize: 56,
            letterSpacing: -0.4,
            color: inkColor.withOpacity(0.28),
            shadows: [
              Shadow(
                offset: const Offset(0, 0),
                blurRadius: 4.0,
                color: inkColor.withOpacity(0.30),
              ),
            ],
          ),
        ),
        anchor: Anchor.center,
        position: numberPos,
        priority: 1,
      );
      add(glowText);
      _numberGlow = glowText;
    }

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

          shadows: _inkShadows(),
        ),
      ),
      anchor: Anchor.center,
      position: numberPos,
      priority: 2,
    );
    add(numberText);

    // Color gem instead of a flat dot.
    add(
      _gemBadge = TileGemBadge(
        radius: 10.5,
        center: Vector2(size.x / 2, size.y * 0.71),
        coreColor: badgeColors,
        rimColor: badgeColors,
        mellow: isYellowInk,
        outlineColor: TileThemeService.palette.inkOutline(tile.color,
          colorBlind: UserState.colorBlindMode),
      ),
    );
  }

  @override
  void onTapDown(TapDownEvent event) {
    final gameRef = _tryGame();
    gameRef?.clearGroupSelectionIfDifferent(this);

    final now = DateTime.now();
    _doubleTapInProgress = false;

    if (_lastTap != null &&
        now.difference(_lastTap!) < const Duration(milliseconds: 320)) {
      _doubleTapInProgress = true;
      _lastTap = null;
      _onDoubleTap();
      return;
    }

    _lastTap = now;
  }

  void _onDoubleTap() {
    final gameRef = game as OkeyGame;

    gameRef.onTileDoubleTap(this);
  }

  void playInvalidFinishHighlight() {
    if (!isMounted) return;
    stopRackMotion();
    final startPos = position.clone();
    final startScale = scale.clone();
    final startPriority = priority;
    priority = 120;

    children.whereType<MoveEffect>().toList().forEach(
      (e) => e.removeFromParent(),
    );
    children.whereType<ScaleEffect>().toList().forEach(
      (e) => e.removeFromParent(),
    );
    children.whereType<_InvalidFinishFx>().toList().forEach(
      (e) => e.removeFromParent(),
    );

    add(_InvalidFinishFx(size: size, position: size / 2));

    add(
      observeGameEffect(
        SequenceEffect(
          [
            observeGameEffect(
              MoveEffect.by(
                Vector2(0, -16),
                EffectController(duration: 0.11, curve: Curves.easeOutCubic),
              ),
              activityProbeFor(this),
              'tile_component.dart:2',
            ),
            observeGameEffect(
              ScaleEffect.to(
                Vector2(1.08, 1.08),
                EffectController(duration: 0.11, curve: Curves.easeOutBack),
              ),
              activityProbeFor(this),
              'tile_component.dart:3',
            ),
            observeGameEffect(
              MoveEffect.to(
                startPos,
                EffectController(duration: 0.15, curve: Curves.easeInCubic),
              ),
              activityProbeFor(this),
              'tile_component.dart:4',
            ),
            observeGameEffect(
              ScaleEffect.to(
                startScale,
                EffectController(duration: 0.12, curve: Curves.easeInOut),
              ),
              activityProbeFor(this),
              'tile_component.dart:5',
            ),
          ],
          onComplete: () {
            if (!isMounted) return;
            if (priority == 120) {
              priority = startPriority;
            }
          },
        ),
        activityProbeFor(this),
        'tile_component.dart:1',
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
    if (!isJoker || isFakeJoker || !isLoaded) return;

    isFaceDown = !isFaceDown;

    removeAll(children);

    _buildFace();
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
    // Rebuilding a joker's face removes its children, including the automatic
    // discard MoveEffect started by the second tap. Let that animation finish.
    final wasDoubleTap = _doubleTapInProgress;
    _doubleTapInProgress = false;
    if (isJoker && !wasDoubleTap) {
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

    stopRackMotion();
    if (gameRef.isGroupDragAnchor(this)) {
      priority = 100;
      gameRef.startActiveGroupDrag(this);
      return;
    }

    gameRef.clearGroupSelectionIfDifferent(this);

    originalPosition = position.clone();
    // Stop a previous slot/preview animation before the pointer takes control.
    children.whereType<MoveEffect>().toList().forEach((e) => e.removeFromParent());
    dragOffset = event.localPosition;
    priority = 100;
    gameRef.showTileAboveAvatars(this);

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
    gameRef.notifyDraggedTileMoved();
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

      gameRef.hideTileAboveAvatars(this);
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
        gameRef.hideTileAboveAvatars(this);
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
    stopRackMotion();
    children.whereType<MoveEffect>().toList().forEach((e) => e.removeFromParent());
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
  List<Shadow> _inkShadows() {
    final themed = TileThemeService.palette.inkShadows(tile.color,
      colorBlind: UserState.colorBlindMode);
    if (themed != null) return themed;
    final isYellowInk = tile.color == TileColor.yellow;
    return isYellowInk
              ? [
                  // Thin dark contour so yellow stays readable on warm tile base.
                  Shadow(
                    offset: const Offset(-0.65, 0),
                    blurRadius: 0.0,
                    color: const Color(0xFF6A5600).withOpacity(0.72),
                  ),
                  Shadow(
                    offset: const Offset(0.65, 0),
                    blurRadius: 0.0,
                    color: const Color(0xFF6A5600).withOpacity(0.72),
                  ),
                  Shadow(
                    offset: const Offset(0, -0.65),
                    blurRadius: 0.0,
                    color: const Color(0xFF6A5600).withOpacity(0.65),
                  ),
                  Shadow(
                    offset: const Offset(0, 0.6),
                    blurRadius: 0.0,
                    color: const Color(0xFF6A5600).withOpacity(0.70),
                  ),
                ]
              : [
                  Shadow(
                    offset: const Offset(0, 0),
                    blurRadius: 0.7,
                    color: Colors.black.withOpacity(0.18),
                  ),
                ];
  }
  Color _getInkColor() {
    return TileThemeService.palette.ink(tile.color,
        colorBlind: UserState.colorBlindMode);
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

class TileSurfaceFx extends PositionComponent with CachedDecoration {
  TileSurfaceFx({required Vector2 size, required Vector2 position}) {
    this.size = size;
    this.position = position;
    anchor = Anchor.center;
  }

  @override
  void renderDecoration(Canvas canvas) {
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
  Color coreColor;
  Color rimColor;
  Color? outlineColor;
  final bool mellow;

  TileGemBadge({
    required this.radius,
    required this.center,
    required this.coreColor,
    required this.rimColor,
    this.mellow = false,
    this.outlineColor,
  }) {
    position = center;
    anchor = Anchor.center;
  }

  @override
  void render(Canvas canvas) {
    final edge = outlineColor;
    if (edge != null) {
      canvas.drawCircle(Offset.zero, radius + 1.5, Paint()..color = edge);
    }
    if (mellow) {
      canvas.drawCircle(Offset.zero, radius, Paint()..color = coreColor);
      return;
    }
    final double outerCoreOpacity = mellow ? 0.84 : 0.96;
    final double ringOpacity = mellow ? 0.36 : 0.53;
    final double gleamOpacity = mellow ? 0.34 : 0.65;

    final outer = Paint()
      ..shader = RadialGradient(
        colors: [coreColor.withOpacity(outerCoreOpacity), rimColor],
        stops: const [0.35, 1.0],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius));
    canvas.drawCircle(Offset.zero, radius, outer);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Colors.white.withOpacity(ringOpacity);
    canvas.drawCircle(Offset.zero, radius - 0.9, ring);

    final gleam = Paint()..color = Colors.white.withOpacity(gleamOpacity);
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
