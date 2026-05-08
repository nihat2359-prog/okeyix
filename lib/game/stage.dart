import 'package:flame/collisions.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';

import 'package:flame/components.dart';
import 'okey_game.dart';

class Stage extends Component with HasGameReference<OkeyGame> {
  late final PositionComponent _rack;
  bool _buttonsShown = false;

  @override
  Future<void> onLoad() async {
    final image = await game.images.load('rack.png');

    _rack = PositionComponent(
      size: Vector2(1380, 400),
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

    _rack.priority = 0;
    add(_rack);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_buttonsShown || !game.gameStarted) return;
    _buttonsShown = true;
    _spawnAnimatedRackButtons();
  }

  Future<void> _spawnAnimatedRackButtons() async {
    final rackTop = _rack.position.y - (_rack.size.y / 2);
    final rackLeft = _rack.position.x - (_rack.size.x / 2);
    final rackRight = _rack.position.x + (_rack.size.x / 2);
    const sideGap = 4.0;
    const leftInset = 22.0;
    const rightInset = 22.0;

    final seriSize = Vector2(96, 200);
    final rightSize = Vector2(88, 90);
    const rightGap = 14.0;

    final seriTarget = Vector2(
      rackLeft - seriSize.x - sideGap + leftInset,
      rackTop + 18,
    );
    final rightTopTarget = Vector2(
      rackRight + sideGap - rightInset,
      rackTop + 18,
    );
    final rightBottomTarget = Vector2(
      rackRight + sideGap - rightInset,
      rackTop + 18 + rightSize.y + rightGap,
    );

    final seri = RackActionButton(
      label: 'Seri Diz',
      targetPosition: seriTarget,
      startPosition: Vector2(rackLeft + 24, seriTarget.y),
      size: seriSize,
      onTap: () => game.arrangeSerial(),
    );
    final cifte = RackActionButton(
      label: 'Çifte Diz',
      targetPosition: rightTopTarget,
      startPosition: Vector2(rackRight - rightSize.x - 24, rightTopTarget.y),
      size: rightSize,
      onTap: () => game.arrangePairs(),
    );
    final git = RackActionButton(
      label: 'Çifte Git',
      targetPosition: rightBottomTarget,
      startPosition: Vector2(
        rackRight - rightSize.x - 24,
        rightBottomTarget.y,
      ),
      size: rightSize,
      onTap: () => game.requestDoubleMode(),
    );

    add(seri);
    add(cifte);
    add(git);
  }
}

class RackActionButton extends PositionComponent with TapCallbacks {
  final String label;
  final Vector2 targetPosition;
  final Vector2 startPosition;
  final VoidCallback onTap;
  bool _pressed = false;
  late final TextPaint _textPaint;
  late final double _lineHeight;

  RackActionButton({
    required this.label,
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
    _textPaint = TextPaint(
      style: TextStyle(
        color: Color(0xFFF6D783),
        fontSize: size.y >= 150 ? 30 : 22,
        fontWeight: FontWeight.w700,
        height: 1.0,
      ),
    );
    _lineHeight = size.y >= 150 ? 34 : 24;
    add(RectangleHitbox(size: size, anchor: Anchor.topLeft));

    add(
      MoveEffect.to(
        targetPosition,
        EffectController(duration: 0.32, curve: Curves.easeOutBack),
      ),
    );
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    final r = RRect.fromRectAndRadius(rect, const Radius.circular(16));

    final body = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF2A352E), Color(0xFF0F1612)],
      ).createShader(rect);
    final border = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFF0CC7D), Color(0xFFB8842D)],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    final inner = Paint()
      ..color = const Color(0x33FFF6D8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final gloss = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x44FFF2CD), Color(0x00FFF2CD)],
        stops: [0.0, 0.65],
      ).createShader(Rect.fromLTWH(0, 0, size.x, size.y * 0.55));

    if (_pressed) {
      canvas.save();
      final cx = size.x / 2;
      final cy = size.y / 2;
      canvas.translate(cx, cy);
      canvas.scale(0.98, 0.98);
      canvas.translate(-cx, -cy);
    }
    canvas.drawRRect(r, body);
    canvas.drawRRect(r, gloss);
    canvas.drawRRect(r, border);
    canvas.drawRRect(r.deflate(5), inner);
    final lines = label.split(' ');
    final totalHeight = lines.length * _lineHeight;
    var y = (size.y - totalHeight) / 2 + (_lineHeight / 2);
    for (final line in lines) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: line,
          style: TextStyle(
            color: const Color(0xFFF6D783),
            fontSize: size.y >= 150 ? 30 : 22,
            fontWeight: FontWeight.w700,
            height: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final w = textPainter.width;
      final x = (size.x - w) / 2;
      _textPaint.render(
        canvas,
        line,
        Vector2(x, y),
        anchor: Anchor.topLeft,
      );
      y += _lineHeight;
    }
    if (_pressed) canvas.restore();
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (_pressed) return;
    _pressed = true;
    add(
      ScaleEffect.to(
        Vector2.all(0.96),
        EffectController(duration: 0.06, curve: Curves.easeOut),
      ),
    );
    onTap();
  }

  @override
  void onTapUp(TapUpEvent event) {
    _pressed = false;
    add(
      ScaleEffect.to(
        Vector2.all(1.0),
        EffectController(duration: 0.08, curve: Curves.easeOut),
      ),
    );
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    _pressed = false;
    add(
      ScaleEffect.to(
        Vector2.all(1.0),
        EffectController(duration: 0.08, curve: Curves.easeOut),
      ),
    );
  }
}
