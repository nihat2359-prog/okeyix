import 'dart:math' as math;
import 'bot_observation.dart';

class BotFinish {
  final BotStone discard;
  final List<List<BotStone>> groups;
  final bool pairs;
  BotFinish(this.discard, this.groups, {this.pairs = false});
  List<Map<String, dynamic>> get slots {
    final out = <Map<String, dynamic>>[];
    for (final group in groups) {
      if (out.isNotEmpty && !pairs) out.add({'i': out.length});
      for (final stone in group) {
        out.add({'i': out.length, 'tile': stone.toPayload()});
      }
    }
    while (out.length < 26) {
      out.add({'i': out.length});
    }
    return out;
  }
}

class BotDecision {
  final String discardId;
  final bool takeDiscard;
  final BotFinish? finish;
  final double score;
  final bool limited;
  final BotDrawTrace? draw;
  final int elapsedMicros;
  const BotDecision({
    required this.discardId,
    this.takeDiscard = false,
    this.finish,
    this.score = 0,
    this.limited = false,
    this.draw,
    this.elapsedMicros = 0,
  });
}

class BotDrawTrace {
  final double? current, taking, closed;
  final String reason;
  final int evaluatedTypes, totalTypes;
  final double? closedLower, closedUpper;
  const BotDrawTrace(
    this.reason, {
    this.current,
    this.taking,
    this.closed,
    this.evaluatedTypes = 0,
    this.totalTypes = 0,
    this.closedLower,
    this.closedUpper,
  });
  Map<String, Object?> toJson() => {
    'reason': reason,
    'current': current,
    'taking': taking,
    'closed_expected': closed,
    'evaluated_types': evaluatedTypes,
    'total_types': totalTypes,
    'closed_lower': closedLower,
    'closed_upper': closedUpper,
    'closed_exact': closed != null,
  };
}

/// Mirrors the local server validator: different-color sets of 3..4;
/// same-color runs, distinct numbers, gap-filled by real jokers; 1 may be 14.
/// Fake jokers are ordinary fixed-value stones throughout.
bool botValidGroup(List<BotStone> group) {
  if (group.length < 3) return false;
  final normal = group.where((s) => !s.wild).toList();
  if (normal.isEmpty) return false;
  final jokers = group.length - normal.length;
  if (group.length <= 4 &&
      normal.every((s) => s.number == normal.first.number) &&
      normal.map((s) => s.color).toSet().length == normal.length) {
    return true;
  }
  if (normal.any((s) => s.color != normal.first.color) ||
      normal.map((s) => s.number).toSet().length != normal.length) {
    return false;
  }
  bool fits(bool wrap) {
    final values =
        normal.map((s) => wrap && s.number == 1 ? 14 : s.number).toList()
          ..sort();
    return values.last - values.first + 1 - values.length <= jokers;
  }

  return fits(false) || fits(true);
}

class _Limit implements Exception {}

/// Pure deterministic bounded search. One catalog and memo table are shared
/// by all discard masks. No completed group is unconditionally protected.
class BotEngine {
  final int maxNodes;
  final Duration timeBudget;
  BotEngine({
    this.maxNodes = 300000,
    this.timeBudget = const Duration(milliseconds: 180),
  });

  BotFinish? findFinish(BotObservation observation) {
    var nodes = 0;
    final watch = Stopwatch()..start();
    try {
      return _Search(observation, () {
        if (++nodes > maxNodes ||
            (nodes % 128 == 0 && watch.elapsed > timeBudget)) {
          throw _Limit();
        }
      }).finish();
    } on _Limit {
      return null;
    }
  }

  /// Offline measurement of immediate potential, not a claim that closed
  /// drawing is inferior. Uses only the same permitted observation.
  ({double before, double after, bool finish, bool retainsTop}) assessTop(
    BotObservation o,
  ) {
    if (o.hand.length != 14 || o.topDiscard == null) {
      throw ArgumentError('14 + top required');
    }
    final current = _Search(o, () {}).handValue((1 << 14) - 1);
    final candidate = _Search(
      o.withHand([...o.hand, o.topDiscard!]),
      () {},
    ).bestDiscard();
    return (
      before: current,
      after: candidate.score,
      finish: candidate.finish != null,
      retainsTop:
          candidate.discardId != o.topDiscard!.id || candidate.finish != null,
    );
  }

