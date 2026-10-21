// Frozen pre-upgrade policy for offline comparison only. Never imported by lib/.
import 'package:okeyix/game/bot/bot_engine.dart';
import 'package:okeyix/game/bot/bot_observation.dart';

class LegacyBotPolicy {
  final _keep = <String, int>{}, _recent = <String, int>{};
  String? _pending;
  String? _beforeDrawStrategy;
  void _decay(Map<String, int> memory) {
    memory.updateAll((_, n) => n - 1);
    memory.removeWhere((_, n) => n <= 0);
  }

  BotDecision decide(BotObservation o) {
    final hand = o.hand.map((s) => s.toPayload()).toList();
    final strategy = hand.length == 14
        ? decideStrategy(hand)
        : _beforeDrawStrategy ?? decideStrategy(hand);
    _beforeDrawStrategy = hand.length == 14 ? strategy : null;
    if (hand.length == 14) {
      _decay(_recent);
      final top = o.topDiscard?.toPayload();
      final gain = _immediateMeldGainFromTopDiscard(hand, top);
      final take =
          top != null &&
          !_recent.containsKey(_botTileMapKey(top)) &&
          top['is_fake_joker'] != true &&
          (gain >= 4 ||
              (gain >= 3 && !_wouldDiscardTakenTop(hand, top, strategy)));
      _pending = take ? _botTileMapKey(top) : null;
      // Original emergency finish predicate rejected every 15-stone candidate.
      return BotDecision(discardId: '', takeDiscard: take);
    }
    final plan = _buildBotFinishPlan(hand);
    if (plan != null) {
      final groups = <List<BotStone>>[];
      var group = <BotStone>[];
      for (final slot in plan['slots'] as List) {
        if (slot['tile'] is Map) {
          group.add(
            BotStone.fromJson(Map<String, dynamic>.from(slot['tile'] as Map)),
          );
        } else if (group.isNotEmpty) {
          groups.add(group);
          group = [];
        }
      }
      if (group.isNotEmpty) groups.add(group);
      final last = BotStone.fromJson(
        Map<String, dynamic>.from(plan['last_tile'] as Map),
      );
      return BotDecision(discardId: last.id, finish: BotFinish(last, groups));
    }
    _decay(_keep);
    if (_pending != null) {
      _keep[_pending!] = 8;
      _pending = null;
    }
    var tile = pickBestDiscardTile(
      hand,
      strategy,
      protectedKeys: _keep.keys.toSet(),
    );
    if (_isJokerMap(tile)) tile = _pickNonJokerTileOrFallback(hand, strategy);
    tile = _ensureLooseDiscardWhenPossible(hand, tile, strategy);
    _recent[_botTileMapKey(tile)] = 12;
    return BotDecision(discardId: tile['id'] as String);
  }

  Map<String, dynamic> _normalizeTilePayload(Map<String, dynamic> raw) {
    final valueRaw = raw['value'] ?? raw['number'] ?? 0;
    final value = valueRaw is int ? valueRaw : int.tryParse('$valueRaw') ?? 0;
    return {
      'id': (raw['id'] ?? '').toString(),
      'value': value,
      'color': (raw['color'] ?? '').toString(),
      'isJoker':
          raw['isJoker'] == true ||
          raw['joker'] == true ||
          raw['is_joker'] == true,
      'isFakeJoker':
          raw['isFakeJoker'] == true ||
          raw['fake_joker'] == true ||
          raw['is_fake_joker'] == true,
    };
  }

  List<List<Map<String, dynamic>>>? _buildValidatorCompatibleGroups(
    List<Map<String, dynamic>> hand14,
  ) {
    if (hand14.length != 14) return null;
    final tiles = <_BotFinishTile>[
      for (final t in hand14)
        _BotFinishTile(
          id: (t['id'] ?? '').toString(),
          value: (t['value'] ?? 0) as int,
          color: (t['color'] ?? '').toString(),
          isJoker: t['isJoker'] == true,
          payload: t,
        ),
    ];

    final memo = <String, List<List<_BotFinishTile>>?>{};
    final solved = _solveBotFinishGroups(tiles, memo);
    if (solved == null) return null;
    return solved
        .map((g) => g.map((t) => Map<String, dynamic>.from(t.payload)).toList())
        .toList();
  }

