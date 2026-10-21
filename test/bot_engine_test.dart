import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/game/bot/bot_engine.dart';
import 'package:okeyix/game/bot/bot_observation.dart';
import 'package:okeyix/game/bot/bot_runner.dart';

List<BotStone> stones(String text) => text.split(' ').asMap().entries.map((e) {
  final token = e.value;
  if (token == 'J') return BotStone('s${e.key}', 'yellow', 13, wild: true);
  final color = {
    'K': 'red',
    'M': 'blue',
    'S': 'black',
    'Y': 'yellow',
  }[token[0]]!;
  return BotStone('s${e.key}', color, int.parse(token.substring(1)));
}).toList();
BotObservation observation(
  String hand, {
  BotStone? top,
  List<BotPublicMove> history = const [],
  bool pairs = false,
  bool declared = false,
  int deck = 60,
}) => BotObservation(
  handKey: 'table:round:seed',
  hand: stones(hand),
  ownSeat: 1,
  deckRemaining: deck,
  topDiscard: top,
  history: history,
  canDeclarePairs: pairs,
  pairsDeclared: declared,
);
final engine = BotEngine(
  maxNodes: 500000,
  timeBudget: const Duration(seconds: 10),
);
const base = 'K2 K3 K4 M6 M7 M8 S10 S11 S12';

void assertFinish(BotObservation o, BotFinish finish) {
  expect(finish.groups.expand((g) => g).length, 14);
  final ids = finish.groups.expand((g) => g).map((s) => s.id).toList();
  expect(ids.toSet().length, 14);
  expect(ids, isNot(contains(finish.discard.id)));
  if (!finish.pairs) expect(finish.groups.every(botValidGroup), isTrue);
  expect(finish.slots.length, 26);
}