  BotDecision decide(BotObservation observation, {bool discardOnly = false}) {
    final timer = Stopwatch()..start();
    final d = _decide(observation, discardOnly: discardOnly);
    return BotDecision(
      discardId: d.discardId,
      takeDiscard: d.takeDiscard,
      finish: d.finish,
      score: d.score,
      limited: d.limited,
      draw: d.draw,
      elapsedMicros: timer.elapsedMicroseconds,
    );
  }

  /// Web has no compute isolate. Yield between closed-draw types so a whole
  /// expectation does not have to fit the old single 12 ms browser budget.
  /// The synchronous timeBudget is deliberately not a deadline per type:
  /// even one exact discard comparison can exceed a frame in debug Chrome.
  Future<BotDecision> decideCooperatively(
    BotObservation o, {
    bool discardOnly = false,
    Duration totalBudget = const Duration(milliseconds: 650),
  }) async {
    if (o.hand.length != 14) return decide(o, discardOnly: discardOnly);
    final wall = Stopwatch()..start();
    final slice = Stopwatch()..start();
    var nodes = 0;
    BotDecision best = BotDecision(
      discardId: o.hand.first.id,
      limited: true,
      draw: const BotDrawTrace('search_limit_before_comparison'),
    );
    try {
      for (final step in _drawSteps(o, () {
        if (++nodes > maxNodes ||
            (nodes % 128 == 0 && wall.elapsed > totalBudget)) {
          throw _Limit();
        }
      })) {
        best = step;
        // Chrome clamps nested zero-duration timers. Yielding on every cheap
        // type can spend most of the deadline waiting rather than searching.
        if (slice.elapsedMicroseconds >= 8000) {
          await Future<void>.delayed(Duration.zero);
          slice.reset();
        }
        nodes = 0;
      }
      return BotDecision(
        discardId: best.discardId,
        takeDiscard: best.takeDiscard,
        finish: best.finish,
        score: best.score,
        draw: best.draw,
        elapsedMicros: wall.elapsedMicroseconds,
      );
    } on _Limit {
      if (!o.pairsDeclared &&
          o.topDiscard != null &&
          best.draw?.taking != null) {
        return botDeadlineDrawComparison(
          o,
          elapsedBefore: wall.elapsedMicroseconds,
        );
      }
      return BotDecision(
        discardId: best.discardId,
        limited: true,
        draw: best.draw,
        elapsedMicros: wall.elapsedMicroseconds,
      );
    }
  }

  BotDecision _decide(BotObservation observation, {bool discardOnly = false}) {
    final watch = Stopwatch()..start();
    var nodes = 0;
    void tick() {
      nodes++;
      if (nodes > maxNodes ||
          (nodes % 128 == 0 && watch.elapsed > timeBudget)) {
        throw _Limit();
      }
    }

    final hand = observation.hand;
    final fallback = hand.firstWhere((s) => !s.wild, orElse: () => hand.first);
    BotDecision best = BotDecision(discardId: fallback.id, limited: true);
    try {
      if (hand.length == 14) {
        for (final step in _drawSteps(observation, tick)) {
          best = step;
        }
        return best;
      }
      final search = _Search(observation, tick);
      // Exact finishing is checked before strategic scoring or defensive risk.
      final finish = discardOnly ? null : search.finish(strategic: true);
      if (finish != null) {
        return BotDecision(
          discardId: finish.discard.id,
          finish: finish,
          score: finish.discard.wild || finish.pairs ? 1640 : 1600,
        );
      }
      best = search.bestDiscard(checkFinish: false, preservePartial: true);
      return best;
    } on _Limit {
      // Stable legal fallback. Never invent a win, or force a joker discard.
      return BotDecision(
        discardId: best.discardId,
        takeDiscard: best.takeDiscard,
        score: best.score,
        limited: true,
        draw:
            best.draw ??
            (hand.length == 14
                ? const BotDrawTrace('search_limit_before_comparison')
                : null),
      );
    }
  }
}