  List<List<_BotFinishTile>>? _solveBotFinishGroups(
    List<_BotFinishTile> tiles,
    Map<String, List<List<_BotFinishTile>>?> memo,
  ) {
    if (tiles.isEmpty) return <List<_BotFinishTile>>[];

    final key = (tiles.map((t) => t.id).toList()..sort()).join('|');
    if (memo.containsKey(key)) return memo[key];

    final first = tiles.firstWhere(
      (t) => !t.isJoker,
      orElse: () => tiles.first,
    );

    final candidates = _candidateGroupsForFirst(tiles, first);
    for (final group in candidates) {
      final groupIds = group.map((t) => t.id).toSet();
      final remaining = tiles.where((t) => !groupIds.contains(t.id)).toList();
      final rest = _solveBotFinishGroups(remaining, memo);
      if (rest != null) {
        final out = <List<_BotFinishTile>>[group, ...rest];
        memo[key] = out;
        return out;
      }
    }

    memo[key] = null;
    return null;
  }

  List<List<_BotFinishTile>> _candidateGroupsForFirst(
    List<_BotFinishTile> tiles,
    _BotFinishTile first,
  ) {
    final out = <List<_BotFinishTile>>[];
    final jokers = tiles.where((t) => t.isJoker).toList();
    final nonJokers = tiles.where((t) => !t.isJoker).toList();

    // SET candidates (size 3..4): same value, distinct colors + jokers.
    final sameValue = nonJokers.where((t) => t.value == first.value).toList();
    final uniqueByColor = <String, _BotFinishTile>{};
    for (final t in sameValue) {
      uniqueByColor.putIfAbsent(t.color, () => t);
    }
    final colorUnique = uniqueByColor.values.toList();

    for (final targetSize in const [3, 4]) {
      for (
        int nonJokerCount = 1;
        nonJokerCount <= colorUnique.length;
        nonJokerCount++
      ) {
        final jokerNeed = targetSize - nonJokerCount;
        if (jokerNeed < 0 || jokerNeed > jokers.length) continue;
        final combos = _botTileCombinations(colorUnique, nonJokerCount);
        for (final combo in combos) {
          if (!combo.contains(first)) continue;
          final g = [...combo, ...jokers.take(jokerNeed)];
          if (_isValidatorSetGroup(g)) out.add(g);
        }
      }
    }

    // RUN candidates (size >=3): same color, with jokers filling gaps, including 13->1 wrap.
    final sameColor = nonJokers.where((t) => t.color == first.color).toList();
    for (int size = 3; size <= 5; size++) {
      final target = size.clamp(1, sameColor.length).toInt();
      final combos = _botTileCombinations(sameColor, target);
      for (final combo in combos) {
        if (!combo.contains(first)) continue;
        if (_isValidatorRunGroup(combo)) out.add(combo);
      }
      for (
        int nonJokerCount = 2;
        nonJokerCount <= sameColor.length;
        nonJokerCount++
      ) {
        final jokerNeed = size - nonJokerCount;
        if (jokerNeed <= 0 || jokerNeed > jokers.length) continue;
        final baseCombos = _botTileCombinations(sameColor, nonJokerCount);
        for (final base in baseCombos) {
          if (!base.contains(first)) continue;
          final g = [...base, ...jokers.take(jokerNeed)];
          if (_isValidatorRunGroup(g)) out.add(g);
        }
      }
    }

    // Prefer larger groups first for fewer separators.
    out.sort((a, b) => b.length.compareTo(a.length));
    return out;
  }

