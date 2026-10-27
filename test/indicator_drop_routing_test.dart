import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/game/rack/tile_component.dart';
import 'package:okeyix/game/rack/preview_component.dart';
import 'tile_visual_identity_test.dart' as fixture;

class IndicatorDropGame extends fixture.VisualGame {
  bool indicatorArea = true;
  bool claimed = false;
  int indicatorCalls = 0, finishCalls = 0;
  @override
  bool isPointNearIndicator(dynamic point) => indicatorArea;
  @override
  bool isPointNearClosedPile(dynamic point) => true;
  @override
  Future<bool> tryClaimIndicatorBonus(TileComponent tile) async {
    indicatorCalls++;
    return claimed;
  }
  @override
  Future<bool> finishWithTile(TileComponent tile) async {
    finishCalls++;
    return false;
  }
}

void main() {
  for (final indicatorArea in [true, false]) {
  for (final claimed in [false, true]) {
    testWidgets('indicator and finish drops stay separate; indicator=$indicatorArea claimed=$claimed', (tester) async {
      final game = IndicatorDropGame()..claimed = claimed..indicatorArea = indicatorArea;
      await tester.pumpWidget(GameWidget(game: game));
      await tester.runAsync(() => game.loaded);
      game.previewBox = PreviewComponent(size: game.size.clone());
      await tester.runAsync(() => game.images.loadAll(['tile_base.png', 'tile_back.png']));
      final tile = fixture.visual('indicator-copy');
      tile.currentSlotIndex = 0;
      tile.originalSlotIndex = 0;
      game.occupiedSlots[0] = tile;
      game.tileComponentMap[tile.id] = tile;
      game.world.add(tile);
      await fixture.settle(tester, game);
      await tile.onDragEnd(DragEndEvent(1, DragEndDetails()));
      await fixture.settle(tester, game);
      expect(game.indicatorCalls, indicatorArea ? 1 : 0);
      expect(game.finishCalls, indicatorArea ? 0 : 1);
      expect(game.tileComponentMap[tile.id], same(tile));
      expect(game.occupiedSlots[0], same(tile));
      expect(tile.position.distanceTo(game.slotPositions[0]), lessThan(.001));
    });
  }
  }
}
