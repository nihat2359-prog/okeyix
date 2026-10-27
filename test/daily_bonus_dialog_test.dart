import 'package:okeyix/services/reward_audio.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/reward_dialogs.dart';

void main() {
  testWidgets('closing without Al never claims; reopening still allows a server claim', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (context) => TextButton(onPressed: () => showDialog<void>(
        context: context, builder: (_) => DailyBonusDialog(amount: 2500,
          onSound: _ignoreSound, onClaim: () async { calls++; return true; })),
        child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reward-close')));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reward-action')));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Harika! Kazandın.'), findsOneWidget);
  });
  Future<void> showBonus(
    WidgetTester tester,
    Future<bool> Function() onClaim, {
    Size size = const Size(1000, 700),
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: DailyBonusDialog(
              onSound: _ignoreSound,
              amount: 2500,
              onClaim: onClaim,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('blocks repeated claims, waits for server, then shows success', (
    tester,
  ) async {
    final pending = Completer<bool>();
    var calls = 0;
    await showBonus(tester, () {
      calls++;
      return pending.future;
    });
    expect(find.text('Harika! Kazandın.'), findsNothing);
    await tester.tap(find.byType(ElevatedButton));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    expect(calls, 1);
    expect(find.text('Alınıyor...'), findsOneWidget);
    expect(find.text('Harika! Kazandın.'), findsNothing);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    pending.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('Harika! Kazandın.'), findsOneWidget);
    expect(find.text('Devam et'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });
  testWidgets('shows error and allows retry', (tester) async {
    var calls = 0;
    await showBonus(tester, () async {
      calls++;
      if (calls == 1) throw StateError('offline');
      return true;
    });
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    expect(
      find.text('Bonus alınamadı. Lütfen tekrar deneyin.'),
      findsOneWidget,
    );
    expect(find.text('Harika! Kazandın.'), findsNothing);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Harika! Kazandın.'), findsOneWidget);
  });
  testWidgets('already claimed is not presented as a new win', (tester) async {
    await showBonus(tester, () async => false);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    expect(find.text('Bugünkü ödülün alındı'), findsOneWidget);
    expect(find.text('Harika! Kazandın.'), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });
  testWidgets('completion after disposal does not update state', (
    tester,
  ) async {
    final pending = Completer<bool>();
    await showBonus(tester, () => pending.future);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(true);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  for (final size in [const Size(320, 568), const Size(568, 320)]) {
    testWidgets('small viewport $size supports large text and scrolling', (
      tester,
    ) async {
      await showBonus(tester, () async => false, size: size, textScale: 2);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byType(ElevatedButton));
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      expect(find.text('Bugünkü ödülün alındı'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('welcome reward fits small screens with large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(2),
          ),
          child: const Scaffold(
            body: WelcomeRewardDialog(onSound: _ignoreSound, amount: 10000),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(ElevatedButton));
    expect(tester.takeException(), isNull);
    expect(find.text('Harika, başlayalım'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
  });
}

void _ignoreSound(RewardSound _) {}
