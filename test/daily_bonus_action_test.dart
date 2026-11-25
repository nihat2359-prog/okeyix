import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/reward_dialogs.dart';

void main() {
  for (final size in [
    const Size(568, 320),
    const Size(640, 360),
    const Size(844, 390),
  ]) {
    testWidgets(
      'daily claim remains visible below store and weekly trail $size',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var calls = 0;
        final pending = Completer<bool>();
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: const EdgeInsets.fromLTRB(59, 0, 44, 21),
                viewPadding: const EdgeInsets.fromLTRB(59, 0, 44, 21),
                textScaler: TextScaler.linear(2),
              ),
              child: child!,
            ),
            home: Scaffold(
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
                onStore: () {},
                onClaim: () {
                  calls++;
                  return pending.future;
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();
        final action = find.byKey(const ValueKey('reward-action'));
        expect(find.text('Günlük bonusu al'), findsOneWidget);
        expect(action.hitTestable(), findsOneWidget);
        final rect = tester.getRect(action);
        expect(rect.height, greaterThanOrEqualTo(44));
      expect(rect.width, greaterThan(size.width * .65));
        expect(rect.left, greaterThanOrEqualTo(59));
        expect(rect.right, lessThanOrEqualTo(size.width - 44));
        expect(rect.bottom, lessThanOrEqualTo(size.height - 21));
        expect(
          rect.top,
          greaterThanOrEqualTo(
            tester.getRect(find.byKey(const ValueKey('reward-day-7'))).bottom,
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(action);
        await tester.pump();
        expect(calls, 1);
        expect(tester.widget<ElevatedButton>(action).onPressed, isNull);
        pending.complete(true);
        await tester.pumpAndSettle();
        expect(find.text('Devam et'), findsOneWidget);
        expect(action.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
