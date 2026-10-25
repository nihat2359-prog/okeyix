import 'finish_tile_layout.dart';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'package:okeyix/engine/models/tile.dart';

import 'package:okeyix/game/okey_game.dart';
import 'package:okeyix/game/rack/tile_component.dart';

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
    // ğŸ”¥ TÃœM SAHNEYÄ° ORTALA
    position = gameRef.size / 2;
    anchor = Anchor.center;
    priority = 9999;

    // ğŸ”¥ FULL SCREEN KARARTMA

    final vp = gameRef.camera.viewport.size;
    // ğŸ”¥ FULL SCREEN OVERLAY
    add(
      RectangleComponent(
        size: vp, // ğŸ”¥ DOÄRU
        position: -vp / 2, // ğŸ”¥ DOÄRU
        paint: Paint()..color = Colors.black.withOpacity(0.7),
      ),
    );

    // ğŸ”¥ RACK PNG
    final image = await gameRef.images.load('rack.png');

    final rackWidth = vp.x * 0.60;

    // oranÄ± koru
    final aspect = image.height / image.width;

    final rackHeight = rackWidth * aspect;

    rack = SpriteComponent(
      sprite: Sprite(image),
      size: Vector2(rackWidth, rackHeight),
      anchor: Anchor.center,
      position: Vector2(0, -vp.y * 0.08), // yukarÄ±
    );

    add(rack);

    _buildTiles();
    _buildFinishTile();
  }

  void _buildTiles() {
    // ğŸ”¥ rack ile aynÄ± offset (Ã¼stte konum)

    // ğŸ”¥ rack boyutuna baÄŸlÄ± hesap
    final rackWidth = rack.size.x;
    final rackHeight = rack.size.y;

    // ğŸ”¥ slotlarÄ± sÄ±rala
    slots.sort((a, b) => (a['i'] as int).compareTo(b['i'] as int));

    for (final s in slots) {
      final i = s['i'] as int;

      final col = i % 13;
      // Rack indexing is: 0-12 bottom row, 13-25 top row.
      final isTop = i >= 13;

      // X yerleşimi: rack içinde 13 kolona dengeli dağıt.
      const scaleX = 0.80;
      const offsetX = 0.50;

      // Y yerleşimi: iki sıra arası sabit.

      // ---------- X ----------
      final step = 1 / 13;
      final normalizedX = (col + 0.5) * step;
      final centeredX = (normalizedX - 0.5) * scaleX;
      final x = (centeredX + offsetX) * rackWidth;

      // ---------- Y ----------

      final tile = s['tile'];
      if (tile == null) continue;

      final model = _tileModelFromPayload(tile);
      if (model == null) return;

      final t = TileComponent(tile: model, position: Vector2(x, 0));
      final slotWidthPx = (rackWidth * scaleX) / 13;
      final baseTileWidth = t.size.x <= 0 ? 100.0 : t.size.x;
      final clampedScale = finishTileScale(slotWidthPx, baseTileWidth);
      t.scale = Vector2.all(clampedScale);
      t.position.y = finishTileCenterY(
        isTop,
        rackHeight,
        t.size.y * clampedScale,
      );
      rack.add(t);
    }
  }

  void _buildFinishTile() {
    final tile = finishTile;

    //final y = rackHeight * 0.55;
    final model = _tileModelFromPayload(tile);
    if (model == null) return;

    final t = TileComponent(tile: model, position: Vector2(0, 60));
    final rackWidth = rack.size.x;
    final slotWidthPx = (rackWidth * 0.80) / 13;
    final baseTileWidth = t.size.x <= 0 ? 100.0 : t.size.x;
    t.scale = Vector2.all(finishTileScale(slotWidthPx, baseTileWidth) * 1.15);
    t.position = Vector2(
      rack.position.x,
      rack.position.y - rack.size.y / 2 -
          t.size.y * t.scale.y / 2 - gameRef.camera.viewport.size.y * .003,
    );

    // ğŸ”¥ glow efekti
    t.add(
      CircleComponent(
        radius: 45,
        anchor: Anchor.center,
        paint: Paint()
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20)
          ..color = Colors.amber.withOpacity(0.4),
      )..priority = -1,
    );

    add(t);
  }

  Future<void> _playResultSound() async {
    if (!FeedbackSettingsService.soundEnabled) return;
    if (_isPlayingSound) return; // ğŸ”¥ Ã‡AKIÅMA ENGEL

    _isPlayingSound = true;

    try {
      final source = jo.AssetSource(
        (isSpectator || isWinner) ? 'sounds/win.mp3' : 'sounds/lose.mp3',
      );

      await _player.play(source);
    } catch (e) {
      // ğŸ”¥ ARTIK STREAM BOZULMAZ
      debugPrint("Sound error ignored: $e");
    } finally {
      _isPlayingSound = false;
    }

    FeedbackSettingsService.triggerHaptic();
  }

  TileModel? _tileModelFromPayload(Map<String, dynamic> raw) {
    // ğŸ”¥ ID ZORUNLU
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
      id: id.toString(), // ğŸ”¥ EN KRÄ°TÄ°K
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
        // ğŸ”¥ KARARTMA
        Positioned.fill(child: Container(color: Colors.black.withOpacity(0.7))),

        // ğŸ”¥ ORTA ALAN
        Center(
          child: SizedBox(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            child: GameWidget(game: game), // aynÄ± game
          ),
        ),
      ],
    );
  }
}
