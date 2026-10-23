import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/core/league_player_counts.dart';

void main() {
  test('table counters include starting games and exclude orphan rows', () {
    final rows = <Map<String, dynamic>>[
      {'id': 'empty', 'league_id': 'standard', 'status': 'waiting'},
      {'id': 'waiting', 'league_id': 'standard', 'status': 'waiting'},
      {'id': 'playing', 'league_id': 'standard', 'status': 'playing'},
      {'id': 'starting', 'league_id': 'standard', 'status': 'start'},
      {'id': 'waiting', 'league_id': 'standard', 'status': 'waiting'},
    ];
    expect(listedLeagueTableCounts(rows, [
      {'table_id': 'waiting', 'user_id': 'bot'},
      {'table_id': 'playing', 'user_id': 'human'},
      {'table_id': 'starting', 'user_id': 'human2'},
    ]), {'standard': 3});
    expect(listedLeagueTableCounts(rows, []), isEmpty);
  });
  final leagues = [
    {'id': 'standard', 'min_rating': 0},
    {'id': 'bronze', 'min_rating': 1500},
    {'id': 'silver', 'min_rating': 2000},
    {'id': 'gold', 'min_rating': 2500},
    {'id': 'elite', 'min_rating': 3000},
  ];
  test('counts seated bots in table league, not rating league, once', () {
    final counts = leaguePlayerCounts(
      leagues: leagues,
      onlineProfiles: [
        {'id': 'human', 'rating': 1500},
        {'id': 'bot', 'rating': 3000},
      ],
      tables: [
        {'id': 'table', 'league_id': 'standard', 'status': 'waiting'},
      ],
      seats: [
        {'table_id': 'table', 'user_id': 'bot'},
        {'table_id': 'table', 'user_id': 'bot'},
      ],
      botIds: {'bot'},
    );
    expect(counts, {
      'standard': 1,
      'bronze': 1,
      'silver': 0,
      'gold': 0,
      'elite': 0,
    });
  });
  test('offline humans and idle bots do not inflate activity', () {
    expect(
      leaguePlayerCounts(
        leagues: leagues,
        onlineProfiles: [],
        tables: [
          {'id': 't', 'league_id': 'silver', 'status': 'waiting'},
        ],
        seats: [
          {'table_id': 't', 'user_id': 'offline-human'},
        ],
        botIds: {'idle-bot'},
      )['silver'],
      0,
    );
  });
  test('start, playing count but ended tables do not', () {
    for (final status in ['start', 'starting', 'playing', 'finished']) {
      final counts = leaguePlayerCounts(
        leagues: leagues,
        onlineProfiles: [],
        tables: [
          {'id': 't', 'league_id': 'elite', 'status': status},
        ],
        seats: [
          {'table_id': 't', 'user_id': 'bot'},
        ],
        botIds: {'bot'},
      );
      expect(counts['elite'], status == 'finished' ? 0 : 1);
    }
  });
  test('human ratings retain live league boundaries without duplication', () {
    final counts = leaguePlayerCounts(
      leagues: leagues.reversed.toList(),
      onlineProfiles: [
        {'id': 'a', 'rating': 1499},
        {'id': 'b', 'rating': 1500},
        {'id': 'c', 'rating': 2000},
        {'id': 'd', 'rating': 2500},
        {'id': 'e', 'rating': 3000},
        {'id': 'e', 'rating': 3000},
      ],
      tables: [],
      seats: [],
      botIds: {},
    );
    expect(counts.values.every((v) => v == 1), isTrue);
  });
}
