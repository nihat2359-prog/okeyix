// Offline only. A neutral harness owns the shuffled deck; neither policy does.
// Run: dart run tool/bot_benchmark.dart 64
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:okeyix/game/bot/bot_engine.dart';
import 'package:okeyix/game/bot/bot_observation.dart';
import '../test/support/legacy_bot_policy.dart';

class Metrics {
  final times = <int>[];
  int invalid = 0,
      missedFinish = 0,
      limited = 0,
      finishes = 0,
      turnsToFinish = 0;
  int drawTurns = 0,
      topOpportunities = 0,
      takes = 0,
      useful = 0,
      usefulTaken = 0,
      usefulRejected = 0,
      unnecessary = 0,
      drawLimited = 0;
  int rejectedLimited = 0, rejectedExpectedBetter = 0, superiorRejected = 0;
  final drawReasons = <String, int>{};
  Map<String, Object> json() {
    final sorted = times.toList()..sort();
    return {
      'decisions': times.length,
      'draw_turns': drawTurns,
      'top_opportunities': topOpportunities,
      'discard_takes': takes,
      'take_rate': topOpportunities == 0 ? 0 : takes / topOpportunities,
      'useful_tops': useful,
      'useful_taken': usefulTaken,
      'useful_rejected': usefulRejected,
      'useful_accept_rate': useful == 0 ? 0 : usefulTaken / useful,
      'non_improving_takes': unnecessary,
      'draw_limited': drawLimited,
      'useful_rejected_limited': rejectedLimited,
      'useful_rejected_expected_better': rejectedExpectedBetter,
      'superior_rejected_by_ev_oracle': superiorRejected,
      'draw_reasons': drawReasons,
      'invalid': invalid,
      'missed_finish': missedFinish,
      'limited': limited,
      'finishes': finishes,
      'mean_finish_turns': finishes == 0 ? 0 : turnsToFinish / finishes,
      'mean_us': times.isEmpty
          ? 0
          : times.reduce((a, b) => a + b) / times.length,
      'p95_us': sorted.isEmpty
          ? 0
          : sorted[((sorted.length - 1) * .95).floor()],
      'worst_us': sorted.isEmpty ? 0 : sorted.last,
    };
  }
}

bool legalFinish(List<BotStone> own, BotFinish plan) {
  final remaining = own.where((s) => s.id != plan.discard.id).toList();
  final used = plan.groups.expand((g) => g).toList();
  if (own.length != 15 ||
      remaining.length != 14 ||
      used.length != 14 ||
      used.map((s) => s.id).toSet().length != 14 ||
      !used.every(
        (s) => remaining.any((t) => t.id == s.id && t.kind == s.kind),
      )) {
    return false;
  }
  if (!plan.pairs) return plan.groups.every(botValidGroup);
  final counts = <String, int>{};
  var wild = 0;
  for (final s in remaining) {
    if (s.wild) {
      wild++;
    } else {
      counts.update('${s.color}:${s.number}', (n) => n + 1, ifAbsent: () => 1);
    }
  }
  var pairs = 0;
  for (final n in counts.values) {
    pairs += n ~/ 2;
    if (n.isOdd && wild > 0) {
      pairs++;
      wild--;
    }
  }
  return pairs + wild ~/ 2 == 7;
}

class MatchOutcome {
  final int? winningSeat;
  final int turns;
  MatchOutcome(this.winningSeat, this.turns);
}

