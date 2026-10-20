import 'package:okeyix/game/observed_effect.dart';
import 'package:flame/collisions.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:okeyix/game/theme_flags.dart';

import 'package:flame/components.dart';
import 'okey_game.dart';

class Stage extends Component with HasGameReference<OkeyGame> {
  late final PositionComponent _rack;
  bool _buttonsShown = false;
  Component? _actionMenu;

  @override
  Future<void> onLoad() async {
    final image = await game.images.load('rack.png');

    _rack = PositionComponent(
      size: Vector2(1440, 400),
      position: Vector2(810, 900 - 180),
      anchor: Anchor.center,
    );

    _rack.add(
      SpriteComponent(
        sprite: Sprite(image),
        size: _rack.size,
        anchor: Anchor.center,
        position: _rack.size / 2,
      ),
    );
    if (ThemeFlags.useCinematicTheme && ThemeFlags.useCinematicRack) {
      _rack.add(RackCinematicFx(size: _rack.size, position: _rack.size / 2));
    }

    _rack.priority = 0;
    add(_rack);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_actionMenu != null && (!game.gameStarted || game.isFinishOpen)) {
      _closeActionMenu();
    }
    if (_buttonsShown || !game.gameStarted) return;
    _buttonsShown = true;
    _spawnAnimatedRackButtons();
  }

  Future<void> _spawnAnimatedRackButtons() async {
    final position = Vector2(
      _rack.position.x + _rack.size.x / 2 - 58,
      _rack.position.y - 60,
    );
    add(RackActionButton(
      label: 'Diz',
      icon: Icons.sort_rounded,
      targetPosition: position,
      startPosition: position,
      size: Vector2(120, 96),
      onTap: _toggleActionMenu,
    ));
  }

  void _closeActionMenu() {
    _actionMenu?.removeFromParent();
    _actionMenu = null;
  }

  void _toggleActionMenu() {
    if (_actionMenu != null) {
      _closeActionMenu();
      return;
    }
    final menu = Component(priority: 20);
    _actionMenu = menu;
    final actions = <(String, VoidCallback)>[
      ('Seri Diz', () => game.arrangeSerial()),
      ('Çifte Diz', () => game.arrangePairs()),
      ('Çifte Git', () => game.requestDoubleMode()),
    ];
    for (var i = 0; i < actions.length; i++) {
      final action = actions[i];
      final position = Vector2(
        _rack.position.x + _rack.size.x / 2 - 138,
        _rack.position.y - 60 - (3 - i) * 102,
      );
      menu.add(RackActionButton(
        label: action.$1,
        icon: const [
          Icons.view_week_rounded,
          Icons.filter_2_rounded,
          Icons.double_arrow_rounded,
        ][i],
        targetPosition: position,
        startPosition: position + Vector2(0, 8),
        size: Vector2(200, 96),
        onTap: () {
          _closeActionMenu();
          action.$2();
        },
      ));
    }
    add(menu);
  }
}

class RackCinematicFx extends PositionComponent {
  RackCinematicFx({required Vector2 size, required Vector2 position}) {
    this.size = size;
    this.position = position;
    anchor = Anchor.center;
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    final glowA = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0x6627D8FF), Color(0x33FF5BF1), Color(0x4D2AB3FF)],
        stops: [0.0, 0.48, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, glowA);

    final stripTop = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Color(0x0064F3FF), Color(0xAA64F3FF), Color(0x0064F3FF)],
      ).createShader(Rect.fromLTWH(0, size.y * 0.28, size.x, 6));
    canvas.drawRect(Rect.fromLTWH(0, size.y * 0.28, size.x, 6), stripTop);

    final stripMid = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Color(0x00FF57E8), Color(0x99FF57E8), Color(0x00FF57E8)],
      ).createShader(Rect.fromLTWH(0, size.y * 0.52, size.x, 5));
    canvas.drawRect(Rect.fromLTWH(0, size.y * 0.52, size.x, 5), stripMid);
  }
}