  bool _isValidatorSetGroup(List<_BotFinishTile> g) {
    if (g.length < 3 || g.length > 4) return false;
    final jokers = g.where((t) => t.isJoker).length;
    final non = g.where((t) => !t.isJoker).toList();
    if (non.isEmpty) return false;
    final sameValue = non.every((t) => t.value == non.first.value);
    if (!sameValue) return false;
    final colors = non.map((t) => t.color).toSet();
    if (colors.length != non.length) return false;
    return (non.length + jokers) >= 3 && (non.length + jokers) <= 4;
  }

  bool _isValidatorRunGroup(List<_BotFinishTile> g) {
    if (g.length < 3) return false;
    final non = g.where((t) => !t.isJoker).toList();
    if (non.isEmpty) return false;
    final jokers = g.where((t) => t.isJoker).length;

    final colors = non.map((t) => t.color).toSet();
    if (colors.length != 1) return false;

    final vals = non.map((t) => t.value).toList()..sort();
    final uniq = vals.toSet();
    if (uniq.length != vals.length) return false;

    int gap = 0;
    for (int i = 1; i < vals.length; i++) {
      final d = vals[i] - vals[i - 1];
      if (d <= 0) return false;
      gap += (d - 1);
    }
    if (gap <= jokers) return true;

    // wrap check: treat 1 as 14
    final wrap = non.map((t) => t.value == 1 ? 14 : t.value).toList()..sort();
    gap = 0;
    for (int i = 1; i < wrap.length; i++) {
      final d = wrap[i] - wrap[i - 1];
      if (d <= 0) return false;
      gap += (d - 1);
    }
    return gap <= jokers;
  }

  List<List<_BotFinishTile>> _botTileCombinations(
    List<_BotFinishTile> input,
    int choose,
  ) {
    if (choose <= 0 || choose > input.length) return <List<_BotFinishTile>>[];
    final out = <List<_BotFinishTile>>[];
    void walk(int start, List<_BotFinishTile> current) {
      if (current.length == choose) {
        out.add(List<_BotFinishTile>.from(current));
        return;
      }
      for (int i = start; i < input.length; i++) {
        current.add(input[i]);
        walk(i + 1, current);
        current.removeLast();
      }
    }

    walk(0, <_BotFinishTile>[]);
    return out;
  }

  bool _isServerValidSlotsPayload(List<Map<String, dynamic>> slots) {
    final groups = <List<_BotFinishTile>>[];
    var current = <_BotFinishTile>[];
    var total = 0;

    for (final slot in slots) {
      final tileRaw = slot['tile'];
      if (tileRaw == null) {
        if (current.isNotEmpty) {
          groups.add(current);
          current = <_BotFinishTile>[];
        }
        continue;
      }
      if (tileRaw is! Map) return false;
      final map = Map<String, dynamic>.from(tileRaw);
      final id = (map['id'] ?? '').toString();
      if (id.isEmpty) return false;
      final valueRaw = map['value'] ?? map['number'] ?? 0;
      final value = valueRaw is int ? valueRaw : int.tryParse('$valueRaw');
      if (value == null) return false;
      final color = (map['color'] ?? '').toString();
      if (color.isEmpty) return false;
      final isJoker =
          map['isJoker'] == true ||
          map['joker'] == true ||
          map['is_joker'] == true;
      current.add(
        _BotFinishTile(
          id: id,
          value: value,
          color: color,
          isJoker: isJoker,
          payload: map,
        ),
      );
    }
    if (current.isNotEmpty) {
      groups.add(current);
    }

    for (final g in groups) {
      if (g.length < 3) return false;
      total += g.length;
      final ids = g.map((t) => t.id).toList();
      if (ids.toSet().length != ids.length) return false;
      if (!_isValidatorSetGroup(g) && !_isValidatorRunGroup(g)) {
        return false;
      }
    }

    return total == 14;
  }

