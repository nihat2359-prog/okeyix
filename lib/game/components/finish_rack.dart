import 'dart:ui';

import 'package:audioplayers/audioplayers.dart' as jo;
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:okeyix/game/okey_game.dart';
import 'package:okeyix/game/rack/tile_component.dart';
import 'package:okeyix/services/celebration_service.dart';
import 'package:okeyix/services/feedback_settings_service.dart';

final _player = jo.AudioPlayer();

class FinishRack extends PositionComponent with HasGameRef<OkeyGame> {
  final List<Map<String, dynamic>> slots;
  final String winnerName;
  final bool isWinner;
  final bool isSpectator;
  FinishRack(this.slots, this.winnerName, this.isWinner, this.isSpectator);
  Future<void> onLoad() async {
    _playResultSound();
    position = Vector2(
      gameRef.size.x / 2,
      gameRef.size.y / 2 + 100, // aşağı kaydır
    );
    anchor = Anchor.center;
    priority = 999999;
    final bgWidth = gameRef.size.x * 1.5;
    final bgHeight = gameRef.size.y * 1;

    add(
      RoundedBackground(Vector2(bgWidth, bgHeight))
        ..position = Vector2(-160, -240)
        ..anchor = Anchor.center
        ..priority = -1,
    );

    add(
      TextComponent(
        text: _getResultText(),
        position: Vector2(380, -170),
        anchor: Anchor.center,
        textRenderer: TextPaint(
          style: TextStyle(
            fontSize: 62,
            fontWeight: FontWeight.w900,
            foreground: Paint()
              ..shader = const LinearGradient(
                colors: [
                  Color(0xFFFFE082),
                  Color(0xFFFFC107),
                  Color(0xFFFFA000),
                ],
              ).createShader(const Rect.fromLTWH(0, 0, 200, 50)),
            shadows: [
              Shadow(color: Colors.amber.withOpacity(0.8), blurRadius: 20),
            ],
          ),
        ),
      ),
    );

    add(
      TextComponent(
        text: winnerName,
        position: Vector2(0, -90),
        anchor: Anchor.center,
        textRenderer: TextPaint(
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 18,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );

    final tileWidth = 75.0;
    final spacing = 9.0;

    final totalWidth = tileWidth - 10 * spacing;

    for (final s in slots) {
      final tile = s['tile'];
      final i = s['i'];

      if (tile == null) continue;

      final isTop = i <= 12;
      final col = isTop ? i : i - 13;

      final startX = -totalWidth / 2;

      final x = startX + col * (tileWidth + spacing);
      final y = isTop ? 60.0 : -60.0;

      add(
        TileComponent(
          position: Vector2(x, y),
          colorType: _stringToTileColor(tile['color']),
          value: tile['number'],
          isJoker: tile['joker'] ?? false,
          isFakeJoker: tile['fake_joker'] ?? false,
        ),
      );
    }
  }

  String _getResultText() {
    if (isSpectator) {
      return "$winnerName KAZANDI";
    }

    return isWinner ? "KAZANDIN" : "KAYBETTİN";
  }

  void _playResultSound() {
    if (!FeedbackSettingsService.soundEnabled) return;

    if (isSpectator || isWinner) {
      _player.play(jo.AssetSource('sounds/win.mp3'));
      CelebrationService.showConfetti();
    } else {
      _player.play(jo.AssetSource('sounds/lose.mp3'));
    }

    FeedbackSettingsService.triggerHaptic();
  }

  TileColorType _stringToTileColor(String c) {
    switch (c) {
      case 'red':
        return TileColorType.red;
      case 'blue':
        return TileColorType.blue;
      case 'black':
        return TileColorType.black;
      case 'yellow':
        return TileColorType.yellow;
      default:
        return TileColorType.red;
    }
  }
}

class RoundedBackground extends PositionComponent {
  final Vector2 sizeRect;

  RoundedBackground(this.sizeRect);

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, sizeRect.x, sizeRect.y);

    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(30));

    final fill = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xE0121821), Color(0xD00A0F16)],
      ).createShader(rect);
    canvas.drawRRect(rrect, fill);

    final outerStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0x88FFD36A);
    canvas.drawRRect(rrect, outerStroke);

    final inner = RRect.fromRectAndRadius(
      rect.deflate(10),
      const Radius.circular(24),
    );
    final innerStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x334FC3FF);
    canvas.drawRRect(inner, innerStroke);

    final softGlow = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14)
      ..color = const Color(0x224FC3FF);
    canvas.drawRRect(inner, softGlow);
  }
}
