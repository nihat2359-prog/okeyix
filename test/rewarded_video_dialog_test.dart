import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/reward_dialogs.dart';
import 'package:okeyix/core/rewarded_ad_phase.dart';

void main() {
  testWidgets('shows real preparation phases and preserves reward until confirmation', (tester) async {
    final pending = Completer<bool>();
    late ValueChanged<RewardedAdPhase> report;
    await tester.binding.setSurfaceSize(const Size(568, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RewardedVideoDialog(
      onSound: (_) {}, onClaim: () async => false,
      onClaimWithProgress: (onProgress) { report = onProgress; return pending.future; },
    ))));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('reward-action')));
    await tester.pump();
    for (final phase in RewardedAdPhase.values) {
      report(phase);
      await tester.pump();
      expect(find.text(phase.label), findsOneWidget);
      expect(find.text(phase.message), findsOneWidget);
      expect(find.text('Harika! Kazandın.'), findsNothing);
      expect(tester.widget<ElevatedButton>(find.byKey(const ValueKey('reward-action'))).onPressed, isNull);
      expect(tester.takeException(), isNull);
    }
    pending.complete(true);
    await tester.pump();
    expect(find.text('Harika! Kazandın.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    report(RewardedAdPhase.verifying);
    expect(tester.takeException(), isNull);
  });
  for (final size in [const Size(568, 320), const Size(667, 300), const Size(844, 390)]) {
    testWidgets('reward action remains visible at $size with large text', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final pending = Completer<bool>();
      var calls = 0;
      await tester.pumpWidget(MaterialApp(home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(1.5)),
        child: Scaffold(body: RewardedVideoDialog(
          onSound: (_) {}, onPrivacy: () async {},
          onClaim: () { calls++; return pending.future; },
        )),
      )));
      await tester.pump(const Duration(seconds: 1));
      final action = find.byKey(const ValueKey('reward-action'));
      expect(tester.getRect(action).bottom, lessThanOrEqualTo(size.height));
      expect(tester.takeException(), isNull);
      await tester.tap(action);
      await tester.pump();
      await tester.tap(action);
      expect(calls, 1);
      expect(find.text('Harika! Kazandın.'), findsNothing);
      pending.complete(true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Harika! Kazandın.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('unfinished video allows retry without showing a win', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RewardedVideoDialog(
      onSound: (_) {}, onClaim: () async {
        calls++;
        if (calls == 1) throw StateError('Ödül için videoyu tamamlamalısın.');
        return true;
      },
    ))));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('reward-action')));
    await tester.pump();
    expect(find.text('Ödül için videoyu tamamlamalısın.'), findsOneWidget);
    expect(find.text('Harika! Kazandın.'), findsNothing);
    await tester.tap(find.text('Tekrar dene'));
    await tester.pump();
    expect(find.text('Harika! Kazandın.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