class RackActionButton extends PositionComponent with TapCallbacks, ActivityLifecycleObservation {
  final String label;
  final IconData? icon;
  final Vector2 targetPosition;
  final Vector2 startPosition;
  final VoidCallback onTap;
  bool _pressed = false;
  final List<TextPainter> _labels = [];
  TextPainter? _iconPainter;
  double? _labelWidth;
  double? _labelHeight;
  int textMeasurements = 0;

  void _clearLabels() {
    _iconPainter?.dispose();
    _iconPainter = null;
    for (final painter in _labels) {
      painter.dispose();
    }
    _labels.clear();
    _labelWidth = null;
    _labelHeight = null;
  }

  void _prepareLabels() {
    if (_labelWidth == size.x && _labelHeight == size.y) return;
    _clearLabels();
    final glyph = icon;
    if (glyph != null) {
      _iconPainter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(glyph.codePoint),
          style: TextStyle(
            fontFamily: glyph.fontFamily,
            package: glyph.fontPackage,
            fontSize: 32,
            color: const Color(0xFFE5D3AA),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    }
    for (final line in size.x >= 180 ? [label] : label.split(' ')) {
      _labels.add(
        TextPainter(
          text: TextSpan(
            text: line,
            style: TextStyle(
              color: const Color(0xFFE5D3AA),
              fontSize: size.x >= 180 ? 27 : 23,
              fontWeight: FontWeight.w600,
              height: 1.0,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(),
      );
      textMeasurements++;
    }
    _labelWidth = size.x;
    _labelHeight = size.y;
  }

  @override
  void onRemove() {
    _clearLabels();
    super.onRemove();
  }

  RackActionButton({
    required this.label,
    this.icon,
    required this.targetPosition,
    required this.startPosition,
    required Vector2 size,
    required this.onTap,
  }) : super(
         position: startPosition,
         size: size,
         anchor: Anchor.topLeft,
         priority: 10,
       );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(RectangleHitbox(size: size, anchor: Anchor.topLeft));

    add(
      observeGameEffect(MoveEffect.to(
        targetPosition,
        EffectController(duration: 0.32, curve: Curves.easeOutBack),
      ), activityProbeFor(this), 'stage.dart:1'),
    );
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final rect = Rect.fromLTWH(5, 5, size.x - 10, size.y - 10);
    final r = RRect.fromRectAndRadius(rect, const Radius.circular(22));

    final body = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x992A342C), Color(0x9913211C)],
      ).createShader(rect);
    final border = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xCCCFB878), Color(0x667F713E)],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    if (_pressed) {
      canvas.save();
      final cx = size.x / 2;
      final cy = size.y / 2;
      canvas.translate(cx, cy);
      canvas.scale(0.98, 0.98);
      canvas.translate(-cx, -cy);
    }
    canvas.drawRRect(r, body);
    canvas.drawRRect(r, border);
    renderLabels(canvas);
    if (_pressed) canvas.restore();
  }

  void renderLabels(Canvas canvas) {
    _prepareLabels();
    const lineHeight = 27.0;
    var y = (size.y - _labels.length * lineHeight) / 2;
    final iconPainter = _iconPainter;
    if (iconPainter != null) {
      iconPainter.paint(
        canvas,
        Offset((size.x - iconPainter.width) / 2, 14),
      );
      y = size.y - 14 - _labels.length * lineHeight;
    }
    for (final painter in _labels) {
      painter.paint(canvas, Offset((size.x - painter.width) / 2, y));
      y += lineHeight;
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (_pressed) return;
    _pressed = true;
    add(
      observeGameEffect(ScaleEffect.to(
        Vector2.all(0.96),
        EffectController(duration: 0.06, curve: Curves.easeOut),
      ), activityProbeFor(this), 'stage.dart:2'),
    );
    onTap();
  }

  @override
  void onTapUp(TapUpEvent event) {
    _pressed = false;
    add(
      observeGameEffect(ScaleEffect.to(
        Vector2.all(1.0),
        EffectController(duration: 0.08, curve: Curves.easeOut),
      ), activityProbeFor(this), 'stage.dart:3'),
    );
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    _pressed = false;
    add(
      observeGameEffect(ScaleEffect.to(
        Vector2.all(1.0),
        EffectController(duration: 0.08, curve: Curves.easeOut),
      ), activityProbeFor(this), 'stage.dart:4'),
    );
  }
}