  Map<String, dynamic>? _buildBotFinishPlan(List hand) {
    final normalized = hand
        .whereType<Map>()
        .map((e) => _normalizeTilePayload(Map<String, dynamic>.from(e)))
        .where((e) => (e['id']?.toString().isNotEmpty ?? false))
        .toList(growable: true);
    if (normalized.length != 15) return null;

    for (int i = 0; i < normalized.length; i++) {
      final candidateLast = Map<String, dynamic>.from(normalized[i]);
      final remaining = <Map<String, dynamic>>[
        for (int j = 0; j < normalized.length; j++)
          if (j != i) Map<String, dynamic>.from(normalized[j]),
      ];
      final groups = _buildValidatorCompatibleGroups(remaining);
      if (groups == null) continue;

      final slots = <Map<String, dynamic>>[];
      var slot = 0;
      for (int g = 0; g < groups.length && slot < 26; g++) {
        final group = groups[g];
        for (final tile in group) {
          if (slot >= 26) break;
          slots.add({'i': slot, 'tile': tile});
          slot++;
        }
        if (g < groups.length - 1 && slot < 26) {
          slots.add({'i': slot});
          slot++;
        }
      }
      while (slot < 26) {
        slots.add({'i': slot});
        slot++;
      }

      if (_isServerValidSlotsPayload(slots)) {
        return {'last_tile': candidateLast, 'slots': slots};
      }
    }
    return null;
  }

  String decideStrategy(List hand) {
    final tiles = hand.map((e) => BotTile.fromJson(e)).toList();

    int runScore = 0;
    int setScore = 0;

    for (var t in tiles) {
      // run potansiyeli
      final hasNeighbor = tiles.any(
        (x) =>
            x != t &&
            x.color == t.color &&
            (x.value == t.value - 1 ||
                x.value == t.value + 1 ||
                (t.value == 1 && x.value == 13) ||
                (t.value == 13 && x.value == 1)),
      );

      if (hasNeighbor) runScore++;

      // set potansiyeli
      final sameCount = tiles.where((x) => x != t && x.value == t.value).length;

      if (sameCount >= 1) setScore++;
    }

    return runScore >= setScore ? 'run' : 'set';
  }

  bool _wouldDiscardTakenTop(
    List hand,
    Map<String, dynamic>? topDiscard,
    String strategy,
  ) {
    if (topDiscard == null) return false;
    final candidate = List<Map<String, dynamic>>.from(
      hand.map((e) => Map<String, dynamic>.from(e as Map)),
    )..add(Map<String, dynamic>.from(topDiscard));

    final bestDiscard = pickBestDiscardTile(candidate, strategy);
    return _sameTileMap(bestDiscard, topDiscard);
  }

