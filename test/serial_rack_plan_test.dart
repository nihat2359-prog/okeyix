import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/engine/models/tile.dart';
import 'package:okeyix/game/rack/serial_rack_plan.dart';

void main() {
  TileModel tile(String id, int n, TileColor c, {bool joker = false}) =>
      TileModel(id: id, value: n, color: c, isJoker: joker);
  const black = TileColor.black;
  const yellow = TileColor.yellow;
  const red = TileColor.red;
  const blue = TileColor.blue;
  test('reported opening: singles stay together at bottom right, including 13', () {
    final hand = [
      tile('r3', 3, red), tile('u3', 3, blue), tile('b3', 3, black),
      tile('r3copy', 3, red), tile('r4', 4, red), tile('r5', 5, red),
      tile('b9', 9, black), tile('b10', 10, black),
      tile('y10', 10, yellow), tile('y11', 11, yellow),
      tile('y5', 5, yellow), tile('y7', 7, yellow),
      tile('u8', 8, blue), tile('r9', 9, red), tile('y13', 13, yellow),
    ];
    final plan = serialRackPlan(hand, columns: 13);
    expect(plan.take(6).every((s) => s >= 13), isTrue);
    expect(plan.sublist(10), [8, 9, 10, 11, 12]);
    expect(plan[7], plan[6] + 1);
    expect(plan[8], greaterThan(plan[7] + 1));
    expect(plan[9], plan[8] + 1);
    expect(plan.toSet(), hasLength(15));
  });
  test(
    'reported hand: joker completes black 7-8-9-10; loose blocks have gaps',
    () {
      final hand = [
        tile('y3', 3, yellow),
        tile('y4', 4, yellow),
        tile('y5', 5, yellow),
        tile('b9', 9, black),
        tile('b10', 10, black),
        tile('b1', 1, black),
        tile('b2', 2, black),
        tile('u2', 2, blue),
        tile('b2copy', 2, black),
        tile('u4', 4, blue),
        tile('b4', 4, black),
        tile('r1', 1, red),
        tile('r6', 6, red),
        tile('joker', 8, red, joker: true),
        tile('b7', 7, black),
      ];
      final plan = serialRackPlan(hand, columns: 13);
      int slot(String id) => plan[hand.indexWhere((t) => t.id == id)];
      expect(slot('b7'), greaterThanOrEqualTo(13));
      expect(
        [slot('joker'), slot('b9'), slot('b10')],
        [slot('b7') + 1, slot('b7') + 2, slot('b7') + 3],
      );
      expect(slot('b2'), slot('b1') + 1);
      expect(slot('u2'), greaterThan(slot('b2') + 1));
      expect(slot('b2copy'), slot('u2') + 1);
      expect(slot('u4'), greaterThan(slot('b2copy') + 1));
      expect(slot('b4'), slot('u4') + 1);
      expect(plan.toSet(), hasLength(hand.length));
    },
  );
  test('globally chooses two runs instead of a competing set', () {
    final hand = [
      tile('b1', 1, black),
      tile('b2', 2, black),
      tile('b3', 3, black),
      tile('r1', 1, red),
      tile('r2', 2, red),
      tile('r3', 3, red),
      tile('u2', 2, blue),
    ];
    final plan = serialRackPlan(hand, columns: 13);
    expect(plan.take(6).every((s) => s >= 13), isTrue);
    expect(plan[6], lessThan(13));
  });
  test('duplicate copies can form separate complete runs', () {
    final hand = [
      for (var copy = 0; copy < 2; copy++)
        for (var n = 1; n <= 3; n++) tile('$copy-$n', n, black),
    ];
    final plan = serialRackPlan(hand, columns: 13);
    expect(plan.every((s) => s >= 13), isTrue);
    expect(plan.toSet(), hasLength(6));
  });
  test('joker completes a distinct-colour set', () {
    final hand = [
      tile('r5', 5, red),
      tile('b5', 5, black),
      tile('joker', 8, blue, joker: true),
    ];
    final plan = serialRackPlan(hand, columns: 13);
    expect(plan.every((s) => s >= 13), isTrue);
    expect(plan.toSet(), hasLength(3));
  });
  test('only the existing 12-13-1 wrap is grouped as a complete run', () {
    final valid = [
      tile('12', 12, black),
      tile('13', 13, black),
      tile('1', 1, black),
    ];
    expect(serialRackPlan(valid, columns: 13), [13, 14, 15]);
    final invalid = [
      tile('13', 13, black),
      tile('1', 1, black),
      tile('2', 2, black),
    ];
    expect(serialRackPlan(invalid, columns: 13).every((s) => s < 13), isTrue);
  });
  test(
    'random hands preserve every physical tile with deterministic valid slots',
    () {
      final random = Random(271026);
      for (var sample = 0; sample < 150; sample++) {
        final hand = [
          for (var i = 0; i < 15; i++)
            tile(
              '$i',
              1 + random.nextInt(13),
              TileColor.values[random.nextInt(4)],
              joker: i < sample % 3,
            ),
        ];
        final plan = serialRackPlan(hand, columns: 13);
        expect(plan, hasLength(15));
        expect(plan.toSet(), hasLength(15));
        expect(plan.every((s) => s >= 0 && s < 26), isTrue);
        expect(serialRackPlan(hand, columns: 13), plan);
      }
    },
  );
}