/// Deadline fallback: compare BOTH sources with one bounded, local connection
/// heuristic over ALL unknown types. Never compare an exact open score against
/// an incomplete/optimistically sampled closed score, or force closed by default.
BotDecision botDeadlineDrawComparison(
  BotObservation o, {
  int elapsedBefore = 0,
}) {
  if (o.hand.length != 14 || o.topDiscard == null) {
    throw ArgumentError(
      'Deadline draw comparison requires 14 stones and a top',
    );
  }
  final watch = Stopwatch()..start();
  double value(List<BotStone> hand, int discard) {
    var score = 0.0;
    for (var i = 0; i < hand.length; i++) {
      if (i == discard) continue;
      final a = hand[i];
      if (a.wild) {
        score += 3;
        continue;
      }
      var links = 0.0;
      for (var j = 0; j < hand.length; j++) {
        if (j == i || j == discard) continue;
        final b = hand[j];
        if (b.wild) continue;
        if (a.number == b.number && a.color != b.color) links += 1;
        if (a.color == b.color) {
          final distance = (a.number - b.number).abs();
          if (distance == 1 || distance == 12) links += 1;
          if (distance == 2 ||
              (a.number == 1 && b.number == 12) ||
              (b.number == 1 && a.number == 12)) {
            links += 0.5;
          }
        }
      }
      score += math.min(2.0, links);
    }
    return score;
  }

  ({double score, String discard}) best(BotStone drawn) {
    final hand = [...o.hand, drawn];
    var score = -double.infinity;
    var discard = drawn.id;
    for (var i = 0; i < hand.length; i++) {
      if (hand[i].wild) continue;
      final candidate = value(hand, i);
      if (candidate > score + 1e-8 ||
          ((candidate - score).abs() < 1e-8 && hand[i].id == drawn.id)) {
        score = candidate;
        discard = hand[i].id;
      }
    }
    return (score: score, discard: discard);
  }

  final taking = best(o.topDiscard!);
  final known = o.knownCopies;
  var weighted = 0.0, total = 0, types = 0;
  for (final color in BotStone.colors) {
    for (var number = 1; number <= 13; number++) {
      final s = BotStone(
        'draw:$color:$number',
        color,
        number,
        wild:
            o.indicator?.color == color &&
            number == (o.indicator!.number % 13 + 1),
      );
      final count = (2 - (known[s.kind] ?? 0)).clamp(0, 2);
      if (count == 0) continue;
      weighted += best(s).score * count;
      total += count;
      types++;
    }
  }
  if (o.indicator case final BotStone indicator) {
    final count = (2 - (known['fake'] ?? 0)).clamp(0, 2);
    if (count > 0) {
      weighted +=
          best(
            BotStone(
              'draw:fake',
              indicator.color,
              indicator.number % 13 + 1,
              fake: true,
            ),
          ).score *
          count;
      total += count;
      types++;
    }
  }
  final closed = total > 0 ? weighted / total : value(o.hand, -1);
  final take =
      taking.discard != o.topDiscard!.id && taking.score > closed + 1e-8;
  return BotDecision(
    discardId: taking.discard,
    takeDiscard: take,
    limited: true,
    score: taking.score,
    elapsedMicros: elapsedBefore + watch.elapsedMicroseconds,
    draw: BotDrawTrace(
      take
          ? 'fast_take_beats_closed_expectation'
          : 'fast_closed_expectation_better',
      taking: taking.score,
      closed: closed,
      evaluatedTypes: types,
      totalTypes: types,
    ),
  );
}

