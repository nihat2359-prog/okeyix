import '../../engine/models/tile.dart';

/// Local presentation only. Indices identify physical copies, never values.
List<int> serialRackPlan(List<TileModel> tiles, {required int columns}) {
  if (tiles.length > columns * 2) {
    throw ArgumentError('Hand exceeds rack capacity');
  }
  final candidates = <int, List<int>>{};
  final jokers = [
    for (var i = 0; i < tiles.length; i++)
      if (tiles[i].isJoker) i,
  ];
  void add(List<int> group) {
    final mask = group.fold(0, (int m, i) => m | (1 << i));
    candidates.putIfAbsent(mask, () => List.of(group));
  }

  // Enumerate intervals and physical copies, including jokers at either end
  // or inside a run. Keep the existing ruleset's sole wrap: 12-13-1.
  for (final color in TileColor.values) {
    final byValue = <int, List<int>>{};
    for (var i = 0; i < tiles.length; i++) {
      final t = tiles[i];
      if (!t.isJoker && t.color == color && t.value >= 1 && t.value <= 13) {
        byValue.putIfAbsent(t.value, () => []).add(i);
      }
    }
    void interval(List<int> values) {
      void visit(int at, List<int> group, int usedJokers) {
        if (at == values.length) {
          if (group.length - usedJokers >= 2) add(group);
          return;
        }
        for (final index in byValue[values[at]] ?? <int>[]) {
          visit(at + 1, [...group, index], usedJokers);
        }
        for (final index in jokers) {
          if (!group.contains(index))
            visit(at + 1, [...group, index], usedJokers + 1);
        }
      }

      // Avoid exploring intervals that cannot possibly be filled.
      if (values.where((v) => !byValue.containsKey(v)).length <=
          jokers.length) {
        visit(0, [], 0);
      }
    }

    for (var start = 1; start <= 11; start++) {
      for (var end = start + 2; end <= 13; end++) {
        interval([for (var v = start; v <= end; v++) v]);
      }
    }
    interval([12, 13, 1]);
  }
  // Sets have distinct colours; duplicate physical copies are alternatives.
  for (var value = 1; value <= 13; value++) {
    void visit(int color, List<int> group, int natural) {
      if (color == TileColor.values.length) {
        if (group.length >= 3 && natural >= 2) add(group);
        return;
      }
      visit(color + 1, group, natural);
      for (var i = 0; i < tiles.length; i++) {
        if (!tiles[i].isJoker &&
            tiles[i].value == value &&
            tiles[i].color.index == color) {
          visit(color + 1, [...group, i], natural + 1);
        }
      }
      for (final index in jokers) {
        if (!group.contains(index))
          visit(color + 1, [...group, index], natural);
      }
    }

    visit(0, [], 0);
  }

  final byTile = List.generate(tiles.length, (_) => <int>[]);
  for (final entry in candidates.entries) {
    for (final i in entry.value) {
      byTile[i].add(entry.key);
    }
  }
  final memo = <int, ({int score, List<List<int>> groups})>{};
  ({int score, List<List<int>> groups}) solve(int mask) {
    if (mask == 0) return (score: 0, groups: []);
    if (memo.containsKey(mask)) return memo[mask]!;
    var first = 0;
    while ((mask & (1 << first)) == 0) {
      first++;
    }
    var best = solve(mask & ~(1 << first));
    for (final candidate in byTile[first]) {
      if ((candidate & mask) != candidate) continue;
      final group = candidates[candidate]!;
      final rest = solve(mask ^ candidate);
      // Maximise covered tiles first; prefer coherent longer runs on ties.
      final score =
          rest.score + group.length * 1000 + group.length * group.length;
      if (score > best.score)
        best = (score: score, groups: [group, ...rest.groups]);
    }
    return memo[mask] = best;
  }

  final groups = solve((1 << tiles.length) - 1).groups.toList();
  groups.sort((a, b) {
    final color = tiles[a.first].color.index.compareTo(
      tiles[b.first].color.index,
    );
    return color != 0
        ? color
        : tiles[a.first].value.compareTo(tiles[b.first].value);
  });
  final used = groups.expand((g) => g).toSet();
  final remaining = [
    for (var i = 0; i < tiles.length; i++)
      if (!used.contains(i)) i,
  ];
  final loose = <List<int>>[];
  // Preserve same-colour neighbours before collecting same-number pairs.
  for (final color in TileColor.values) {
    final sorted =
        remaining
            .where((i) => !tiles[i].isJoker && tiles[i].color == color)
            .toList()
          ..sort((a, b) => tiles[a].value.compareTo(tiles[b].value));
    for (final i in sorted) {
      if (!remaining.contains(i)) continue;
      final block = [i];
      var value = tiles[i].value;
      while (true) {
        final next = sorted.where(
          (j) => remaining.contains(j) && tiles[j].value == value + 1,
        );
        if (next.isEmpty) break;
        block.add(next.first);
        value++;
      }
      if (block.length >= 2) {
        loose.add(block);
        remaining.removeWhere(block.contains);
      }
    }
  }
  remaining.sort((a, b) {
    final value = tiles[a].value.compareTo(tiles[b].value);
    return value != 0
        ? value
        : tiles[a].color.index.compareTo(tiles[b].color.index);
  });
  while (remaining.isNotEmpty) {
    final first = remaining.removeAt(0);
    final block = [first];
    if (!tiles[first].isJoker) {
      block.addAll(
        remaining.where(
          (i) => !tiles[i].isJoker && tiles[i].value == tiles[first].value,
        ),
      );
      remaining.removeWhere(block.contains);
    }
    loose.add(block);
  }
  final plan = List.filled(tiles.length, -1);
  final occupied = <int>{};
  // Singles form one compact, right-aligned block, not separate groups with
  // a gap after each tile. Reserve it before placing the other blocks.
  final singles = loose.where((block) => block.length == 1).expand((b) => b).toList();
  loose.removeWhere((block) => block.length == 1);
  final bottomSingles = singles.take(columns).toList();
  final singlesStart = columns - bottomSingles.length;
  for (var i = 0; i < bottomSingles.length; i++) {
    plan[bottomSingles[i]] = singlesStart + i;
    occupied.add(singlesStart + i);
  }
  if (bottomSingles.isNotEmpty && singlesStart > 0) {
    occupied.add(singlesStart - 1);
  }
  if (singles.length > columns) loose.add(singles.sublist(columns));
  void place(List<List<int>> blocks, int preferredRow) {
    for (final block in blocks) {
      int? start;
      for (final row in [preferredRow, 1 - preferredRow]) {
        for (var col = 0; col + block.length <= columns; col++) {
          final slot = row * columns + col;
          if (List.generate(
            block.length,
            (i) => slot + i,
          ).every((s) => !occupied.contains(s))) {
            start = slot;
            break;
          }
        }
        if (start != null) break;
      }
      if (start == null)
        continue; // Final pass always assigns every physical tile.
      for (var i = 0; i < block.length; i++) {
        plan[block[i]] = start + i;
        occupied.add(start + i);
      }
      if ((start % columns) + block.length < columns)
        occupied.add(start + block.length);
    }
  }

  place(groups, 1); // Rack coordinates: second row is visually upper.
  place(loose, 0);
  final actual = plan.where((s) => s >= 0).toSet();
  for (var i = 0; i < plan.length; i++) {
    if (plan[i] >= 0) continue;
    final slot = List.generate(
      columns * 2,
      (s) => s,
    ).firstWhere((s) => !actual.contains(s));
    plan[i] = slot;
    actual.add(slot);
  }
  return plan;
}
