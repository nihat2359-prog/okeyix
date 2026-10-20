import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/engine/models/tile.dart';
import 'package:okeyix/game/okey_game.dart';
import 'package:okeyix/game/rack/tile_component.dart';

class VisualGame extends OkeyGame {
  VisualGame() : super(tableId: 'visual-test', isCreator: false);
  @override
  Future<void> onLoad() async {
    world = World();
    add(world);
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
