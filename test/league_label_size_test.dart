import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/lobby/lobby_league_list.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Montserrat',
    )..addFont(rootBundle.load('assets/fonts/Montserrat-Regular.ttf'))).load();
  });
  for (final size in [
    const Size(300, 180),
    const Size(380, 270),
    const Size(520, 300),
  ]) {
    testWidgets('league labels share rendered size at $size', (tester) async {
      const names = [
        'Yeniler',
        'Müdavimler',
        'Deneyimliler',
        'Ustalar',
        'Efsaneler',
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Montserrat'),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: LobbyLeagueList(
                  leagues: List.generate(
                    5,
                    (i) => {'id': '$i', 'name': names[i]},
                  ),
                  selectedLeagueId: '0',
                  leagueActivePlayers: const {},
                  leagueActiveTables: const {},
                  onSelect: (_) {},
                  userCoin: 1000,
                  userRating: 1000,
                  loading: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final fontSizes = names
          .take(4)
          .map((name) => tester.widget<Text>(find.text(name)).style!.fontSize)
          .toSet();
      expect(fontSizes.length, 1);
      expect(
        tester.widget<Text>(find.text('Efsaneler')).style!.fontSize!,
        greaterThan(fontSizes.single!),
      );
      for (final name in names) {
        final label = find.text(name);
        expect(
          find.ancestor(of: label, matching: find.byType(FittedBox)),
          findsNothing,
        );
        final textRect = tester.getRect(label);
        final cardRect = tester.getRect(
          find.byKey(ValueKey('league-${names.indexOf(name)}')),
        );
        expect(cardRect.contains(textRect.topLeft), isTrue);
        expect(cardRect.contains(textRect.bottomRight), isTrue);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
