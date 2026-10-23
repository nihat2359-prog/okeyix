const lobbyTableStatuses = ['waiting', 'start', 'playing'];

/// The league table count follows the list, including visible starting games.
Map<String, int> listedLeagueTableCounts(
  List<Map<String, dynamic>> tables,
  List<Map<String, dynamic>> seats,
) {
  final occupied = <String>{
    for (final seat in seats)
      if (seat['user_id'] != null && seat['table_id'] != null)
        seat['table_id'].toString(),
  };
  final seen = <String>{};
  final counts = <String, int>{};
  for (final table in tables) {
    final id = table['id']?.toString();
    final league = table['league_id']?.toString();
    if (id == null ||
        league == null ||
        !occupied.contains(id) ||
        !lobbyTableStatuses.contains(table['status']) ||
        !seen.add(id))
      continue;
    counts[league] = (counts[league] ?? 0) + 1;
  }
  return counts;
}

/// Humans use their rating league; seated bots use their actual table league.
/// Each account is counted once, including bots whose profile says online.
Map<String, int> leaguePlayerCounts({
  required List<Map<String, dynamic>> leagues,
  required List<Map<String, dynamic>> onlineProfiles,
  required List<Map<String, dynamic>> tables,
  required List<Map<String, dynamic>> seats,
  required Set<String> botIds,
}) {
  final sorted = [...leagues]
    ..sort(
      (a, b) => ((a['min_rating'] as num?) ?? 0).compareTo(
        (b['min_rating'] as num?) ?? 0,
      ),
    );
  final result = <String, int>{for (final l in sorted) '${l['id']}': 0};
  final counted = <String>{};
  for (final p in onlineProfiles) {
    final id = p['id']?.toString();
    if (id == null || botIds.contains(id) || counted.contains(id)) continue;
    final rating = (p['rating'] as num?)?.toInt() ?? 1200;
    for (var i = 0; i < sorted.length; i++) {
      final l = sorted[i];
      final min = (l['min_rating'] as num?)?.toInt() ?? 0;
      final explicit = (l['max_rating'] as num?)?.toInt();
      final max = explicit != null && explicit > 0
          ? explicit
          : i + 1 < sorted.length
          ? ((sorted[i + 1]['min_rating'] as num?)?.toInt() ?? 9999999) - 1
          : 9999999;
      if (rating >= min && rating <= max) {
        result['${l['id']}'] = result['${l['id']}']! + 1;
        counted.add(id);
        break;
      }
    }
  }
  final tableLeague = <String, String>{
    for (final t in tables)
      if (['waiting', 'start', 'starting', 'playing'].contains(t['status']) &&
          result.containsKey(t['league_id']?.toString()))
        '${t['id']}': '${t['league_id']}',
  };
  for (final seat in seats) {
    final id = seat['user_id']?.toString();
    final league = tableLeague[seat['table_id']?.toString()];
    if (id == null ||
        league == null ||
        !botIds.contains(id) ||
        !counted.add(id)) {
      continue;
    }
    result[league] = result[league]! + 1;
  }
  return result;
}
