import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/services/game_view_data_source.dart';
import 'package:okeyix/ui/table_session_score.dart';

void main() {
  GameViewDataSource source({
    required String table,
    required String? Function() user,
    required Future<ViewRow> Function() fetch,
    DateTime Function()? now,
  }) => GameViewDataSource(
    tableId: table,
    currentUser: user,
    fetchTable: () async => {},
    fetchPlayers: () async => [],
    fetchUsers: (_) async => [],
    fetchProfiles: (_) async => [],
    fetchLeague: (_) async => [],
    fetchSessionScore: fetch,
    now: now,
  );

  test(
    'concurrent refreshes share one query; next existing tick rereads',
    () async {
      var clock = DateTime.utc(2026);
      var calls = 0;
      var wins = 0;
      final data = source(
        table: 'a',
        user: () => 'me',
        now: () => clock,
        fetch: () async {
          calls++;
          return {'table_id': 'a', 'wins': wins, 'losses': 0};
        },
      );
      final results = await Future.wait([
        data.sessionScore(),
        data.sessionScore(),
      ]);
      expect(calls, 1);
      expect(results.first['wins'], 0);
      wins = 1;
      clock = clock.add(const Duration(seconds: 2));
      expect((await data.sessionScore())['wins'], 1);
      expect(calls, 2);
      // A new deal does not clear previously confirmed session results.
      data.tableChanged('next-round');
      expect((await data.sessionScore())['wins'], 1);
      data.dispose();
    },
  );

  test(
    'old table disposal rejects late reply; new table starts at zero',
    () async {
      final pending = Completer<ViewRow>();
      final old = source(
        table: 'old',
        user: () => 'me',
        fetch: () => pending.future,
      );
      final read = old.sessionScore();
      final rejected = expectLater(read, throwsStateError);
      old.dispose();
      final fresh = source(
        table: 'new',
        user: () => 'me',
        fetch: () async => {'table_id': 'new', 'wins': 0, 'losses': 0},
      );
      pending.complete({'table_id': 'old', 'wins': 8, 'losses': 3});
      await rejected;
      expect((await fresh.sessionScore())['wins'], 0);
      fresh.dispose();
    },
  );

  test(
    'auth changes reject old user reply and load new user results',
    () async {
      var user = 'old';
      var calls = 0;
      final pending = Completer<ViewRow>();
      final data = source(
        table: 'same',
        user: () => user,
        fetch: () {
          calls++;
          return calls == 1
              ? pending.future
              : Future.value({'table_id': 'same', 'wins': 0, 'losses': 1});
        },
      );
      final read = data.sessionScore();
      final rejected = expectLater(read, throwsStateError);
      user = 'new';
      pending.complete({'table_id': 'same', 'wins': 9, 'losses': 0});
      await rejected;
      expect((await data.sessionScore())['losses'], 1);
      data.dispose();
    },
  );

  test('reconnect invalidation bypasses short cache', () async {
    var calls = 0;
    final data = source(
      table: 'a',
      user: () => 'me',
      fetch: () async {
        calls++;
        return {'table_id': 'a', 'wins': calls, 'losses': 0};
      },
    );
    await data.sessionScore();
    data.invalidateAll();
    expect((await data.sessionScore())['wins'], 2);
    data.dispose();
  });

  for (final size in [
    const Size(480, 270),
    const Size(568, 320),
    const Size(667, 375),
    const Size(844, 390),
  ]) {
    testWidgets('compact landscape score below controls at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              padding: const EdgeInsets.symmetric(horizontal: 44),
              viewPadding: const EdgeInsets.symmetric(horizontal: 44),
              textScaler: const TextScaler.linear(1.4),
            ),
            child: const Scaffold(
              body: SafeArea(child: Stack(
                children: [
                  Positioned(
                    top: 10,
                    left: 6,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 220, height: 46),
                        SizedBox(height: 4),
                        Padding(
                          padding: EdgeInsets.only(left: 18),
                          child: TableSessionScore(wins: 1234, losses: 5678),
                        ),
                      ],
                    ),
                  ),
                ],
              )),
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.emoji_events_rounded), findsOneWidget);
      expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
      expect(find.text('Galibiyet'), findsNothing);
      expect(find.text('Mağlubiyet'), findsNothing);
      expect(find.text('Toplam'), findsNothing);
      expect(find.text('6912'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('6912')).dy,
        greaterThan(tester.getTopLeft(find.text('5678')).dy),
      );
      final rect = tester.getRect(find.byType(TableSessionScore));
      expect(rect.width, 72);
      expect(rect.top, 60);
      expect(rect.left, 44 + 6 + 18);
      expect(find.byType(Table), findsOneWidget);
      expect(rect.bottom, lessThan(150));
      expect(tester.takeException(), isNull);
    });
  }
}
