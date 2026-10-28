import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/effects.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/engine/models/tile.dart';
import 'package:okeyix/game/okey_game.dart';
import 'package:okeyix/game/rack/tile_component.dart';

class LocalTurnGame extends OkeyGame {
  LocalTurnGame() : super(tableId: 'joker-guard', isCreator: false);
  @override
  bool get isMyTurnForLocalUser => true;
}

class VisualGame extends OkeyGame {
  int doubleTaps = 0;
  bool discardAnimationCompleted = false;
  @override
  void onTileDoubleTap(TileComponent tile) {
    doubleTaps++;
    tile.add(MoveEffect.to(Vector2(350, 150), EffectController(duration: 0.18),
      onComplete: () => discardAnimationCompleted = true));
  }
  VisualGame() : super(tableId: 'visual-test', isCreator: false);
  @override
  Future<void> onLoad() async {
    world = World();
    add(world);
    camera.world = world;
    for (var i = 0; i < 26; i++) {
      slotPositions.add(Vector2(100 + i * 30, 300));
    }
  }

  @override
  void onAttach() {}
  @override
  void onDetach() {}
  @override
  void onRemove() {}
}

Map<String, dynamic> payload(
  String id, {
  bool fake = false,
  int number = 7,
  String color = 'red',
}) => {
  'id': id,
  'number': number,
  'color': color,
  'is_joker': false,
  'is_fake_joker': fake,
};
TileComponent visual(String id, {bool joker = false, bool fake = false}) =>
    TileComponent(
      tile: TileModel(
        id: id,
        value: 7,
        color: TileColor.red,
        isJoker: joker,
        isFakeJoker: fake,
      ),
      position: Vector2.zero(),
    );

Future<VisualGame> mount(WidgetTester tester) async {
  final game = VisualGame();
  await tester.pumpWidget(GameWidget(game: game));
  await tester.runAsync(() => game.loaded.timeout(const Duration(seconds: 3)));
  await tester.runAsync(
    () => game.images.loadAll(['tile_base.png', 'tile_back.png']),
  );
  await tester.pump();
  return game;
}

