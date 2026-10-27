import 'package:flame/components.dart';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'tile_visual_identity_test.dart' as fixture;

Future<fixture.VisualGame> seeded(WidgetTester tester, List<int> slots) async {
  final game = await fixture.mount(tester);
  for (var i = 0; i < slots.length; i++) {
    final tile = fixture.visual('tile-$i');
    tile.currentSlotIndex = slots[i];
    tile.position = game.slotPositions[slots[i]].clone();
    game.tileComponentMap[tile.id] = tile;
    game.occupiedSlots[slots[i]] = tile;
    game.world.add(tile);
  }
  await fixture.settle(tester, game);
  return game;
}

void expectUniqueRack(fixture.VisualGame game, int count) {
  expect(game.tileComponentMap.length, count);
  expect(game.occupiedSlots.length, count);
  expect(game.occupiedSlots.values.toSet().length, count);
  for (final tile in game.tileComponentMap.values) {
    expect(tile.currentSlotIndex, isNotNull, reason: tile.id);
    expect(game.occupiedSlots[tile.currentSlotIndex], same(tile));
    expect(tile.position.distanceTo(game.slotPositions[tile.currentSlotIndex!]), lessThan(.01));
  }
}

List<Map<String, dynamic>> snapshot(fixture.VisualGame game) => [
  for (final id in game.tileComponentMap.keys) fixture.payload(id),
];

