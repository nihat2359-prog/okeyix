import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/game/bot/bot_engine.dart';
import 'package:okeyix/game/bot/bot_observation.dart';
import '../tool/bot_benchmark.dart' show legalFinish, Metrics, playMatch;

// An independent sequence-template oracle (rather than the engine's gap sum).
bool referenceGroup(List<BotStone> stones) {
  if (stones.length < 3) return false;
  final normal = stones.where((s) => !s.wild).toList();
  if (normal.isEmpty) return false;
  if (stones.length <= 4 &&
      normal.map((s) => s.number).toSet().length == 1 &&
      normal.map((s) => s.color).toSet().length == normal.length) {
    return true;
  }
  if (normal.map((s) => s.color).toSet().length != 1) return false;
  for (final highAce in [false, true]) {
    final values = normal
        .map((s) => highAce && s.number == 1 ? 14 : s.number)
        .toList();
    if (values.toSet().length != values.length) continue;
    for (var start = 1; start <= 14; start++) {
      final sequence = List.generate(stones.length, (i) => start + i);
      if (sequence.last > (highAce ? 14 : 13)) continue;
      if (values.every(sequence.contains)) return true;
    }
  }
  return false;
}

void main() {
  test('2000 generated groups agree with independent sequence templates', () {
    final rng = Random(11021);
    for (var sample = 0; sample < 2000; sample++) {
      final hand = List.generate(
        3 + rng.nextInt(3),
        (i) => BotStone(
          '$i',
          BotStone.colors[rng.nextInt(4)],
          1 + rng.nextInt(13),
          wild: i < 2 && rng.nextInt(5) == 0,
        ),
      );
      expect(
        botValidGroup(hand),
        referenceGroup(hand),
        reason: 'sample $sample',
      );
    }
  });
  test('128 shuffled physical hands always return an owned discard', () {
    final rng = Random(27128);
    final engine = BotEngine(
      maxNodes: 200000,
      timeBudget: const Duration(seconds: 2),
    );
    final deck = <BotStone>[
      for (final color in BotStone.colors)
        for (var n = 1; n <= 13; n++)
          for (var copy = 0; copy < 2; copy++)
            BotStone(
              '$color:$n:$copy',
              color,
              n,
              wild: color == 'red' && n == 1,
            ),
      const BotStone('fake1', 'red', 1, fake: true),
      const BotStone('fake2', 'red', 1, fake: true),
    ];
    for (var sample = 0; sample < 128; sample++) {
      deck.shuffle(rng);
      final hand = deck.take(15).toList();
      final o = BotObservation(
        handKey: '$sample',
        hand: hand,
        ownSeat: 0,
        deckRemaining: 50,
        canDeclarePairs: true,
      );
      final result = engine.decide(o);
      expect(hand.any((s) => s.id == result.discardId), true);
      if (result.finish case final BotFinish finish) {
        expect(legalFinish(hand, finish), true);
        if (!finish.pairs) expect(finish.groups.every(referenceGroup), true);
      }
    }
  });
  test('paired offline matches complete without invalid moves', () async {
    final legacy = Metrics(), modern = Metrics();
    for (var seat = 0; seat < 2; seat++) {
      final outcome = await playMatch(74219, seat, legacy, modern);
      expect(outcome.turns, lessThanOrEqualTo(180));
    }
    expect(legacy.invalid, 0);
    expect(modern.invalid, 0);
    expect(modern.missedFinish, 0);
  });
}
