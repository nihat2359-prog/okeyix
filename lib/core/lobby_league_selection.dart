/// The lobby's existing access rule: both balance and rating must qualify.
bool canAccessLobbyLeague(
  Map<String, dynamic> league, {
  required int coins,
  required int rating,
}) =>
    coins >= ((league['min_coin'] as num?)?.toInt() ?? 0) &&
    rating >= ((league['min_rating'] as num?)?.toInt() ?? 0);

/// In-memory selection, scoped to a login rather than a particular route.
class LobbyLeagueSelection {
  String? _session;
  String? selectedId;

  void useSession(String session) {
    if (_session == session) return;
    _session = session;
    selectedId = null;
  }

  String? resolve(
    List<Map<String, dynamic>> orderedLeagues, {
    required int coins,
    required int rating,
  }) {
    if (orderedLeagues.isEmpty) return null;
    for (final league in orderedLeagues) {
      if (league['id'] == selectedId &&
          canAccessLobbyLeague(league, coins: coins, rating: rating)) {
        return selectedId;
      }
    }
    for (final league in orderedLeagues.reversed) {
      if (canAccessLobbyLeague(league, coins: coins, rating: rating)) {
        return selectedId = league['id'] as String;
      }
    }
    // Keep an inaccessible league locked; never bypass its access checks.
    final existing = orderedLeagues.where((l) => l['id'] == selectedId);
    return selectedId =
        (existing.isEmpty ? orderedLeagues.first : existing.first)['id']
            as String;
  }
}