class _Search {
  final BotObservation o;
  final void Function() tick;
  late final List<BotStone> h = o.hand;
  late final int all = (1 << h.length) - 1;
  final groups = <int>[];
  final pairs = <int, double>{};
  late final groupsByFirst = List.generate(h.length, (_) => <int>[]);
  late final pairsByFirst = List.generate(h.length, (_) => <(int, double)>[]);
  final memo = <int, double>{0: 0};
  final solved = <int, List<int>?>{0: <int>[]};
  late final Map<String, int> known = o.knownCopies;
  final Map<String, List<BotStone>> outsCache;
  // Phase comes from remaining public deck and hand's progress, not turn count.
  double get urgency => (1 - o.deckRemaining / 77).clamp(0.0, 1.0);
  _Search(this.o, this.tick, {Map<String, List<BotStone>>? outsCache})
    : outsCache = outsCache ?? {} {
    for (var a = 0; a < h.length; a++) {
      for (var b = a + 1; b < h.length; b++) {
        final mask = (1 << a) | (1 << b);
        final outs = _outs(h[a], h[b]);
        if (outs > 0) pairs[mask] = 36 + math.min(12, outs) * (2.5 - urgency);
      }
    }
    // Every long legal run can be partitioned into legal lengths 3..5 under
    // the checked server rules. Physical IDs remain distinct in all masks.
    final selected = <BotStone>[];
    void choose(int start, int mask) {
      tick();
      BotStone? first;
      var sameColor = true, sameNumber = true;
      for (var a = 0; a < selected.length; a++) {
        final stone = selected[a];
        if (stone.wild) continue;
        first ??= stone;
        sameColor = sameColor && stone.color == first.color;
        sameNumber = sameNumber && stone.number == first.number;
        if (!sameColor && !sameNumber) return;
        for (var b = 0; b < a; b++) {
          final other = selected[b];
          if (!other.wild &&
              other.color == stone.color &&
              other.number == stone.number) {
            return;
          }
        }
      }
      if (selected.length >= 3 && botValidGroup(selected)) groups.add(mask);
      if (selected.length == 5) return;
      for (var i = start; i < h.length; i++) {
        selected.add(h[i]);
        choose(i + 1, mask | (1 << i));
        selected.removeLast();
      }
    }

    choose(0, 0);
    groups.sort((a, b) => _count(b).compareTo(_count(a)));
    // A subset whose smallest occupied bit is i can only contain groups whose
    // smallest bit is also i. All others were scanned and rejected repeatedly.
    for (final group in groups) {
      groupsByFirst[(group & -group).bitLength - 1].add(group);
    }
    for (final entry in pairs.entries) {
      pairsByFirst[(entry.key & -entry.key).bitLength - 1].add((
        entry.key,
        entry.value,
      ));
    }
  }

  List<BotStone> stones(int mask) => [
    for (var i = 0; i < h.length; i++)
      if (mask & (1 << i) != 0) h[i],
  ];
  int _count(int mask) {
    var n = 0;
    while (mask != 0) {
      mask &= mask - 1;
      n++;
    }
    return n;
  }

  List<int>? partition(int mask) {
    if (solved.containsKey(mask)) return solved[mask];
    tick();
    final first = mask & -mask;
    for (final group in groupsByFirst[first.bitLength - 1]) {
      if (group & mask != group) continue;
      final rest = partition(mask ^ group);
      if (rest != null) return solved[mask] = [group, ...rest];
    }
    solved[mask] = null;
    return null;
  }

  List<List<BotStone>>? pairGroups(int mask) {
    final tiles = stones(mask);
    final wild = tiles.where((s) => s.wild).toList();
    final values = <String, List<BotStone>>{};
    for (final s in tiles.where((s) => !s.wild)) {
      values.putIfAbsent('${s.color}:${s.number}', () => []).add(s);
    }
    final out = <List<BotStone>>[];
    for (final group in values.values) {
      while (group.length >= 2) {
        out.add([group.removeLast(), group.removeLast()]);
      }
      if (group.isNotEmpty) {
        if (wild.isEmpty) return null;
        out.add([group.single, wild.removeLast()]);
      }
    }
    while (wild.length >= 2) {
      out.add([wild.removeLast(), wild.removeLast()]);
    }
    return wild.isEmpty && out.length == 7 ? out : null;
  }

  // Keep legality queries exact; only playing decisions may defer a normal win.
  bool get pursueOkeyDiscard =>
      !o.pairsDeclared &&
      o.deckRemaining > 0 &&
      h.where((s) => s.wild && !s.fake).length >= 2;

