import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/core/league_player_counts.dart';
import 'package:okeyix/ui/lobby/lobby_league_list.dart';

void main() {
  test('open counts exclude full, empty, playing and showcase tables', () {
    final tables = List.generate(5, (i) => <String, dynamic>{
      'id': '$i', 'league_id': 'standard', 'status': i == 3 ? 'playing' : 'waiting',
      'max_players': 2, 'is_fake': i == 4,
    });
    final seats = [
      for (final id in ['0', '1', '3', '4']) {'table_id': id, 'user_id': 'a'},
      {'table_id': '1', 'user_id': 'b'},
    ];
    expect(openLeagueTableCounts(tables, seats), {'standard': 1});
  });

  testWidgets('five league badges fit a short landscape panel', (tester) async {
    await tester.binding.setSurfaceSize(const Size(568, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(
      child: SizedBox(width: 280, height: 160, child: LobbyLeagueList(
        leagues: List.generate(5, (i) => {'id': '$i', 'name': 'Lig $i'}),
        selectedLeagueId: '0', leagueActivePlayers: const {},
        leagueActiveTables: const {'0': 1, '1': 2, '2': 0, '3': 3, '4': 4},
        onSelect: (_) {}, userCoin: 100, userRating: 100, loading: false,
      )),
    ))));
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      expect(find.byKey(ValueKey('league-open-tables-$i')), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    final first = tester.getRect(find.byKey(const ValueKey('league-0')));
    final second = tester.getRect(find.byKey(const ValueKey('league-1')));
    final last = tester.getRect(find.byKey(const ValueKey('league-4')));
    expect(first.top, second.top);
    expect(last.width, greaterThan(first.width * 1.9));
  });
}