void main() {
  test('deadline fallback evaluates all types and can accept a useful top', () {
    final o = observation(
      '$base K6 K8 Y2 S5 Y10',
      top: const BotStone('top', 'red', 7),
    );
    final d = botDeadlineDrawComparison(o);
    expect(d.limited, true);
    expect(d.takeDiscard, true);
    expect(d.draw!.evaluatedTypes, d.draw!.totalTypes);
    expect(d.draw!.totalTypes, greaterThan(40));
    expect(d.draw!.taking, greaterThan(d.draw!.closed!));
    final useless = botDeadlineDrawComparison(
      observation(
        '$base K6 K8 Y2 S5 Y10',
        top: const BotStone('top', 'blue', 1),
      ),
    );
    expect(useless.takeDiscard, false);
  });
  test('two real okeys defer a normal finish and remain in hand', () {
    final o = observation('$base K1 M1 S1 J J Y9');
    final legal = engine.findFinish(o);
    expect(legal, isNotNull);
    expect(legal!.discard.wild, false);
    final d = engine.decide(o);
    expect(d.limited, false);
    expect(d.finish, isNull);
    expect(o.hand.firstWhere((s) => s.id == d.discardId).wild, false);
    // With no closed tiles remaining, accept the available legal win.
    final exhausted = observation('$base K1 M1 S1 J J Y9', deck: 0);
    expect(engine.decide(exhausted).finish, isNotNull);
  });
  test('two okeys finish immediately when one can be thrown', () {
    final o = observation('K1 K2 K3 K4 M6 M7 M8 S10 S11 S12 Y1 Y2 Y3 J J');
    final d = engine.decide(o);
    expect(d.finish, isNotNull);
    expect(d.finish!.discard.wild, true);
    assertFinish(o, d.finish!);
  });
  test('single real okey still accepts a normal finish', () {
    final o = observation('$base K1 M1 S1 Y1 J Y9');
    final d = engine.decide(o);
    expect(d.finish, isNotNull);
    assertFinish(o, d.finish!);
  });
  test('two okeys do not defer an already-declared pairs finish', () {
    final o = observation(
      'K1 K1 M3 M3 S5 S5 Y7 Y7 K9 K9 M11 M11 J J Y2',
      declared: true,
    );
    final d = engine.decide(o);
    expect(d.finish, isNotNull);
    expect(d.finish!.pairs, true);
    assertFinish(o, d.finish!);
  });
  test('cached draw bounds agree with independent per-type searches', () {
    for (final indicator in [null, const BotStone('indicator', 'red', 6)]) {
      final raw = observation(
        '$base K6 K8 Y2 S5 Y10',
        top: const BotStone('top', 'red', 7),
      );
      final o = BotObservation(
        handKey: 'cache-regression',
        hand: raw.hand,
        ownSeat: 0,
        deckRemaining: 30,
        indicator: indicator,
        topDiscard: raw.topDiscard,
      );
      final d = engine.decide(o);
      final palette = <BotStone>[
        for (final color in BotStone.colors)
          for (var n = 1; n <= 13; n++)
            BotStone(
              'draw:$color:$n',
              color,
              n,
              wild:
                  indicator != null &&
                  indicator.color == color &&
                  n == indicator.number % 13 + 1,
            ),
        if (indicator != null)
          BotStone(
            'draw:fake',
            indicator.color,
            indicator.number % 13 + 1,
            fake: true,
          ),
      ];
      var weighted = 0.0, weight = 0;
      for (final s in palette) {
        final copies = (2 - (o.knownCopies[s.kind] ?? 0)).clamp(0, 2);
        if (copies == 0) continue;
        // Each call owns a fresh cache, independently of all other types.
        final result = engine.decide(o.withHand([...o.hand, s]));
        expect(result.limited, false);
        weighted += copies * result.score;
        weight += copies;
      }
      final exact = weighted / weight;
      final trace = d.draw!;
      if (trace.closed != null) expect(trace.closed, closeTo(exact, 1e-8));
      if (trace.closedLower != null) {
        expect(exact, greaterThanOrEqualTo(trace.closedLower! - 1e-8));
        expect(exact, lessThanOrEqualTo(trace.closedUpper! + 1e-8));
      }
      expect(
        d.takeDiscard,
        d.discardId != o.topDiscard!.id && trace.taking! > exact + 1e-8,
      );
    }
  });
  test(
    'cooperative draw does not inherit a synchronous slice deadline',
    () async {
      final o = observation(
        '$base K6 K8 Y2 S5 Y10',
        top: const BotStone('top', 'red', 7),
      );
      final d = await BotEngine(
        timeBudget: Duration.zero,
      ).decideCooperatively(o, totalBudget: const Duration(seconds: 3));
      expect(d.limited, false);
      expect(d.takeDiscard, engine.decide(o).takeDiscard);
      expect(d.takeDiscard, true);
    },
  );
  test(
    'bounded discard retains an evaluated candidate instead of first tile',
    () {
      final o = observation('$base K6 K8 Y2 S5 Y11 M12');
      final partials = [
        for (var n = 500; n <= 10000; n += 250)
          BotEngine(
            maxNodes: n,
            timeBudget: const Duration(seconds: 3),
          ).decide(o, discardOnly: true),
      ].where((d) => d.limited && d.score > 0).toList();
      expect(partials, isNotEmpty);
      expect(partials.any((d) => d.discardId != o.hand.first.id), true);
      for (final d in partials) {
        expect(o.hand.any((s) => s.id == d.discardId), true);
      }
    },
  );
  test(
    'closed finish expectation stays on the same scale as a useful open draw',
    () {
      final o = observation(
        'K1 K2 K3 K4 M5 M6 M7 M8 S9 S10 S11 Y5 Y6 Y10',
        top: const BotStone('top', 'blue', 9),
      );
      final d = engine.decide(o);
      expect(d.finish, isNull);
      expect(d.limited, false);
      expect(d.draw!.closed ?? d.draw!.closedUpper, lessThanOrEqualTo(1640));
      expect(d.takeDiscard, true, reason: '${d.draw!.toJson()}');
      expect(
        d.draw!.taking,
        greaterThan(d.draw!.closed ?? d.draw!.closedUpper!),
      );
      expect(
        o
            .withHand([...o.hand, const BotStone('hypothetical', 'black', 2)])
            .topDiscard
            ?.id,
        'top',
      );
    },
  );
  test(
    'cooperative browser expectation agrees with synchronous calculation',
    () async {
      final o = observation(
        '$base K6 K8 Y2 S5 Y10',
        top: const BotStone('top', 'red', 7),
      );
      final sync = engine.decide(o);
      final cooperative = await engine.decideCooperatively(o);
      expect(cooperative.limited, false);
      expect(cooperative.takeDiscard, sync.takeDiscard);
      expect(cooperative.draw!.closed, sync.draw!.closed);
    },
  );
  test('normalization: fake is fixed, real joker aliases and physical ids', () {
    const indicator = BotStone('indicator', 'red', 4);
    final fake = BotStone.fromJson({
      'id': 'f',
      'number': 0,
      'color': 'red',
      'is_fake_joker': true,
      'joker': true,
    }, indicator: indicator);
    expect(fake.number, 5);
    expect(fake.wild, false);
    expect(fake.fake, true);
    final actual = BotStone.fromJson({
      'id': 'j',
      'number': 5,
      'color': 'red',
    }, indicator: indicator);
    expect(actual.wild, true);
    expect(BotStone.fromJson(actual.toPayload()).wild, true);
    expect(
      () => BotObservation(
        handKey: 'x',
        hand: List.filled(14, actual),
        ownSeat: 0,
        deckRemaining: 40,
      ),
      throwsArgumentError,
    );
  });
  test('group rules: gap, distinct colors, 12-13-1, no 13-1-2', () {
    expect(botValidGroup(stones('K6 K7 K8')), true);
    expect(botValidGroup(stones('K9 M9 K9')), false);
    expect(botValidGroup(stones('K9 M9 S9')), true);
    expect(botValidGroup(stones('K12 K13 K1')), true);
    expect(botValidGroup(stones('K13 K1 K2')), false);
    expect(botValidGroup(stones('K6 J K8')), true);
    expect(botValidGroup(stones('K6 K8 K10')), false);
  });
  test('takes real okey and immediately finishes (old report scenario 1)', () {
    final o = observation(
      'K1 K2 K3 K4 M5 M6 M7 M8 S9 S10 S11 Y5 Y6 Y10',
      top: const BotStone('top', 'yellow', 13, wild: true),
    );
    final d = engine.decide(o);
    expect(d.takeDiscard, true);
    expect(d.finish, isNotNull);
    assertFinish(o, d.finish!);
  });
  test('takes fixed-value fake okey to finish (scenario 2)', () {
    final o = observation(
      'K1 K2 K3 K4 M5 M6 M7 M8 S9 S10 S11 Y4 Y6 Y10',
      top: const BotStone('top', 'yellow', 5, fake: true),
    );
    final d = engine.decide(o);
    expect(d.takeDiscard, true);
    assertFinish(o, d.finish!);
  });
  test(
    'takes middle gap 7 to finish, preserving 14/15 semantics (scenario 3)',
    () {
      final o = observation(
        'M1 M2 M3 M4 S5 S6 S7 S8 Y9 Y10 Y11 K6 K8 Y2',
        top: const BotStone('top', 'red', 7),
      );
      final d = engine.decide(o);
      expect(d.takeDiscard, true);
      expect(d.finish, isNotNull);
      assertFinish(o, d.finish!);
    },
  );
  test('duplicate color does not magically finish a set (scenario 4)', () {
    final o = observation(
      '$base K9 M9 Y2 S5 Y13',
      top: const BotStone('top', 'red', 9),
    );
    final d = engine.decide(o);
    expect(d.finish, isNull);
    expect(d.takeDiscard, false);
  });
  test('overlapping groups cannot generate a false finish (scenario 5)', () {
    final o = observation('$base M3 Y3 Y7 S5 M12 S1');
    expect(engine.decide(o).finish, isNull);
  });
  test('wrap sequence participates in exact finish (scenario 6)', () {
    final o = observation('K1 K2 K3 K4 M5 M6 M7 M8 S9 S10 S11 Y12 Y13 Y1 S2');
    final d = engine.decide(o);
    expect(d.finish, isNotNull);
    assertFinish(o, d.finish!);
  });
  test('real joker fills a missing run in finish (scenario 7)', () {
    final o = observation('M1 M2 M3 M4 S5 S6 S7 S8 Y9 Y10 Y11 K6 J K8 Y2');
    final d = engine.decide(o);
    expect(d.finish, isNotNull);
    assertFinish(o, d.finish!);
  });
  test(
    'seven pairs needs authorized declaration; fake pairs as ordinary value (scenario 8)',
    () {
      const hand = 'K2 K2 M4 M4 S6 S6 Y8 Y8 K10 K10 M12 M12 Y1 Y1 S3';
      expect(engine.decide(observation(hand)).finish, isNull);
      final o = observation(hand, pairs: true);
      final d = engine.decide(o);
      expect(d.finish!.pairs, true);
      assertFinish(o, d.finish!);
      expect(
        engine.decide(observation(hand, declared: true)).finish!.pairs,
        true,
      );
    },
  );
  test(
    'opponent public pickup breaks an otherwise neutral discard tie (scenario 9)',
    () {
      const hand = 'K3 K4 K5 K6 M3 M4 M5 S8 S9 S10 Y8 Y9 Y10 K12 M12';
      final plain = engine.decide(observation(hand));
      expect(plain.discardId, 's13');
      final history = [
        BotPublicMove(
          'p',
          1,
          const BotStone('known', 'red', 11),
          takenBySeat: 0,
        ),
      ];
      final defensive = engine.decide(
        observation(hand, history: history, deck: 8),
      );
      expect(defensive.discardId, 's14');
      expect(defensive.finish, isNull);
    },
  );
  test('prefers okey discard over first normal finish (scenario 10)', () {
    final o = observation('K1 K2 K3 K4 M5 M6 M7 M8 S9 S10 S11 Y5 Y6 Y7 J');
    final d = engine.decide(o);
    expect(d.finish!.discard.wild, true);
    assertFinish(o, d.finish!);
  });
  test('known copies deduplicate taken/discarded/current physical tile', () {
    final hand = stones('$base K6 K8 Y2 S5 Y11');
    final history = [
      BotPublicMove('e1', 0, hand.first, takenBySeat: 1),
      BotPublicMove('e2', 1, hand.first),
      const BotPublicMove('e3', 0, BotStone('other', 'red', 2)),
    ];
    final o = BotObservation(
      handKey: 'round2',
      hand: hand,
      history: history,
      ownSeat: 1,
      deckRemaining: 30,
    );
    expect(o.knownCopies['red:2'], 2);
    final rows = [
      {
        'id': 'e1',
        'seat_index': 0,
        'tile': hand.first.toPayload(),
        'drawn_at': 'now',
        'drawn_by_user_id': 'bot',
        'hand': ['SECRET'],
      },
    ];
    final replay = botPublicHistory([...rows, ...rows], {'bot': 1});
    expect(replay.length, 1);
    expect(replay.single.takenBySeat, 1);
    expect(botPublicHistory([], {}).length, 0);
  });

  test(
    'exhausted visible outs reduce hand potential and history resets cleanly',
    () {
      const hand = '$base K6 K8 Y2 Y4 S2 M12';
      const indicator = BotStone('indicator', 'blue', 12);
      final own = stones(hand);
      BotObservation make(List<BotPublicMove> history, String key) =>
          BotObservation(
            handKey: key,
            hand: own,
            ownSeat: 1,
            deckRemaining: 30,
            indicator: indicator,
            history: history,
          );
      final fresh = engine.decide(make([], 'round1'));
      final exposed = [
        for (var i = 0; i < 2; i++) ...[
          BotPublicMove('r$i', 0, BotStone('red7:$i', 'red', 7)),
          BotPublicMove('j$i', 0, BotStone('wild:$i', 'blue', 13, wild: true)),
        ],
      ];
      final exhausted = engine.decide(make(exposed, 'round1'));
      expect(exhausted.score, lessThan(fresh.score));
      final reconnected = engine.decide(make(exposed, 'round1'));
      expect(reconnected.discardId, exhausted.discardId);
      final nextRound = engine.decide(make([], 'round2'));
      expect(nextRound.discardId, fresh.discardId);
      expect(nextRound.score, fresh.score);
    },
  );
  test(
    'hidden hand/deck permutation cannot affect the allowlisted observation',
    () {
      final hand = stones('$base K6 K8 Y2 S5 Y11 M12');
      BotObservation project(Map<String, Object> full) => BotObservation(
        handKey: 'round',
        hand: hand,
        ownSeat: 1,
        deckRemaining: 30,
        history: botPublicHistory(
          (full['public'] as List).cast<Map<String, dynamic>>(),
          {},
        ),
      );
      final a = project({
        'public': <Map<String, dynamic>>[],
        'opponent': ['K1'],
        'deck': ['M2', 'Y3'],
      });
      final b = project({
        'public': <Map<String, dynamic>>[],
        'opponent': ['S13'],
        'deck': ['Y3', 'M2'],
      });
      final da = engine.decide(a), db = engine.decide(b);
      expect(da.discardId, db.discardId);
      expect(da.score, db.score);
      expect(engine.decide(a).discardId, da.discardId);
      final source = File('lib/game/bot/bot_engine.dart').readAsStringSync();
      expect(source, isNot(contains('supabase')));
      expect(source, isNot(contains('okey_game.dart')));
    },
  );
  test(
    'node exhaustion and worker timeout produce owned legal discard',
    () async {
      final o = observation('$base K6 K8 Y2 S5 Y11 M12');
      final bounded = BotEngine(maxNodes: 0).decide(o);
      expect(bounded.limited, true);
      expect(o.hand.any((s) => s.id == bounded.discardId), true);
      final result = await runBotDecision(
        o,
        timeout: const Duration(milliseconds: 1),
        worker: (_) => Completer<BotDecision>().future,
      );
      expect(result.limited, true);
      expect(o.hand.any((s) => s.id == result.discardId), true);
    },
  );
  test('business failure is not success; stale hands/turns cannot commit', () {
    expect(botFinishSucceeded({'ok': false}), false);
    expect(botFinishSucceeded(null), false);
    expect(botFinishSucceeded({'ok': true}), true);
    final o = observation('$base K6 K8 Y2 S5 Y11 M12');
    expect(
      botCanCommit(
        expectedTurn: 'a',
        currentTurn: 'a',
        expectedHand: o.hand,
        currentHand: o.hand,
        discardId: o.hand.first.id,
      ),
      true,
    );
    expect(
      botCanCommit(
        expectedTurn: 'a',
        currentTurn: 'b',
        expectedHand: o.hand,
        currentHand: o.hand,
        discardId: o.hand.first.id,
      ),
      false,
    );
    expect(
      botCanCommit(
        expectedTurn: 'a',
        currentTurn: 'a',
        expectedHand: o.hand,
        currentHand: o.hand.reversed.toList(),
        discardId: 'not-owned',
      ),
      false,
    );
  });
}
