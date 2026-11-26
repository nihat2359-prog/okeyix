import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/reward_dialogs.dart';
import 'package:okeyix/ui/store/coin_store_scene.dart';

void main() {
  for (final size in [const Size(568, 320), const Size(844, 390)]) {
    testWidgets('weekly reward and store remain visible at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var storeVisits = 0;
      var claims = 0;
      await tester.runAsync(() async {
        final fonts = FontLoader('Montserrat')
          ..addFont(rootBundle.load('assets/fonts/Montserrat-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Montserrat-Bold.ttf'));
        await fonts.load();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Montserrat'),
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(1.4),
            ),
            child: Scaffold(
              body: DailyBonusDialog(
                amount: 20000,
                rewardDay: 4,
                weeklyRewards: const [
                  2500,
                  5000,
                  10000,
                  20000,
                  40000,
                  80000,
                  160000,
                ],
                onSound: (_) {},
                onClaim: () async {
                  claims++;
                  return true;
                },
                onStore: () {
                  storeVisits++;
                },
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        final context = tester.element(find.byType(DailyBonusDialog));
        await Future.wait([
          precacheImage(const AssetImage('assets/images/table.png'), context),
          precacheImage(
            const AssetImage('assets/images/coins/video_reward_coins_v2.png'),
            context,
          ),
        ]);
      });
      await tester.pumpAndSettle();
      expect(find.image(const AssetImage('assets/images/coins/video_reward_coins_v2.png')), findsOneWidget);
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(CoinStoreOfferCard), findsNWidgets(4));
      expect(find.text('ELİT'), findsOneWidget);
      expect(find.text('MEGA'), findsOneWidget);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          'goldens/daily_reward_store_${size.width.toInt()}.png',
        ),
      );
      for (final key in ['reward-action', 'daily-store-open', 'reward-day-7']) {
        final rect = tester.getRect(find.byKey(ValueKey(key)));
        expect(rect.bottom, lessThanOrEqualTo(size.height));
        expect(rect.right, lessThanOrEqualTo(size.width));
      }
      await tester.tap(find.byKey(const ValueKey('daily-store-open')));
      expect(storeVisits, 1);
      expect(claims, 0);
      await tester.tap(find.byKey(const ValueKey('reward-action')));
      await tester.pumpAndSettle();
      expect(claims, 1);
      expect(find.text('Harika! Kazandın.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