  BotFinish? finish({bool strategic = false}) {
    if (h.length != 15) return null;
    // Server rewards okey OR pairs, not their sum. Prefer an already-declared
    // mode; otherwise an okey normal finish avoids unnecessary state mutation.
    final candidates = List<int>.generate(h.length, (i) => i)
      ..sort((a, b) {
        final bonus = (h[b].wild ? 1 : 0).compareTo(h[a].wild ? 1 : 0);
        return bonus != 0 ? bonus : h[a].id.compareTo(h[b].id);
      });
    BotFinish? normal;
    for (final i in candidates) {
      tick();
      final remaining = all ^ (1 << i);
      if (!o.pairsDeclared) {
        final plan = partition(remaining);
        if (plan != null) {
          final result = BotFinish(h[i], plan.map(stones).toList());
          if (h[i].wild) return result;
          normal ??= result;
        }
      }
      if (o.pairsDeclared || o.canDeclarePairs) {
        final plan = pairGroups(remaining);
        if (plan != null) return BotFinish(h[i], plan, pairs: true);
      }
    }
    return strategic && pursueOkeyDiscard ? null : normal;
  }

  double evaluate(int mask) {
    if (memo[mask] case final double score) return score;
    tick();
    final first = mask & -mask;
    var best = evaluate(mask ^ first);
    for (final group in groupsByFirst[first.bitLength - 1]) {
      if (group & mask == group) {
        best = math.max(best, 100.0 * _count(group) + evaluate(mask ^ group));
      }
    }
    for (final entry in pairsByFirst[first.bitLength - 1]) {
      if (entry.$1 & mask == entry.$1) {
        best = math.max(best, entry.$2 + evaluate(mask ^ entry.$1));
      }
    }
    // A free joker still has flexibility even before a group can be built.
    final index = first.bitLength - 1;
    if (h[index].wild) best = math.max(best, 65 + evaluate(mask ^ first));
    memo[mask] = best;
    return best;
  }

