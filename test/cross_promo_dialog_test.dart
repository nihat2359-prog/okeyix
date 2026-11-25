import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/lobby/cross_promo_dialog.dart';
import 'package:okeyix/ui/lobby/lobby_bottom_dock.dart';
import 'package:okeyix/services/cross_promo_service.dart';

void main() {
  for (final size in [
    const Size(480, 270),
    const Size(568, 320),
    const Size(844, 390),
  ]) {
    testWidgets('promo dialog fits notched landscape $size', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var downloads = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => MediaQuery(
            data: MediaQueryData(
              size: size,
              padding: const EdgeInsets.fromLTRB(59, 0, 44, 21),
              textScaler: TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: CrossPromoDialog(
            games: CrossPromoService.games,
            onDownload: (_) async {
              downloads++;
              return 5000;
            },
            isClaimed: (_) async => false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('İndir & +5.000 Çip Kazan').first);
      await tester.pumpAndSettle();
      expect(downloads, 1);
      expect(find.text('MAĞAZADA AÇ'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('games action fits existing six-action dock on small landscape', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(568, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var games = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: LobbyBottomDock(
                left: const Text('Oyuncu · 25.000 çip'),
                center: LobbyDockCreate(onTap: () {}),
                right: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LobbyDockAction(
                      label: 'Oyunlarımız',
                      icon: Icons.sports_esports_outlined,
                      onTap: () => games++,
                    ),
                    for (final label in [
                      'Mağaza',
                      'Davet',
                      'Sıralama',
                      'Arkadaşlar',
                      'Mesajlar',
                    ])
                      LobbyDockAction(
                        label: label,
                        icon: Icons.star_outline,
                        onTap: () {},
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oyunlarımız'));
    expect(games, 1);
    expect(tester.takeException(), isNull);
  });
}