void main() {
  for (final fullRow in [false, true]) {
    testWidgets('confirmed draw retains all tiles when right side is full; fullRow=$fullRow', (tester) async {
      final slots = fullRow ? [...List.generate(13, (i) => i), 13]
          : [...List.generate(12, (i) => i + 1), 13, 14];
      final game = await seeded(tester, slots);
      final previous = Map.of(game.tileComponentMap);
      final drawn = fixture.visual('draw');
      drawn.position = game.slotPositions[5].clone();
      game.tileComponentMap[drawn.id] = drawn;
      game.world.add(drawn);
      game.insertIntoRow(5, drawn);
      await fixture.settle(tester, game);
      expectUniqueRack(game, 15);
      expect(drawn.currentSlotIndex, fullRow ? 14 : 5);
      for (final entry in previous.entries) {
        expect(game.tileComponentMap[entry.key], same(entry.value));
      }
      final assigned = {for (final t in game.tileComponentMap.values) t.id: t.currentSlotIndex};
      game.debugSyncVisualHand(snapshot(game));
      await fixture.settle(tester, game);
      expectUniqueRack(game, 15);
      expect({for (final t in game.tileComponentMap.values) t.id: t.currentSlotIndex}, assigned);
    });
  }

  for (final existingTile in [false, true]) {
    testWidgets('animated neighbour cannot steal the target slot; existingTile=$existingTile', (tester) async {
      final game = await seeded(tester, [...List.generate(7, (i) => i), ...List.generate(7, (i) => i + 13)]);
      final neighbour = game.tileComponentMap['tile-2']!;
      final occupant = game.tileComponentMap['tile-3']!;
      final tile = existingTile ? game.tileComponentMap['tile-0']! : fixture.visual('draw');
      if (existingTile) {
        tile.originalSlotIndex = 0;
        tile.currentSlotIndex = null;
        game.occupiedSlots.remove(0);
      } else {
        game.tileComponentMap[tile.id] = tile;
        game.world.add(tile);
      }
      neighbour.position = game.slotPositions[3].clone();
      // Represent an in-flight preview so cleanup snaps its unchanged owner.
      game.isTempShiftActive = true;
      tile.position = game.slotPositions[3].clone();
      game.insertIntoRow(3, tile);
      game.clearTemporaryShift();
      await fixture.settle(tester, game);
      expectUniqueRack(game, existingTile ? 14 : 15);
      expect(tile.currentSlotIndex, 3);
      expect(occupant.currentSlotIndex, 4);
      expect(neighbour.currentSlotIndex, 2);
      expect(game.world.children.where((t) => identical(t, neighbour)).length, 1);
    });
  }

  testWidgets('incremental sync repairs an existing slotless tile without redealing', (tester) async {
    final game = await seeded(tester, List.generate(15, (i) => i));
    final before = Map.of(game.tileComponentMap);
    final lost = game.tileComponentMap['tile-5']!;
    game.occupiedSlots.remove(5);
    lost.currentSlotIndex = null;
    lost.position = Vector2.zero();
    game.debugSyncVisualHand(snapshot(game));
    await fixture.settle(tester, game);
    expectUniqueRack(game, 15);
    for (final entry in before.entries) {
      expect(game.tileComponentMap[entry.key], same(entry.value));
      expect(entry.value.currentSlotIndex, int.parse(entry.key.split('-').last));
    }
  });

  testWidgets('incremental sync repairs conflicting slots while preserving other positions', (tester) async {
    final game = await seeded(tester, List.generate(14, (i) => i));
    final before = Map.of(game.tileComponentMap);
    final bad = game.tileComponentMap['tile-8']!;
    bad.currentSlotIndex = 3;
    bad.position = game.slotPositions[3].clone();
    game.debugSyncVisualHand(snapshot(game));
    await fixture.settle(tester, game);
    expectUniqueRack(game, 14);
    expect(bad.currentSlotIndex, 8);
    for (final entry in before.entries) {
      expect(game.tileComponentMap[entry.key], same(entry.value));
      if (!identical(entry.value, bad)) {
        expect(entry.value.currentSlotIndex, int.parse(entry.key.split('-').last));
      }
    }
  });

  testWidgets('cancelled drag cannot overwrite another owner of its original slot', (tester) async {
    final game = await seeded(tester, List.generate(14, (i) => i));
    final dragged = game.tileComponentMap['tile-0']!;
    final occupant = game.tileComponentMap['tile-1']!;
    dragged.originalSlotIndex = 1;
    dragged.currentSlotIndex = null;
    game.occupiedSlots.remove(0);
    game.restoreRackTile(dragged);
    await fixture.settle(tester, game);
    expectUniqueRack(game, 14);
    expect(game.occupiedSlots[1], same(occupant));
  });

  testWidgets('finish preparation repairs missing tiles but keeps the last tile separate', (tester) async {
    final game = await seeded(tester, List.generate(15, (i) => i));
    final last = game.tileComponentMap['tile-14']!;
    last.currentSlotIndex = null;
    game.occupiedSlots.remove(14);
    final lost = game.tileComponentMap['tile-5']!;
    lost.currentSlotIndex = null;
    lost.position = Vector2.zero();
    final slots = game.debugFinishSlots(last)!;
    final ids = slots.where((s) => s['tile'] != null)
        .map((s) => (s['tile'] as Map)['id']).toSet();
    expect(ids.length, 14);
    expect(ids, contains(lost.id));
    expect(ids, isNot(contains(last.id)));
    expect(last.currentSlotIndex, isNull);
    expect(game.tileComponentMap.length, 15);
  });

  testWidgets('repeated rack moves retain every physical tile and unique slot', (tester) async {
    final game = await seeded(tester, [...List.generate(7, (i) => i), ...List.generate(7, (i) => i + 13)]);
    final original = Map.of(game.tileComponentMap);
    final random = math.Random(27102026);
    for (var attempt = 0; attempt < 150; attempt++) {
      final tile = game.tileComponentMap['tile-${random.nextInt(14)}']!;
      tile.originalSlotIndex = tile.currentSlotIndex;
      tile.originalPosition = tile.position.clone();
      game.occupiedSlots.remove(tile.currentSlotIndex);
      tile.currentSlotIndex = null;
      final target = random.nextInt(26);
      tile.position = game.slotPositions[target].clone();
      game.insertIntoRow(target, tile);
      await fixture.settle(tester, game);
      expectUniqueRack(game, 14);
      for (final entry in original.entries) {
        expect(game.tileComponentMap[entry.key], same(entry.value));
      }
    }
  });

  testWidgets('finish preparation does not reuse an attached finishing tile slot', (tester) async {
    final game = await seeded(tester, List.generate(15, (i) => i));
    final last = game.tileComponentMap['tile-0']!;
    final lost = game.tileComponentMap['tile-5']!;
    lost.currentSlotIndex = null;
    lost.position = Vector2.zero();
    final slots = game.debugFinishSlots(last)!;
    final ids = slots.where((s) => s['tile'] != null)
        .map((s) => (s['tile'] as Map)['id']).toSet();
    expect(ids.length, 14);
    expect(ids, isNot(contains(last.id)));
    expect(last.currentSlotIndex, 0);
    expectUniqueRack(game, 15);
  });
}
