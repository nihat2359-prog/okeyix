import 'dart:math';

const lobbyTableDisplayTarget = 8;

const showcaseTableMessage =
    "Bu masa şu an dolu, üstteki açık masaya katılabilir veya Hemen Oyna'yı kullanabilirsiniz";

/// Real waiting seats first, followed by real games and finally display rows.
int compareLobbyTables(Map<String, dynamic> a, Map<String, dynamic> b) {
  int priority(Map<String, dynamic> table) {
    if (table['is_fake'] == true) return 3;
    final players = (table['_players'] as List?) ?? const [];
    if (table['status'] == 'waiting' &&
        players.isNotEmpty &&
        players.length < ((table['max_players'] as num?)?.toInt() ?? 2)) {
      return players.any((p) => p['is_bot'] != true) ? 0 : 1;
    }
    return 2;
  }

  final order = priority(a).compareTo(priority(b));
  if (order != 0) return order;
  if (a['is_fake'] == true) {
    return a['id'].toString().compareTo(b['id'].toString());
  }
  return (b['created_at']?.toString() ?? '')
      .compareTo(a['created_at']?.toString() ?? '');
}

/// Pure UI composition. Display rows never enter database seat/table reads.
List<Map<String, dynamic>> completeLobbyTables({
  required List<Map<String, dynamic>> realTables,
  required Map<String, dynamic> league,
  required List<Map<String, dynamic>> botPlayers,
  Random? random,
}) {
  final tables = realTables.where((t) => t['is_fake'] != true).toList();
  final missing = max(0, lobbyTableDisplayTarget - tables.length);
  if (missing == 0) return tables..sort(compareLobbyTables);

  final poolById = <String, Map<String, dynamic>>{};
  for (final player in botPlayers) {
    final id = player['id']?.toString();
    if (id != null && id.isNotEmpty &&
        (player['username']?.toString().trim().isNotEmpty ?? false)) {
      poolById[id] = player;
    }
  }
  // An unavailable backend must still leave the room populated. Use the
  // existing bundled avatar assets with local, presentation-only identities.
  if (poolById.length < missing * 2) {
    for (var i = 0; i < _fallbackNames.length; i++) {
      poolById['display-player-$i'] = {
        'id': 'display-player-$i', 'username': _fallbackNames[i],
        'avatar_url': 'assets/images/avatars/avatar${_fallbackAvatars[i]}.png',
      };
    }
  }
  final rng = random ?? Random();
  final pool = poolById.values.toList()..shuffle(rng);
  final rounds = List.generate(12, (i) => i + 1)..shuffle(rng);
  final entry = (league['min_coin'] as num?)?.toInt() ?? 1000;
  for (var i = 0; i < missing; i++) {
    tables.add({
      'id': 'showcase:${league['id']}:$i', 'league_id': league['id'],
      'is_fake': true, 'status': 'playing', 'max_players': 2,
      'entry_coin': entry,
      'pot_amount': entry * 2 * rounds[i], 'round_count': rounds[i],
      'spectators_enabled': false, 'chat_enabled': false,
      '_players': List.generate(2, (seat) {
        final player = pool[i * 2 + seat];
        return {
          'seat_index': seat, 'user_id': player['id'],
          'username': player['username'], 'avatar_url': player['avatar_url'],
          'is_bot': true,
        };
      }),
    });
  }
  return tables..sort(compareLobbyTables);
}

const _fallbackNames = ['Emre K.', 'Selin Y.', 'Murat T.', 'Zeynep A.',
  'Kerem B.', 'Elif D.', 'Mert S.', 'İrem G.', 'Burak E.', 'Ece M.',
  'Onur A.', 'Ceren K.', 'Arda Y.', 'Derya T.', 'Hakan S.', 'Pelin B.'];
const _fallbackAvatars = [8, 13, 11, 6, 10, 7, 2, 12, 3, 15, 1, 5, 9, 17, 4, 18];
