import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/dev/pisti/pisti_model.dart';
import 'package:okeyix/dev/pisti/pisti_screen.dart';

void main() {
  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(844, 390),
    PistiScenario scenario = PistiScenario.pisti,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            textScaler: TextScaler.linear(1.3),
          ),
          child: PistiDemoScreen(initialScenario: scenario, seed: 42),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final seven = find.byKey(const ValueKey('pisti-card-45'));
  for (final size in [
    const Size(568, 280),
    const Size(640, 320),
    const Size(844, 390),
    const Size(960, 320),
    const Size(1024, 600),
  ]) {
    testWidgets(
      'cards, menu and result stay inside landscape SafeArea at $size',
      (tester) async {
        await open(tester, size: size, scenario: PistiScenario.finish);
        expect(tester.takeException(), isNull);
        final cardRect = tester.getRect(seven);
        expect(cardRect.left, greaterThanOrEqualTo(24));
        expect(cardRect.right, lessThanOrEqualTo(size.width - 24));
        expect(cardRect.bottom, lessThanOrEqualTo(size.height - 12));
        await tester.tap(seven);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(seven);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('pisti-result')), findsOneWidget);
        final replay = tester.getRect(
          find.byKey(const ValueKey('pisti-replay')),
        );
        expect(replay.bottom, lessThanOrEqualTo(size.height - 12));
        expect(replay.right, lessThanOrEqualTo(size.width - 24));
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('pisti-replay')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('pisti-result')), findsNothing);
        expect(find.text('BİR KART SEÇ'), findsOneWidget);
      },
    );
  }
  testWidgets('second tap plays once and shows the pişti moment', (
    tester,
  ) async {
    await open(tester);
    final position = tester.getCenter(seven);
    await tester.tap(seven);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(seven);
    await tester.tapAt(position);
    await tester.tapAt(position);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 380));
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text('PİŞTİ'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('10'), findsOneWidget);
    expect(seven, findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('dragging to center plays; dragging away returns selected card', (
    tester,
  ) async {
    await open(tester, scenario: PistiScenario.capture);
    final origin = tester.getCenter(seven);
    await tester.dragFrom(origin, const Offset(5, -20));
    await tester.pumpAndSettle();
    expect(seven, findsOneWidget);
    final center = tester.getCenter(
      find.byKey(const ValueKey('pisti-drop-zone')),
    );
    await tester.timedDrag(
      seven,
      center - tester.getCenter(seven),
      const Duration(milliseconds: 350),
    );
    await tester.pumpAndSettle();
    expect(seven, findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('cancelled drag and a second pointer cannot play a card', (
    tester,
  ) async {
    await open(tester);
    final first = await tester.startGesture(
      tester.getCenter(seven),
      pointer: 1,
    );
    await first.moveBy(const Offset(0, -30));
    await tester.pump();
    await first.moveTo(
      tester.getCenter(find.byKey(const ValueKey('pisti-drop-zone'))),
    );
    await tester.pump();
    final second = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('pisti-card-22'))),
      pointer: 2,
    );
    await second.moveBy(const Offset(0, -30));
    await second.up();
    await first.cancel();
    await tester.pumpAndSettle();
    expect(seven, findsOneWidget);
    expect(find.text('10'), findsNothing);
    await tester.tap(seven);
    await tester.pumpAndSettle();
    expect(seven, findsNothing);
    expect(find.text('10'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'covering the route pauses a flight until the route is visible again',
    (tester) async {
      await open(tester);
      await tester.tap(seven);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(seven);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final navigator = Navigator.of(
        tester.element(find.byType(PistiDemoScreen)),
      );
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Covered')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('10', skipOffstage: false), findsNothing);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text('10'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'background pauses a flight; resume finishes it, exit cancels safely',
    (tester) async {
      await open(tester);
      await tester.tap(seven);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(seven);
      await tester.pump(const Duration(milliseconds: 100));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('PİŞTİ'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('10'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pisti-scenarios')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Normal oyun'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    },
  );
}