  int _immediateMeldGainFromTopDiscard(
    List hand,
    Map<String, dynamic>? topDiscard,
  ) {
    if (topDiscard == null) return 0;
    if (_isJokerMap(topDiscard)) return 0;
    final t = BotTile.fromJson(topDiscard);
    final tiles = hand
        .whereType<Map>()
        .map((e) => BotTile.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    final sameValueColors = tiles
        .where((x) => x.value == t.value)
        .map((x) => x.color)
        .toSet()
        .length;
    final sameColorVals = tiles
        .where((x) => x.color == t.color)
        .map((x) => x.value)
        .toSet();

    var runTouch = 0;
    if (sameColorVals.contains(t.value - 1) ||
        sameColorVals.contains(t.value + 1)) {
      runTouch += 1;
    }
    if (sameColorVals.contains(t.value - 2) ||
        sameColorVals.contains(t.value + 2)) {
      runTouch += 1;
    }

    // Set contribution is based on different colors, not duplicate same color.
    if (sameValueColors >= 2) return 4;
    if (runTouch >= 2) return 3;
    if (sameValueColors >= 1 && runTouch >= 1) return 2;
    if (sameValueColors >= 1 || runTouch >= 1) return 1;
    return 0;
  }

  bool _sameTileMap(Map<String, dynamic> a, Map<String, dynamic> b) {
    final av = _tileNumber(a);
    final bv = _tileNumber(b);
    final ac = (a['color'] ?? '').toString();
    final bc = (b['color'] ?? '').toString();
    final aj = _isJokerMap(a);
    final bj = _isJokerMap(b);
    return av == bv && ac == bc && aj == bj;
  }

  int _tileNumber(Map<String, dynamic> tile) {
    return (tile['value'] ?? tile['number'] ?? 0) as int;
  }

  bool _isJokerMap(Map<String, dynamic> tile) {
    return tile['joker'] == true ||
        tile['is_joker'] == true ||
        tile['fake_joker'] == true ||
        tile['is_fake_joker'] == true;
  }

  Map<String, dynamic> _pickNonJokerTileOrFallback(List hand, String strategy) {
    final chosen = pickWorstTile(hand, strategy);
    if (!_isJokerMap(chosen)) return chosen;
    for (final raw in hand) {
      if (raw is Map<String, dynamic> && !_isJokerMap(raw)) return raw;
    }
    for (final raw in hand) {
      if (raw is Map) return Map<String, dynamic>.from(raw);
    }
    return <String, dynamic>{'value': 1, 'color': 'red'};
  }

  Map<String, dynamic> _ensureLooseDiscardWhenPossible(
    List hand,
    Map<String, dynamic> selected,
    String strategy,
  ) {
    final normalized = hand
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
    if (normalized.isEmpty) return selected;

    final analysis = analyzeHand(normalized);
    final groupedKeySet = <String>{};
    for (final run in analysis.runs) {
      for (final t in run) {
        groupedKeySet.add('${t.color}-${t.value}');
      }
    }
    for (final set in analysis.sets) {
      for (final t in set) {
        groupedKeySet.add('${t.color}-${t.value}');
      }
    }

    String keyOf(Map<String, dynamic> t) =>
        '${(t['color'] ?? '').toString()}-${(t['value'] ?? t['number'] ?? 0)}';

    final selectedKey = keyOf(selected);
    final hasLoose = normalized.any(
      (t) => !_isJokerMap(t) && !groupedKeySet.contains(keyOf(t)),
    );
    final selectedIsGrouped = groupedKeySet.contains(selectedKey);
    if (!hasLoose || !selectedIsGrouped) return selected;

    final looseOnly = normalized
        .where((t) => !_isJokerMap(t) && !groupedKeySet.contains(keyOf(t)))
        .toList(growable: false);
    if (looseOnly.isEmpty) return selected;

    return pickBestDiscardTile(looseOnly, strategy);
  }
}

class _BotFinishTile {
  final String id;
  final int value;
  final String color;
  final bool isJoker;
  final Map<String, dynamic> payload;

  _BotFinishTile({
    required this.id,
    required this.value,
    required this.color,
    required this.isJoker,
    required this.payload,
  });
}

class BotTile {
  final int value;
  final String color;
  final bool joker;
  bool get isOkey => joker == true;
  BotTile(this.value, this.color, this.joker);