  double pairPotential(int mask) {
    var count = 0;
    var wild = 0;
    final kinds = <String, int>{};
    for (final s in stones(mask)) {
      if (s.wild) {
        wild++;
      } else {
        final key = '${s.color}:${s.number}';
        kinds.update(key, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    for (final n in kinds.values) {
      count += n ~/ 2;
    }
    var singles = kinds.values.where((n) => n.isOdd).length;
    final matched = math.min(wild, singles);
    count += matched;
    wild -= matched;
    singles -= matched;
    count += wild ~/ 2;
    // Seven real pairs equal 14 covered stones; natural singletons remain
    // merely potential. No early irreversible declaration is performed.
    return count * 200.0 + math.min(singles, 7 - count) * 12;
  }

  double handValue(int mask) {
    if (o.pairsDeclared) return pairPotential(mask);
    final normal = evaluate(mask);
    return o.canDeclarePairs
        ? math.max(normal, pairPotential(mask) - 20)
        : normal;
  }

  BotDecision bestDiscard({
    bool checkFinish = true,
    bool preservePartial = false,
  }) {
    if (checkFinish) {
      final plan = finish(strategic: true);
      if (plan != null) {
        return BotDecision(
          discardId: plan.discard.id,
          finish: plan,
          score: plan.discard.wild || plan.pairs ? 1640 : 1600,
        );
      }
    }
    BotStone? best;
    var value = -double.infinity;
    // Fixed order resolves exact ties reproducibly and does not depend on time.
    final candidates = h.toList()..sort((a, b) => a.id.compareTo(b.id));
    if (pursueOkeyDiscard) {
      candidates.removeWhere((s) => s.wild && !s.fake);
    }
    try {
      for (final s in candidates) {
        tick();
        final mask = all ^ (1 << h.indexOf(s));
        var score = handValue(mask);
        if (pursueOkeyDiscard) {
          // Plan the 14-stone target that must remain AFTER throwing an okey:
          // keep both now, improve the other 13 instead of parking both in melds.
          var target = 0.0;
          for (var i = 0; i < h.length; i++) {
            if (h[i].wild && !h[i].fake) {
              target = math.max(target, handValue(mask ^ (1 << i)));
            }
          }
          score = target * (14 / 13) + score * 0.000001;
        }
        score -= danger(s) * (1.5 + urgency * 6);
        if (s.wild) {
          score -=
              80; // Legal to discard, but preserve flexibility unless finishing.
        }
        if (score > value) {
          value = score;
          best = s;
        }
      }
    } on _Limit {
      // Only a discard choice may use a partially searched set of candidates.
      // Draw expectation must propagate the limit: an unfinished maximum is
      // not a valid value to compare against the visible discard.
      if (!preservePartial || best == null) rethrow;
      return BotDecision(discardId: best.id, score: value, limited: true);
    }
    return BotDecision(discardId: best!.id, score: value);
  }

  double danger(BotStone s) {
    var risk = 0.0;
    final retained = <String, BotPublicMove>{};
    for (final m in o.history) {
      retained.remove(m.stone.id); // Publicly discarded again: no longer held.
      if (m.takenBySeat != null && m.takenBySeat != o.ownSeat) {
        retained[m.stone.id] = m;
      }
    }
    final moves = retained.values.toList();
    for (var i = 0; i < moves.length; i++) {
      final t = moves[i].stone;
      final weight = (i + 1) / moves.length;
      if (s.wild) risk += weight * 3;
      if (s.color == t.color && (s.number - t.number).abs() <= 2) {
        risk += weight;
      }
      if (s.number == t.number && s.color != t.color) risk += weight * .7;
    }
    return math.min(3, risk);
  }

  List<(BotStone, int)>? _unknown;
  List<(BotStone, int)> unknownTypes() => _unknown ??= _buildUnknownTypes();
  List<BotStone> _drawPalette() {
    final out = <BotStone>[];
    for (final color in BotStone.colors) {
      for (var n = 1; n <= 13; n++) {
        final indicator = o.indicator;
        final wild =
            indicator != null &&
            indicator.color == color &&
            n == indicator.number % 13 + 1;
        final s = BotStone('draw:$color:$n', color, n, wild: wild);
        out.add(s);
      }
    }
    if (o.indicator case final BotStone indicator) {
      final s = BotStone(
        'draw:fake',
        indicator.color,
        indicator.number % 13 + 1,
        fake: true,
      );
      out.add(s);
    }
    return out;
  }

  List<(BotStone, int)> _buildUnknownTypes() => [
    for (final s in _drawPalette())
      if ((2 - (known[s.kind] ?? 0)).clamp(0, 2) case final int left
          when left > 0)
        (s, left),
  ];

  int _outs(BotStone a, BotStone b) {
    if (!a.wild && !b.wild && a.number != b.number && a.color != b.color) {
      return 0;
    }
    String key(BotStone s) => '${s.color}:${s.number}:${s.wild}:${s.fake}';
    final ka = key(a), kb = key(b);
    final pairKey = ka.compareTo(kb) <= 0 ? '$ka|$kb' : '$kb|$ka';
    // Group legality is invariant across hypothetical draws, but availability
    // is not. Cache legal types only; recompute remaining public copies below.
    final completing = outsCache.putIfAbsent(
      pairKey,
      () => [
        for (final s in _drawPalette())
          if (botValidGroup([a, b, s])) s,
      ],
    );
    var outs = 0;
    for (final s in completing) {
      outs += (2 - (known[s.kind] ?? 0)).clamp(0, 2);
    }
    return outs;
  }

  double connection(BotStone s, List<BotStone> hand) {
    if (s.wild) return 100;
    var value = 0.0;
    for (final t in hand) {
      if (t.color == s.color && (t.number - s.number).abs() <= 2) value += 1;
      if (t.number == s.number && t.color != s.color) value += 1;
    }
    return value;
  }
}

Iterable<BotDecision> _drawSteps(
  BotObservation observation,
  void Function() tick,
) sync* {
  final hand = observation.hand;
  final top = observation.topDiscard;
  if (top == null) {
    yield const BotDecision(
      discardId: '',
      draw: BotDrawTrace('no_top_discard'),
    );
    return;
  }
  // Per decision only: never reuse availability or another hand's indicator.
  final outsCache = <String, List<BotStone>>{};
  final taking = _Search(
    observation.withHand([...hand, top]),
    tick,
    outsCache: outsCache,
  );
  final candidate = taking.bestDiscard();
  if (candidate.finish != null) {
    yield BotDecision(
      discardId: candidate.discardId,
      takeDiscard: true,
      finish: candidate.finish,
      score: candidate.score,
      draw: BotDrawTrace('immediate_finish', taking: candidate.score),
    );
    return;
  }
  final currentSearch = _Search(observation, tick, outsCache: outsCache);
  final current = currentSearch.handValue((1 << 14) - 1);
  yield BotDecision(
    discardId: candidate.discardId,
    score: candidate.score,
    draw: BotDrawTrace(
      'expectation_incomplete',
      current: current,
      taking: candidate.score,
    ),
  );
  if (candidate.discardId == top.id) {
    yield BotDecision(
      discardId: candidate.discardId,
      score: candidate.score,
      draw: BotDrawTrace(
        'would_return_top',
        current: current,
        taking: candidate.score,
      ),
    );
    return;
  }
  // Weighted expectation over ALL unknown types, never the real deck.
  // Terminal and non-terminal outcomes use the same bounded utility.
  final available = taking.unknownTypes();
  var total = 0;
  for (final entry in available) {
    total += entry.$2;
  }
  var weighted = 0.0;
  var evaluated = 0;
  var evaluatedWeight = 0;
  // With no closed draw left, compare only against retaining this hand.
  var expectation = current;
  for (final entry
      in observation.deckRemaining == 0 ? <(BotStone, int)>[] : available) {
    final result = _Search(
      observation.withHand([...hand, entry.$1]),
      tick,
      outsCache: outsCache,
    ).bestDiscard();
    weighted += result.score * entry.$2;
    evaluatedWeight += entry.$2;
    evaluated++;
    // Every legal post-discard score is >= -102.5 (bounded risk + joker
    // penalty), <=1400; terminal outcomes <=1640. Thus these are valid bounds
    // for ALL unvisited probability mass, not a biased sample estimate.
    final remainingWeight = total - evaluatedWeight;
    final lower = (weighted - remainingWeight * 103) / total;
    final upper = (weighted + remainingWeight * 1640) / total;
    if (remainingWeight > 0 &&
        (candidate.score > upper + 1e-8 || candidate.score < lower - 1e-8)) {
      final take = candidate.score > upper + 1e-8;
      yield BotDecision(
        discardId: candidate.discardId,
        takeDiscard: take,
        score: candidate.score,
        draw: BotDrawTrace(
          take
              ? 'take_above_closed_upper_bound'
              : 'closed_above_top_lower_bound',
          current: current,
          taking: candidate.score,
          closedLower: lower,
          closedUpper: upper,
          evaluatedTypes: evaluated,
          totalTypes: available.length,
        ),
      );
      return;
    }
    // Incomplete expectation is diagnostic only. Never claim its partial
    // sum is the full expected value or accept on an optimistic estimate.
    yield BotDecision(
      discardId: candidate.discardId,
      score: candidate.score,
      draw: BotDrawTrace(
        'expectation_incomplete',
        current: current,
        taking: candidate.score,
        evaluatedTypes: evaluated,
        totalTypes: available.length,
        closedLower: lower,
        closedUpper: upper,
      ),
    );
  }
  if (observation.deckRemaining > 0 && total > 0) {
    expectation = weighted / total;
  }
  final take =
      candidate.discardId != top.id && candidate.score > expectation + 1e-8;
  yield BotDecision(
    discardId: candidate.discardId,
    takeDiscard: take,
    score: candidate.score,
    draw: BotDrawTrace(
      take
          ? 'take_beats_closed_expectation'
          : candidate.discardId == top.id
          ? 'would_return_top'
          : 'closed_expectation_better',
      current: current,
      taking: candidate.score,
      closed: expectation,
      evaluatedTypes: evaluated,
      totalTypes: available.length,
    ),
  );
}
