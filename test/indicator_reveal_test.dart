import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/game/rack/tile_component.dart';
import 'tile_visual_identity_test.dart' as fixture;

void main() {
  testWidgets('opponent indicator travels to indicator and returns without changing rack', (tester) async {
    final game = await fixture.mount(tester);
    game.pauseEngine();
    game.debugPrepareLatencyState(14);
    final indicator = fixture.visual('indicator')..position = Vector2(860, 270);
    game.indicatorTileComponent = indicator;
    game.world.add(indicator);
    final event = <String, dynamic>{'id': 'receipt-1', 'table_id': 'visual-test',
      'player_id': 'opponent', 'round_no': 1};
    expect(game.debugReceiveIndicatorReveal({...event, 'round_no': 2}, opponent: 'opponent'), isFalse);
    expect(game.debugReceiveIndicatorReveal({...event, 'table_id': 'other'}, opponent: 'opponent'), isFalse);
    expect(game.debugReceiveIndicatorReveal({...event, 'player_id': 'outsider'}, opponent: 'opponent'), isFalse);
    game.debugIndicatorBonusState(playing: false);
    expect(game.debugReceiveIndicatorReveal(event, opponent: 'opponent'), isFalse);
    game.debugIndicatorBonusState();
    final rackBefore = Map.of(game.occupiedSlots);
    expect(game.debugReceiveIndicatorReveal(event, opponent: 'opponent'), isTrue);
    expect(game.debugReceiveIndicatorReveal(event, opponent: 'opponent'), isFalse);
    await tester.runAsync(() => game.ready());
    game.update(0);
    await tester.pump();
    final tile = game.world.children.whereType<TileComponent>()
      .singleWhere((t) => t.id == 'indicator-reveal:receipt-1');
    expect(tile.currentSlotIndex, isNull);
    expect(tile.isLocked, isTrue);
    final start = tile.position.clone();
    game.update(.18);
    expect(tile.position.distanceTo(indicator.position), lessThan(.01));
    game.update(.175);
    expect(tile.angle.abs(), greaterThan(1));
    game.update(.175);
    expect(tile.angle, closeTo(0, .001));
    game.update(.2);
    expect(tile.position.distanceTo(start), lessThan(.01));
    game.update(.01);
    await tester.pump();
    expect(tile.isRemoving || !tile.isMounted, isTrue);
    expect(game.occupiedSlots, rackBefore);
    expect(game.tileComponentMap, isEmpty);
  });
}