Future<void> settle(WidgetTester tester, VisualGame game) async {
  await tester.runAsync(() => game.ready().timeout(const Duration(seconds: 3)));
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('rack settling never overshoots and repeated targets do not restart it', (tester) async {
    final game = await mount(tester);
    final tile = visual('smooth-settle');
    game.world.add(tile);
    await settle(tester, game);
    tile.position.setZero();
    tile.moveOnRack(Vector2(100, 0));
    var previous = 0.0;
    for (var frame = 0; frame < 10; frame++) {
      tile.update(.02);
      expect(tile.position.x, inInclusiveRange(previous, 100));
      previous = tile.position.x;
      tile.moveOnRack(Vector2(100, 0));
    }
    expect(tile.position.x, 100);
    // No-op targets must not schedule another visible movement.
    tile.update(.2);
    expect(tile.position.x, 100);
    expect(tile.isMovingOnRack, isFalse);
  });
  testWidgets('preview cleanup and snapshots keep a smooth move instead of snapping', (tester) async {
    final game = await mount(tester);
    final hand = List.generate(14, (i) => payload('smooth-$i'));
    game.debugSyncVisualHand(hand, initial: true);
    await settle(tester, game);
    final tile = game.tileComponentMap['smooth-0']!;
    final target = game.slotPositions[tile.currentSlotIndex!].clone();
    tile.position = target + Vector2(50, -20);
    final before = tile.position.clone();
    game.isTempShiftActive = true;
    game.clearTemporaryShift();
    expect(tile.position, before);
    tile.update(.04);
    final mid = tile.position.clone();
    game.debugSyncVisualHand(hand);
    expect(tile.position, mid);
    tile.update(.2);
    expect(tile.position.distanceTo(target), lessThan(.001));
    expect(game.occupiedSlots[tile.currentSlotIndex], same(tile));
  });
  testWidgets('preview cleanup preserves an automatic discard animation', (tester) async {
    final game = await mount(tester);
    game.debugSyncVisualHand(List.generate(14, (i) => payload('discard-preview-$i')), initial: true);
    await settle(tester, game);
    final tile = game.tileComponentMap['discard-preview-0']!;
    var completed = false;
    final target = Vector2(350, 150);
    tile.isLocked = true;
    tile.add(MoveEffect.to(target, EffectController(duration: 0.18),
      onComplete: () => completed = true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    game.isTempShiftActive = true;
    game.clearTemporaryShift();
    game.moveTileSmooth(tile, game.slotPositions[tile.currentSlotIndex!]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 50));
    expect(completed, isTrue);
    expect(tile.position.distanceTo(target), lessThan(0.001));
  });

  testWidgets('preview reset before the next frame cannot restart rack motion', (tester) async {
    final game = await mount(tester);
    game.debugSyncVisualHand(List.generate(14, (i) => payload('queued-$i')), initial: true);
    await settle(tester, game);
    final tile = game.tileComponentMap['queued-0']!;
    final slot = tile.currentSlotIndex!;
    // Preview and drop can happen before Flame mounts an added effect.
    game.moveTileSmooth(tile, game.slotPositions[slot] + Vector2(40, -15));
    game.isTempShiftActive = true;
    game.clearTemporaryShift();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tile.position.distanceTo(game.slotPositions[slot]), lessThan(0.001));
  });

  testWidgets('rapid rack retargeting finishes exactly at the latest slot', (tester) async {
    final game = await mount(tester);
    final tile = visual('retarget');
    game.world.add(tile);
    await settle(tester, game);
    game.moveTileSmooth(tile, Vector2(200, 300));
    await tester.pump(const Duration(milliseconds: 40));
    game.moveTileSmooth(tile, Vector2(350, 300));
    game.moveTileSmooth(tile, Vector2(250, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tile.position.distanceTo(Vector2(250, 300)), lessThan(0.001));
  });

  testWidgets('pending closed draw has a neutral face rather than an okey back', (tester) async {
    final game = await mount(tester);
    final pending = visual('__closed_draw_preview__', joker: true);
    pending.showAwaitingDrawConfirmation();
    game.world.add(pending);
    await settle(tester, game);
    expect(pending.children.contains(pending.backSprite), isFalse);
    expect(pending.children.whereType<TextComponent>().single.text, 'Bekleniyor');
  });

  testWidgets('clearing a preview stops its effect and pins tiles to slot centers', (tester) async {
    final game = await mount(tester);
    game.debugSyncVisualHand(List.generate(14, (i) => payload('snap-$i')), initial: true);
    await settle(tester, game);
    final tile = game.tileComponentMap['snap-0']!;
    final slot = tile.currentSlotIndex!;
    tile.position += Vector2(8, -13);
    game.moveTileSmooth(tile, tile.position + Vector2(40, 20));
    game.isTempShiftActive = true;
    await tester.pump();
    game.clearTemporaryShift();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tile.position.distanceTo(game.slotPositions[slot]), lessThan(0.01));
    expect(tile.children.whereType<MoveEffect>(), isEmpty);
  });
  test('real okey cannot be discarded by double tap or rack drag', () async {
    final game = LocalTurnGame();
    final joker = visual('real-okey', joker: true);
    // These paths must reject before turn lookup, animation or any RPC.
    game.onTileDoubleTap(joker);
    await game.autoDiscard(joker);
    expect(await game.discardTile(joker), isFalse);
    expect(joker.children.whereType<MoveEffect>(), isEmpty);
  });
  testWidgets('two rack taps reach the automatic discard handler', (tester) async {
    final game = await mount(tester);
    game.camera.viewfinder.anchor = Anchor.topLeft;
    final tile = visual('tap-target', joker: true)..position = Vector2(150, 150);
    game.world.add(tile);
    await settle(tester, game);
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.componentsAtPoint(Vector2(150, 150)).contains(tile), isTrue);
    await tester.tapAt(const Offset(150, 150));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(const Offset(150, 150));
    expect(game.doubleTaps, 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 50));
    expect(game.discardAnimationCompleted, isTrue);
    expect(tile.position.x, closeTo(350, 0.1));
  });
  test('source draw dropped between rack rows selects an empty slot', () {
    final game = VisualGame();
    game.slotPositions.addAll([
      Vector2(100, 100), Vector2(192, 100),
      Vector2(100, 236), Vector2(192, 236),
    ]);
    final gap = Vector2(146, 168);
    expect(game.getNearestSlotIndex(gap), isNull);
    game.occupySlot(0, visual('occupied'));
    final slot = game.sourceDrawDropSlot(gap);
    expect(slot, isNotNull);
    expect(game.isSlotOccupied(slot!), isFalse);
    expect(game.sourceDrawDropSlot(Vector2(146, 400)), isNull);
    expect(game.sourceDrawDropSlot(Vector2(-100, 168)), isNull);
    expect(game.sourceDrawDropSlot(Vector2(192, 100)), 1);
    for (var i = 1; i < 4; i++) {
      game.occupySlot(i, visual('occupied-$i'));
    }
    expect(game.sourceDrawDropSlot(gap), isNull);
  });

  test('draw response uses only the committed hand for the requested table', () {
    final hand = List.generate(15, (i) => payload('draw-$i'));
    final response = {'ok': true, 'table_id': 'visual-test', 'hand': hand};
    expect(OkeyGame.committedDrawHand(response, 'visual-test'), same(hand));
    expect(OkeyGame.committedDrawHand(response, 'other-table'), isNull);
    expect(OkeyGame.committedDrawHand({...response, 'ok': false}, 'visual-test'), isNull);
    expect(OkeyGame.committedDrawHand(null, 'visual-test'), isNull);
    expect(OkeyGame.committedDrawHand({...response, 'hand': hand.take(14).toList()}, 'visual-test'), isNull);
    expect(OkeyGame.committedDrawHand({...response, 'hand': [...hand.take(14), hand.first]}, 'visual-test'), isNull);
  });

  testWidgets('committed draw reveals its number on the next rack frame', (tester) async {
    final game = await mount(tester);
    final hand = List.generate(14, (i) => payload('hand-$i'));
    game.debugSyncVisualHand(hand, initial: true);
    await settle(tester, game);
    final response = {
      'ok': true, 'table_id': 'visual-test',
      'hand': [...hand, payload('drawn', number: 9)],
    };
    game.debugSyncVisualHand(OkeyGame.committedDrawHand(response, 'visual-test')!);
    await tester.runAsync(() => game.ready());
    await tester.pump();
    final drawn = game.world.children.whereType<TileComponent>().singleWhere((t) => t.id == 'drawn');
    expect(drawn.isFaceDown, isFalse);
    expect(drawn.children.whereType<TextComponent>().any((t) => t.text == '9'), isTrue);
  });

  testWidgets(
    'repeated initial snapshots before mount create one component per physical ID',
    (tester) async {
      final game = await mount(tester);
      final hand = List.generate(
        14,
        (i) => payload(
          'physical-$i',
          fake: i == 13,
          number: i < 2 || i == 13 ? 7 : i,
          color: i < 2 || i == 13 ? 'red' : 'blue',
        ),
      );
      // Repeated physical ID is malformed input; never invent a third component.
      final repeated = [...hand, hand.first];
      game.debugSyncVisualHand(repeated, initial: true);
      game.debugSyncVisualHand(hand, initial: true);
      await settle(tester, game);
      final tiles = game.world.children.whereType<TileComponent>().toList();
      expect(tiles.length, 14);
      expect(tiles.map((t) => t.id).toSet().length, 14);
      expect(tiles.where((t) => t.isFakeJoker).length, 1);
      game.debugSyncVisualHand(hand);
      await settle(tester, game);
      expect(game.world.children.whereType<TileComponent>().length, 14);
    },
  );

  testWidgets(
    'indicator remains separate and keeps its physical ID across deck refreshes',
    (tester) async {
      final game = await mount(tester);
      game.debugSyncIndicator([payload('indicator'), payload('drawable')]);
      game.debugSyncIndicator([payload('indicator'), payload('drawable')]);
      await settle(tester, game);
      game.debugSyncIndicator([payload('indicator')]);
      await settle(tester, game);
      expect(game.indicatorTileComponent!.id, 'indicator');
      expect(game.closedPile.map((t) => t.id), ['indicator']);
      expect(
        game.world.children
            .whereType<TileComponent>()
            .where((t) => t.id == 'indicator')
            .length,
        1,
      );
      expect(game.tileComponentMap.containsKey('indicator'), isFalse);
    },
  );

  testWidgets('pending visual removed before mount never appears later', (
    tester,
  ) async {
    final game = await mount(tester);
    final tile = visual('pending')..isLocked = true;
    game.world.add(tile);
    game.debugClearPendingVisual(tile);
    await settle(tester, game);
    expect(
      game.world.children.whereType<TileComponent>().where(
        (t) => t.id == 'pending',
      ),
      isEmpty,
    );
  });

  testWidgets(
    'cancelled drag restores valid tile but rejects invalidated round',
    (tester) async {
      final game = await mount(tester);
      final valid = visual('valid')..isLocked = true;
      game.debugRestoreDiscard(valid);
      await tester.pump(const Duration(milliseconds: 50));
      await settle(tester, game);
      expect(valid.isMounted, isTrue);
      final stale = visual('stale')..isLocked = true;
      game.debugRestoreDiscard(stale, invalidate: true);
      await tester.pump(const Duration(milliseconds: 50));
      await settle(tester, game);
      expect(stale.isMounted, isFalse);
    },
  );

  testWidgets(
    'real joker toggles both faces without reloading or changing identity; fake stays distinct',
    (tester) async {
      final game = await mount(tester);
      final joker = visual('real', joker: true);
      final fake = visual('fake', fake: true);
      game.world.addAll([joker, fake]);
      await settle(tester, game);
      expect(joker.isFaceDown, isTrue);
      for (var i = 0; i < 3; i++) {
        joker.toggleFace();
        await settle(tester, game);
        expect(joker.isFaceDown, isFalse);
        expect(
          joker.children.whereType<TextComponent>().any((t) => t.text == '7'),
          isTrue,
        );
        joker.toggleFace();
        await settle(tester, game);
        expect(joker.isFaceDown, isTrue);
        expect(joker.children.whereType<TextComponent>(), isEmpty);
      }
      fake.toggleFace();
      expect(fake.isFaceDown, isFalse);
      expect(fake.children.whereType<TextComponent>(), isEmpty);
      expect(joker.id, 'real');
      expect(fake.id, 'fake');
    },
  );
}
