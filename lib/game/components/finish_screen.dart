import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:okeyix/engine/models/tile.dart';

import 'package:okeyix/game/okey_game.dart';
import 'package:okeyix/game/rack/tile_component.dart';
import 'package:okeyix/services/celebration_service.dart';
import 'package:okeyix/services/feedback_settings_service.dart';
import 'package:audioplayers/audioplayers.dart' as jo;

final _player = jo.AudioPlayer();

class FinishRackView extends PositionComponent with HasGameRef<OkeyGame> {
  bool _isPlayingSound = false;
  final List<Map<String, dynamic>> slots;
  final Map<String, dynamic> finishTile;
  final String winnerName;
  final bool isWinner;
  final bool isSpectator;
  final int winAmount;
  final bool isOkeyFinish;
  final bool isDoubleFinish;
  FinishRackView(
    this.slots,
    this.finishTile,
    this.winnerName,
    this.isWinner,
    this.isSpectator,
    this.winAmount,
    this.isOkeyFinish,
    this.isDoubleFinish,
  );
  late SpriteComponent rack;

  @override
  Future<void> onLoad() async {
    _playResultSound();
    // 🔥 TÜM SAHNEYİ ORTALA
    position = gameRef.size / 2;
    anchor = Anchor.center;
    priority = 9999;

    // 🔥 FULL SCREEN KARARTMA

    final vp = gameRef.camera.viewport.size;
    // 🔥 FULL SCREEN OVERLAY
    add(
      RectangleComponent(
        size: vp, // 🔥 DOĞRU
        position: -vp / 2, // 🔥 DOĞRU
        paint: Paint()..color = Colors.black.withOpacity(0.7),
      ),
    );

    // 🔥 RACK PNG
    final image = await gameRef.images.load('rack.png');

    final rackWidth = vp.x * 0.60;

    // oranı koru
    final aspect = 400 / 1380;

    final rackHeight = rackWidth * aspect;

    rack = SpriteComponent(
      sprite: Sprite(image),
      size: Vector2(rackWidth, rackHeight),
      anchor: Anchor.center,
      position: Vector2(0, -vp.y * 0.20), // yukarı
    );

    add(rack);

    rack.add(
      TextComponent(
        text: _getResultText(),
        position: Vector2(150, -20),
        anchor: Anchor.center,
        textRenderer: TextPaint(style: _getResultStyle()),
      ),
    );

    _buildTiles();
    _buildFinishTile();
  }

  @override
  void onMount() {
    super.onMount();

    Future.microtask(() {
      _playResultSound();
    });
  }

  void _buildTiles() {
    final vp = gameRef.camera.viewport.size;

    // 🔥 rack ile aynı offset (üstte konum)

    // 🔥 rack boyutuna bağlı hesap
    final rackWidth = vp.x * 0.65;
    final rackHeight = rackWidth * (400 / 1380);

    // 🔥 slotları sırala
    slots.sort((a, b) => (a['i'] as int).compareTo(b['i'] as int));

    for (final s in slots) {
      final i = s['i'] as int;

      final col = i % 13;
      // Rack indexing is: 0-12 bottom row, 13-25 top row.
      final isTop = i >= 13;

      // 🔥 X PARAM
      double scaleX = 0.75;
      double offsetX = 0.44;

      // 🔥 Y PARAM
      double centerY = 0.35;
      double rowSpacing = 0.30;

      // ---------- X ----------
      final step = 1 / 13;
      final normalizedX = (col + 0.5) * step;
      final centeredX = (normalizedX - 0.5) * scaleX;
      final x = (centeredX + offsetX) * rackWidth;

      // ---------- Y ----------
      final rowIndex = isTop ? -0.5 : 0.5;
      final normalizedY = rowIndex * rowSpacing;
      final y = (normalizedY + centerY) * rackHeight;

      final tile = s['tile'];
      if (tile == null) continue;

      final model = _tileModelFromPayload(tile);
      if (model == null) return;

      final t = TileComponent(tile: model, position: Vector2(x, y))
        ..scale = Vector2.all(0.4);
      rack.add(t);
    }
  }

