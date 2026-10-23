import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/lobby/lobby_table_listing_card.dart';
import 'package:okeyix/ui/lobby/LobbyTableWheel.dart';

void main() {
  testWidgets('four tables visible in two columns without heading or join buttons', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(
      child: SizedBox(width: 320, height: 200, child: LobbyTableWheel(
        tables: List.generate(4, (i) => <String, dynamic>{
          'id': 't$i', 'status': 'waiting', 'entry_coin': 1000,
          '_players': [{'seat_index': 0, 'user_id': 'p$i', 'username': 'Oyuncu'}],
        }),
        blockedUserIds: const {}, onJoin: (_) {}, onSpectate: (_) {},
        canSpectateAll: true, onUserTap: (_) {}, onRefresh: () async {},
        loading: false, playerCoin: 10000, playerRating: 0,
      )),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('KATIL'), findsNothing);
    expect(find.text('RAKİP BEKLİYOR'), findsNothing);
    expect(find.byTooltip('Masaları yenile'), findsNothing);
    final viewport = tester.getRect(find.byKey(const ValueKey('vertical-tables')));
    for (var i = 0; i < 4; i++) {
      final card = tester.getRect(find.byKey(ValueKey('t$i')));
      expect(viewport.contains(card.center), isTrue);
    }
    expect(tester.takeException(), isNull);
  });
  for (final width in [220.0, 280.0, 440.0]) {
    testWidgets('table stage fits $width and preserves actions', (
      tester,
    ) async {
      final calls = <String>[];
      final table = <String, dynamic>{
        'id': 'stage',
        'status': 'waiting',
        'entry_coin': 10000000,
        'pot_amount': 12000000,
        'round_count': 6,
        '_players': [
          {
            'seat_index': 0,
            'user_id': 'host',
            'username': 'Uzun İsimli Oyuncu',
            'is_bot': true,
          },
        ],
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                height: 112,
                child: MediaQuery(
                  data: const MediaQueryData(
                    textScaler: TextScaler.linear(1.5),
                  ),
                  child: LobbyTableListingCard(
                    table: table,
                    number: 1,
                    blockedUserIds: const {},
                    canSpectateAll: true,
                    onJoin: (_) => calls.add('join'),
                    onSpectate: (_) => calls.add('watch'),
                    onUserTap: (_) => calls.add('profile'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('BOT'), findsOneWidget);
      final button = find.ancestor(
        of: find.byIcon(Icons.add_rounded),
        matching: find.byType(AnimatedContainer),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.add_rounded)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.widget<AnimatedContainer>(button).transform!.entry(1, 3), 2);
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedContainer>(button).transform!.entry(1, 3), 0);
      expect(calls, isEmpty);
      await tester.tap(find.byKey(const ValueKey('seat-stage-1')));
      await tester.tap(find.byKey(const ValueKey('seat-stage-0')));
      expect(calls, ['join', 'profile']);
    });
  }
}
