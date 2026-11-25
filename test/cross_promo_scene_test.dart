import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/services/cross_promo_service.dart';
import 'package:okeyix/ui/lobby/cross_promo_scene.dart';

void main() {
  setUpAll(() async {
    await Future.wait([
      (FontLoader('Montserrat')
            ..addFont(rootBundle.load('assets/fonts/Montserrat-Regular.ttf'))
            ..addFont(rootBundle.load('assets/fonts/Montserrat-Bold.ttf')))
          .load(),
      (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load(),
    ]);
  });

  testWidgets(
    'game navigation retains correct download callbacks and visible actions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(568, 320));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final downloads = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CrossPromoScene(
              games: CrossPromoService.games,
              claimed: const {},
              onDownload: (game) => downloads.add(game.id),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('promo-download-okix')));
      await tester.tap(find.byKey(const ValueKey('promo-next')));
      await tester.pumpAndSettle();
      expect(find.text('Sirenix'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('promo-download-sirenix')));
      await tester.drag(
        find.byKey(const ValueKey('promo-games')),
        const Offset(-400, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('Kartix'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('promo-download-kartix')));
      expect(downloads, ['okix', 'sirenix', 'kartix']);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('promo-download-kartix')))
            .height,
        48,
      );
      await tester.tap(find.byKey(const ValueKey('promo-previous')));
      await tester.pumpAndSettle();
      expect(find.text('Sirenix'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('single released game uses salon scene', (tester) async {
    await tester.binding.setSurfaceSize(const Size(844, 390));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Montserrat'),
        home: RepaintBoundary(
          key: const ValueKey('promo-capture'),
          child: Scaffold(
            backgroundColor: const Color(0xFF06110F),
            body: CrossPromoScene(
              games: [CrossPromoService.games.last],
              claimed: const {},
              onDownload: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      final context = tester.element(find.byType(CrossPromoScene));
      await Future.wait([
        precacheImage(
          const AssetImage('assets/images/lobby/lobby.png'),
          context,
        ),
        precacheImage(
          const AssetImage('assets/images/logo/okeyix_logo.png'),
          context,
        ),
        precacheImage(
          const AssetImage('assets/images/coins/coins_large.png'),
          context,
        ),
      ]);
    });
    await tester.pumpAndSettle();
    expect(find.text('Kartix'), findsOneWidget);
    expect(find.byKey(const ValueKey('promo-next')), findsNothing);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('promo-capture')),
      matchesGoldenFile('goldens/cross_promo_844x390.png'),
    );
  });
}