  factory BotTile.fromJson(Map<String, dynamic> json) {
    return BotTile(
      json['value'] ?? json['number'] ?? 0, // ğŸ”¥ FIX
      json['color'] ?? '',
      json['joker'] == true ||
          json['is_joker'] == true ||
          json['is_fake_joker'] == true, // ğŸ”¥ EKSTRA
    );
  }
}

bool botCanFinish(List hand) {
  if (hand.length != 15) return false;

  for (int i = 0; i < hand.length; i++) {
    final copy = List.from(hand)..removeAt(i);

    if (_isWinning14(copy)) {
      return true;
    }
  }

  return false;
}

bool _isWinning14(List hand) {
  final analysis = analyzeHand(hand);

  int groups = analysis.runs.length + analysis.sets.length;

  return groups >= 4;
}

bool shouldTakeDiscard(
  List hand,
  Map<String, dynamic>? topDiscard,
  String strategy,
) {
  if (topDiscard == null) return false;

  final t = BotTile.fromJson(topDiscard);
  final tiles = hand.map((e) => BotTile.fromJson(e)).toList();

  if (t.joker) return false;

  int score = 0;

  // SET
  final sameCount = tiles.where((x) => x.value == t.value).length;

  if (sameCount >= 2) {
    score += 100; // direkt set
  } else if (sameCount == 1) {
    score += 40; // set adayÄ±
  }
  // RUN
  final hasCloseNeighbor = tiles.any(
    (x) =>
        x.color == t.color &&
        (x.value == t.value - 1 || x.value == t.value + 1),
  );

  final hasNearNeighbor = tiles.any(
    (x) =>
        x.color == t.color &&
        (x.value == t.value - 2 || x.value == t.value + 2),
  );

  if (hasCloseNeighbor) score += 60;
  if (hasNearNeighbor) score += 30;

  // STRATEGY BOOST
  if (strategy == 'run' && hasCloseNeighbor) score += 20;
  if (strategy == 'set' && sameCount >= 1) score += 20;

  return score >= 40;
}

Map<String, dynamic> pickWorstTile(List hand, String strategy) {
  final normalized = hand
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  if (normalized.isEmpty) {
    return <String, dynamic>{'value': 1, 'color': 'red'};
  }

  final tiles = normalized.map((e) => BotTile.fromJson(e)).toList();
  final analysis = analyzeHand(hand);

  final protected = <BotTile>{};

  for (var r in analysis.runs) {
    protected.addAll(r);
  }
  for (var s in analysis.sets) {
    protected.addAll(s);
  }

  BotTile? worst;
  int worstScore = 999999;

  for (var t in tiles) {
    // âŒ joker asla atÄ±lmaz
    if (t.isOkey) continue;

    int score = 0;

    // ğŸ”’ full group
    if (protected.contains(t)) {
      score += 100;
    }

    // ğŸ”¶ near run
    final hasNeighbor = tiles.any(
      (x) =>
          x != t &&
          x.color == t.color &&
          (x.value == t.value - 1 ||
              x.value == t.value + 1 ||
              (t.value == 1 && x.value == 13) ||
              (t.value == 13 && x.value == 1)),
    );

    if (hasNeighbor) score += 40;

    // ğŸ”¶ pair
    final sameCount = tiles.where((x) => x != t && x.value == t.value).length;
    if (sameCount >= 1) score += 30;

    // ğŸ¯ orta deÄŸer
    if (t.value >= 6 && t.value <= 9) score += 5;

    // âš ï¸ uÃ§ deÄŸer
    if (t.value <= 2 || t.value >= 12) score -= 5;

    // ğŸ’€ dead tile
    if (!hasNeighbor && sameCount == 0 && !protected.contains(t)) {
      score -= 50;
    }

    if (strategy == 'run') {
      // set'e giden taÅŸlarÄ± biraz dÃ¼ÅŸÃ¼r
      if (sameCount >= 1) score -= 10;
    }

    if (strategy == 'set') {
      // run'a giden taÅŸlarÄ± biraz dÃ¼ÅŸÃ¼r
      if (hasNeighbor) score -= 10;
    }

    if (score < worstScore) {
      worstScore = score;
      worst = t;
    }
  }

  worst ??= tiles.firstWhere((x) => !x.isOkey, orElse: () => tiles.last);

  for (final tile in normalized) {
    final value = (tile['value'] ?? tile['number'] ?? 0) as int;
    final color = (tile['color'] ?? '').toString();
    if (value == worst.value && color == worst.color) {
      return tile;
    }
  }

  for (final tile in normalized) {
    final isJoker =
        tile['joker'] == true ||
        tile['is_joker'] == true ||
        tile['fake_joker'] == true ||
        tile['is_fake_joker'] == true;
    if (!isJoker) return tile;
  }

  return normalized.first;
}

Map<String, dynamic> pickBestDiscardTile(
  List hand,
  String strategy, {
  Set<String> protectedKeys = const <String>{},
}) {
  final normalized = hand
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  if (normalized.isEmpty) {
    return <String, dynamic>{'value': 1, 'color': 'red'};
  }

  final analysis = analyzeHand(normalized);
  final groupedCounts = <String, int>{};
  final groupedKeySet = <String>{};
  String keyOf(Map<String, dynamic> t) =>
      '${(t['color'] ?? '').toString()}-${(t['value'] ?? t['number'] ?? 0)}';
  for (final run in analysis.runs) {
    for (final t in run) {
      final k = '${t.color}-${t.value}';
      groupedKeySet.add(k);
      groupedCounts[k] = (groupedCounts[k] ?? 0) + 1;
    }
  }
  for (final set in analysis.sets) {
    for (final t in set) {
      final k = '${t.color}-${t.value}';
      groupedKeySet.add(k);
      groupedCounts[k] = (groupedCounts[k] ?? 0) + 1;
    }
  }

  final candidates = <int>[];
  for (int i = 0; i < normalized.length; i++) {
    if (!_botIsJokerMap(normalized[i])) {
      candidates.add(i);
    }
  }
  if (candidates.isEmpty) return normalized.first;

  // Human-like priority: discard loose tiles first.
  final looseCandidates = <int>[];
  for (final idx in candidates) {
    final key = keyOf(normalized[idx]);
    final left = groupedCounts[key] ?? 0;
    if (left > 0) {
      groupedCounts[key] = left - 1;
    } else {
      looseCandidates.add(idx);
    }
  }
  // Hard guard: if there are clearly non-group keys, never discard grouped keys.
  final nonGroupKeyCandidates = candidates
      .where((idx) => !groupedKeySet.contains(keyOf(normalized[idx])))
      .toList(growable: false);
  final evaluationCandidates = nonGroupKeyCandidates.isNotEmpty
      ? nonGroupKeyCandidates
      : (looseCandidates.isNotEmpty ? looseCandidates : candidates);

  Map<String, dynamic>? bestTile;
  var bestPotential = -1 << 30;
  var bestUsefulness = 1 << 30;
  var bestProtectedPenalty = 1 << 30;

  for (final idx in evaluationCandidates) {
    final tile = normalized[idx];
    final remaining = <Map<String, dynamic>>[];
    for (int i = 0; i < normalized.length; i++) {
      if (i != idx) remaining.add(normalized[i]);
    }

    final potential = _handPotentialScore(remaining);
    final usefulness = _tileUsefulnessScore(tile, normalized, strategy);
    final protectedPenalty = protectedKeys.contains(_botTileMapKey(tile))
        ? 1000
        : 0;

    final betterPotential = potential > bestPotential;
    final equalPotential = potential == bestPotential;
    final betterPenalty =
        equalPotential && protectedPenalty < bestProtectedPenalty;
    final equalPenalty =
        equalPotential && protectedPenalty == bestProtectedPenalty;
    final betterUsefulness = equalPenalty && usefulness < bestUsefulness;

    if (betterPotential || betterPenalty || betterUsefulness) {
      bestTile = tile;
      bestPotential = potential;
      bestUsefulness = usefulness;
      bestProtectedPenalty = protectedPenalty;
    }
  }

  return bestTile ?? pickWorstTile(hand, strategy);
}

int _handPotentialScore(List<Map<String, dynamic>> hand) {
  final analysis = analyzeHand(hand);
  var score = 0;

  for (final run in analysis.runs) {
    score += run.length * 18;
  }
  for (final set in analysis.sets) {
    score += set.length * 18;
  }

  final tiles = hand.map((e) => BotTile.fromJson(e)).toList();
  for (final t in tiles) {
    final sameCount = tiles.where((x) => x != t && x.value == t.value).length;
    if (sameCount >= 1) score += 6;

    final closeNeighbor = tiles.any(
      (x) =>
          x != t &&
          x.color == t.color &&
          (x.value == t.value - 1 ||
              x.value == t.value + 1 ||
              (t.value == 1 && x.value == 13) ||
              (t.value == 13 && x.value == 1)),
    );
    if (closeNeighbor) score += 8;
  }

  return score;
}

bool _botIsJokerMap(Map<String, dynamic> tile) {
  return tile['joker'] == true ||
      tile['is_joker'] == true ||
      tile['fake_joker'] == true ||
      tile['is_fake_joker'] == true;
}

String _botTileMapKey(Map<String, dynamic> tile) {
  final value = (tile['value'] ?? tile['number'] ?? 0) as int;
  final color = (tile['color'] ?? '').toString();
  final joker = _botIsJokerMap(tile) ? 1 : 0;
  return '$color-$value-$joker';
}

int _tileUsefulnessScore(
  Map<String, dynamic> tile,
  List<Map<String, dynamic>> hand,
  String strategy,
) {
  final t = BotTile.fromJson(tile);
  final tiles = hand.map((e) => BotTile.fromJson(e)).toList();

  var score = 0;
  final sameCount = tiles.where((x) => x.value == t.value).length - 1;
  if (sameCount >= 2) score += 60;
  if (sameCount == 1) score += 25;

  final hasCloseNeighbor = tiles.any(
    (x) =>
        x.color == t.color &&
        x.value != t.value &&
        (x.value == t.value - 1 ||
            x.value == t.value + 1 ||
            (t.value == 1 && x.value == 13) ||
            (t.value == 13 && x.value == 1)),
  );
  if (hasCloseNeighbor) score += 45;

  final hasNearNeighbor = tiles.any(
    (x) =>
        x.color == t.color &&
        x.value != t.value &&
        (x.value == t.value - 2 || x.value == t.value + 2),
  );
  if (hasNearNeighbor) score += 15;

  if (strategy == 'run' && hasCloseNeighbor) score += 10;
  if (strategy == 'set' && sameCount >= 1) score += 10;

  if (t.value >= 6 && t.value <= 9) score += 5;
  return score;
}

class HandAnalysis {
  List<List<BotTile>> runs = [];
  List<List<BotTile>> sets = [];
  List<BotTile> useless = [];
}

HandAnalysis analyzeHand(List hand) {
  final tiles = hand
      .whereType<Map>()
      .map((e) => BotTile.fromJson(Map<String, dynamic>.from(e)))
      .toList();
  final result = HandAnalysis();

  final byColor = <String, List<BotTile>>{};

  for (var t in tiles) {
    if (t.isOkey) continue;
    byColor.putIfAbsent(t.color, () => []).add(t);
  }

  /// seri analizi
  for (var color in byColor.keys) {
    final list = [...byColor[color]!];
    list.sort((a, b) => a.value.compareTo(b.value));

    // For runs, duplicate numbers of the same color don't extend sequence.
    final uniqueByValue = <int, BotTile>{};
    for (final t in list) {
      uniqueByValue.putIfAbsent(t.value, () => t);
    }
    final values = uniqueByValue.keys.toList()..sort();

    var current = <BotTile>[];
    for (final v in values) {
      final tile = uniqueByValue[v]!;
      if (current.isEmpty) {
        current.add(tile);
      } else if (v == current.last.value + 1 ||
          (current.last.value == 13 && v == 1)) {
        current.add(tile);
      } else {
        if (current.length >= 3) result.runs.add(List<BotTile>.from(current));
        current = [tile];
      }
    }
    if (current.length >= 3) result.runs.add(List<BotTile>.from(current));
  }

  /// per analizi
  final byValue = <int, List<BotTile>>{};

  for (var t in tiles) {
    if (t.isOkey) continue;
    byValue.putIfAbsent(t.value, () => []).add(t);
  }

  for (final valueGroup in byValue.values) {
    // Sets must be same number, different colors.
    final uniqueByColor = <String, BotTile>{};
    for (final t in valueGroup) {
      uniqueByColor.putIfAbsent(t.color, () => t);
    }
    final set = uniqueByColor.values.toList();
    if (set.length >= 3) {
      result.sets.add(set);
    }
  }

  return result;
}