  void _buildFinishTile() {
    final tile = finishTile;

    //final y = rackHeight * 0.55;
    final model = _tileModelFromPayload(tile);
    if (model == null) return;

    final t = TileComponent(tile: model, position: Vector2(0, 60))
      ..scale = Vector2.all(0.5);

    // 🔥 glow efekti
    t.add(
      CircleComponent(
        radius: 45,
        anchor: Anchor.center,
        paint: Paint()
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20)
          ..color = Colors.amber.withOpacity(0.4),
      ),
    );

    rack.add(t);
  }

  String _getResultText() {
    final amountText = "${winAmount >= 0 ? '+' : ''}$winAmount";

    if (isSpectator) {
      return "$winnerName $amountText KAZANDI";
    }

    if (isWinner) {
      if (isOkeyFinish) return "OKEY +$winAmount";
      if (isDoubleFinish) return "ÇİFT +$winAmount";

      return "KAZANDIN $amountText";
    }

    return "KAYBETTİN $amountText";
  }

  TextStyle _getResultStyle() {
    if (isSpectator) {
      return const TextStyle(
        color: Colors.white70,
        fontSize: 48,
        fontWeight: FontWeight.w800,
      );
    }

    if (isWinner) {
      return TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w900,
        foreground: Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFFFFF176), Color(0xFFFFC107), Color(0xFFFF8F00)],
          ).createShader(const Rect.fromLTWH(0, 0, 300, 80)),
        shadows: [Shadow(color: Colors.amber.withOpacity(0.9), blurRadius: 30)],
      );
    }

    return TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.w900,
      color: Colors.redAccent,
      shadows: [Shadow(color: Colors.red.withOpacity(0.8), blurRadius: 20)],
    );
  }

  Future<void> _playResultSound() async {
    if (!FeedbackSettingsService.soundEnabled) return;
    if (_isPlayingSound) return; // 🔥 ÇAKIŞMA ENGEL

    _isPlayingSound = true;

    try {
      final source = jo.AssetSource(
        (isSpectator || isWinner) ? 'sounds/win.mp3' : 'sounds/lose.mp3',
      );

      await _player.play(source);

      Future.delayed(const Duration(milliseconds: 80), () {
        if (isOkeyFinish || isDoubleFinish) {
          CelebrationService.showCoinCelebration();
        } else if (isSpectator || isWinner) {
          CelebrationService.showConfetti();
        }
      });
    } catch (e) {
      // 🔥 ARTIK STREAM BOZULMAZ
      debugPrint("Sound error ignored: $e");
    } finally {
      _isPlayingSound = false;
    }

    FeedbackSettingsService.triggerHaptic();
  }

  TileModel? _tileModelFromPayload(Map<String, dynamic> raw) {
    // 🔥 ID ZORUNLU
    final id = raw['id'];
    if (id == null || id.toString().isEmpty) {
      print("Tile payload missing id: $raw");
      return null;
    }

    // value / number
    final valueRaw = raw['number'] ?? raw['value'];
    final value = valueRaw is int ? valueRaw : int.tryParse('$valueRaw');

    // color
    final colorRaw = raw['color'];
    TileColor? color;

    if (colorRaw is int) {
      color = TileColor.values[colorRaw];
    } else if (colorRaw is String) {
      switch (colorRaw) {
        case 'red':
          color = TileColor.red;
          break;
        case 'blue':
          color = TileColor.blue;
          break;
        case 'black':
          color = TileColor.black;
          break;
        case 'yellow':
          color = TileColor.yellow;
          break;
      }
    }

    if (value == null || color == null) {
      print("Invalid tile payload: $raw");
      return null;
    }

    return TileModel(
      id: id.toString(), // 🔥 EN KRİTİK
      value: value,
      color: color,
      isJoker:
          raw['joker'] == true ||
          raw['is_joker'] == true ||
          raw['isJoker'] == true,
      isFakeJoker:
          raw['fake_joker'] == true ||
          raw['is_fake_joker'] == true ||
          raw['isFakeJoker'] == true,
    );
  }
}

class FinishOverlay extends StatelessWidget {
  final OkeyGame game;

  const FinishOverlay(this.game, {super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 🔥 KARARTMA
        Positioned.fill(child: Container(color: Colors.black.withOpacity(0.7))),

        // 🔥 ORTA ALAN
        Center(
          child: SizedBox(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            child: GameWidget(game: game), // aynı game
          ),
        ),
      ],
    );
  }
}
