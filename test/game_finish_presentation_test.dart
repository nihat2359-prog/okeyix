import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/game_finish_presentation.dart';
import 'package:okeyix/game/components/finish_tile_layout.dart';

const sizes = [
  Size(640, 360),
  Size(800, 360),
  Size(844, 390),
  Size(932, 430),
  Size(1024, 600),
];

Future<void> showResult(
  WidgetTester tester,
  Size size, {
  bool winner = true,
  bool special = false,
  bool spectator = false,
  bool reduced = false,
  bool leaving = false,
  double scale = 1,
  VoidCallback? onLeave,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Montserrat'),
      home: Scaffold(
        body: RepaintBoundary(
          key: const ValueKey('finish-capture'),
          child: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(scale),
              padding: const EdgeInsets.fromLTRB(44, 12, 24, 21),
              disableAnimations: reduced,
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    'assets/images/table.png',
                    fit: BoxFit.cover,
                  ),
                ),
                const Positioned.fill(
                  child: ColoredBox(color: Color(0x8802080B)),
                ),
                GameFinishPresentation(
                  winner: winner,
                  spectator: spectator,
                  winnerName: 'Uzun Oyuncu Adı',
                  amount: winner ? 1800 : -1000,
                  okeyFinish: special,
                  leaving: leaving,
                  onLeave: onLeave ?? () {},
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Montserrat',
    )..addFont(rootBundle.load('assets/fonts/Montserrat-Bold.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final size in sizes) {
    test('finish tiles have a real horizontal gap at $size', () {
      final step = size.width * .6 * .8 / 13;
      final width = 90 * finishTileScale(step, 90);
      expect(step - width, closeTo(1.6, .001));
      expect(width, greaterThan(0));
    });
    for (final scale in [1.0, 2.0]) {
      for (final win in [true, false]) {
        testWidgets('result $win $size scale $scale keeps actions accessible', (
          tester,
        ) async {
          var exits = 0;
          await showResult(
            tester,
            size,
            winner: win,
            scale: scale,
            onLeave: () => exits++,
          );
          expect(find.text(win ? 'KAZANDIN' : 'KAYBETTİN'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('finish-coins')),
            win ? findsOneWidget : findsNothing,
          );
          final button = tester.getRect(
            find.byKey(const ValueKey('finish-leave')),
          );
          expect(button.left, greaterThanOrEqualTo(44));
          expect(button.right, lessThanOrEqualTo(size.width - 24));
          expect(button.bottom, lessThanOrEqualTo(size.height - 21));
          final amount = tester.getRect(
            find.byKey(const ValueKey('finish-amount')),
          );
          expect(amount.top, greaterThanOrEqualTo(12));
          expect(amount.bottom, lessThan(button.top));
          // Leaving is available immediately, even while coins are animating.
          await tester.tap(find.byKey(const ValueKey('finish-leave')));
          expect(exits, 1);
          await tester.pumpAndSettle();
          expect(tester.binding.transientCallbackCount, 0);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('special win, reduced motion, busy exit and spectator states', (
    tester,
  ) async {
    var exits = 0;
    await showResult(
      tester,
      sizes.first,
      special: true,
      reduced: true,
      leaving: true,
      onLeave: () => exits++,
    );
    expect(find.text('OKEYLİ BİTİŞ'), findsOneWidget);
    expect(find.text('Ayrılıyor...'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('finish-leave')));
    expect(exits, 0);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
    await showResult(tester, sizes.first, spectator: true);
    expect(find.text('Uzun Oyuncu Adı kazandı'), findsOneWidget);
    expect(find.byKey(const ValueKey('finish-coins')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving during celebration cleans its ticker', (tester) async {
    await showResult(tester, sizes.first, special: true);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  for (final win in [true, false]) {
    testWidgets('result presentation golden $win', (tester) async {
      await showResult(tester, sizes.first, winner: win, special: win);
      await tester.runAsync(() async {
        await precacheImage(
          const AssetImage('assets/images/table.png'),
          tester.element(find.byType(GameFinishPresentation)),
        );
      });
      await tester.pump(const Duration(milliseconds: 700));
      await expectLater(
        find.byKey(const ValueKey('finish-capture')),
        matchesGoldenFile('goldens/finish_${win ? 'win' : 'loss'}_640x360.png'),
      );
      await tester.pumpAndSettle();
    });
  }
}