Future<MatchOutcome> playMatch(
  int seed,
  int newSeat,
  Metrics oldMetrics,
  Metrics newMetrics,
) async {
  // Normal-indicator cohort. Fake-indicator behavior is not invented here.
  const indicator = BotStone('indicator', 'red', 13);
  final deck = <BotStone>[];
  for (final c in BotStone.colors) {
    for (var n = 1; n <= 13; n++) {
      for (var copy = 0; copy < 2; copy++) {
        if (c == 'red' && n == 13 && copy == 0) continue;
        deck.add(BotStone('$c:$n:$copy', c, n, wild: c == 'red' && n == 1));
      }
    }
  }
  deck.addAll([
    const BotStone('fake0', 'red', 1, fake: true),
    const BotStone('fake1', 'red', 1, fake: true),
  ]);
  deck.shuffle(Random(seed));
  final hands = [<BotStone>[], <BotStone>[]];
  for (var seat = 0; seat < 2; seat++) {
    for (var i = 0; i < (seat == 0 ? 15 : 14); i++) {
      hands[seat].add(deck.removeLast());
    }
  }
  final discards = [<BotStone>[], <BotStone>[]];
  final history = <BotPublicMove>[];
  final legacy = LegacyBotPolicy();
  final engine = BotEngine();
  final oracle = BotEngine(
    maxNodes: 1000000,
    timeBudget: const Duration(seconds: 5),
  );
  final ownTurns = [0, 0];
  for (var turn = 0; turn < 180; turn++) {
    final seat = turn % 2, other = 1 - seat;
    ownTurns[seat]++;
    final modern = seat == newSeat;
    final m = modern ? newMetrics : oldMetrics;
    BotObservation observe({BotStone? top}) => BotObservation(
      handKey: '$seed',
      hand: hands[seat],
      ownSeat: seat,
      deckRemaining: deck.length,
      history: history,
      indicator: indicator,
      topDiscard: top,
      canDeclarePairs: modern,
    );
    Future<BotDecision> decide(BotObservation o) async {
      final timer = Stopwatch()..start();
      final d = modern ? await engine.decideCooperatively(o) : legacy.decide(o);
      m.times.add(timer.elapsedMicroseconds);
      if (d.limited) m.limited++;
      return d;
    }

    if (hands[seat].length == 14) {
      final top = discards[other].isEmpty ? null : discards[other].last;
      final draw = await decide(observe(top: top));
      final reason = draw.draw?.reason ?? 'legacy';
      m.drawReasons.update(reason, (n) => n + 1, ifAbsent: () => 1);
      m.drawTurns++;
      if (draw.limited) m.drawLimited++;
      if (top != null) {
        m.topOpportunities++;
        final assessment = oracle.assessTop(observe(top: top));
        final useful =
            assessment.retainsTop &&
            (assessment.finish || assessment.after > assessment.before + 1e-8);
        if (useful) {
          m.useful++;
          if (draw.takeDiscard) {
            m.usefulTaken++;
          } else {
            m.usefulRejected++;
            if (draw.limited) m.rejectedLimited++;
            if (reason == 'closed_expectation_better' ||
                reason == 'closed_above_top_lower_bound') {
              m.rejectedExpectedBetter++;
            }
            // A stronger-budget same-information oracle distinguishes a useful
            // tile from a tile actually superior to closed drawing.
            if (oracle.decide(observe(top: top)).takeDiscard) {
              m.superiorRejected++;
            }
          }
        }
        if (draw.takeDiscard) {
          m.takes++;
          if (!useful) m.unnecessary++;
        }
      }
      if (top != null &&
          !draw.takeDiscard &&
          oracle.findFinish(observe().withHand([...hands[seat], top])) !=
              null) {
        m.missedFinish++;
      }
      if (draw.takeDiscard && top != null) {
        hands[seat].add(discards[other].removeLast());
        final i = history.lastIndexWhere((m) => m.stone.id == top.id);
        if (i >= 0) {
          history[i] = BotPublicMove(
            history[i].eventId,
            other,
            top,
            takenBySeat: seat,
          );
        }
      } else {
        if (deck.isEmpty) return MatchOutcome(null, turn);
        hands[seat].add(deck.removeLast());
      }
    }
    final o = observe();
    final d = await decide(o);
    if (d.finish != null) {
      if (legalFinish(hands[seat], d.finish!)) {
        m.finishes++;
        m.turnsToFinish += ownTurns[seat];
        return MatchOutcome(seat, turn + 1);
      }
      m.invalid++;
    } else if (oracle.findFinish(o) != null) {
      m.missedFinish++;
    }
    final index = hands[seat].indexWhere((s) => s.id == d.discardId);
    if (index < 0) {
      m.invalid++;
      return MatchOutcome(null, turn);
    }
    final discarded = hands[seat].removeAt(index);
    discards[seat].add(discarded);
    history.add(BotPublicMove('event:$turn', seat, discarded));
  }
  return MatchOutcome(null, 180);
}

Future<void> main(List<String> args) async {
  final pairs = args.isEmpty ? 64 : int.parse(args.first);
  final seedStart = args.length > 1 ? int.parse(args[1]) : 74219;
  final old = Metrics(), modern = Metrics();
  var newWins = 0, oldWins = 0, draws = 0;
  final timer = Stopwatch()..start();
  for (var seed = 0; seed < pairs; seed++) {
    for (var newSeat = 0; newSeat < 2; newSeat++) {
      final r = await playMatch(seedStart + seed, newSeat, old, modern);
      if (r.winningSeat == null) {
        draws++;
      } else if (r.winningSeat == newSeat) {
        newWins++;
      } else {
        oldWins++;
      }
    }
    if ((seed + 1) % 8 == 0) {
      stderr.writeln('Completed ${seed + 1}/$pairs seed pairs');
    }
  }
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'seed_start': seedStart,
      'seed_pairs': pairs,
      'games': pairs * 2,
      'new_wins': newWins,
      'old_wins': oldWins,
      'draws': draws,
      'old': old.json(),
      'new': modern.json(),
      'elapsed_ms': timer.elapsedMilliseconds,
      'process_peak_rss_bytes': ProcessInfo.maxRss,
      'scope':
          'Offline local-rule simulation; not live Supabase or human strength rating',
    }),
  );
}
