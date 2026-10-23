import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/game/rack/timeout_discard_selection.dart';

void main() {
  int? pick(List<int> slots, [Set<int> protected = const {}]) =>
      timeoutDiscardSlot(
        occupiedSlots: slots,
        protectedSlots: protected,
        columns: 13,
      );
  test('isolated rack tile takes priority over the end of a meld', () {
    expect(pick([0, 1, 2, 7, 10, 11, 12]), 7);
  });
  test('row boundaries do not join different rows', () {
    expect(pick([0, 1, 12, 13, 14]), 12);
  });
  test('a real joker is protected even when isolated', () {
    expect(pick([0, 1, 5, 9], {9}), 5);
  });
  test('falls back to a legal grouped tile when no singleton exists', () {
    expect(pick([0, 1, 2]), 2);
  });
  test('empty and fully protected racks have no candidate', () {
    expect(pick([]), isNull);
    expect(pick([5], {5}), isNull);
  });
}
