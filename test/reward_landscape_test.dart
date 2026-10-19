import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/reward_dialogs.dart';

const _sizes = [
  Size(640, 360),
  Size(800, 360),
  Size(844, 390),
  Size(932, 430),
  Size(1024, 600),
];
const _insets = EdgeInsets.fromLTRB(24, 12, 24, 24);

Future<void> _open(
  WidgetTester tester,
  Widget dialog,
  Size size,
  double scale,
) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Montserrat'),
      builder: (context, child) => RepaintBoundary(
        key: const ValueKey('capture'),
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: _insets,
            viewPadding: _insets,
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        ),
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => dialog,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void _visibleActions(WidgetTester tester, Size size) {
  for (final key in ['reward-action', 'reward-close']) {
    final finder = find.byKey(ValueKey(key));
    final rect = tester.getRect(finder);
    expect(rect.left, greaterThanOrEqualTo(_insets.left));
    expect(rect.right, lessThanOrEqualTo(size.width - _insets.right));
    expect(rect.top, greaterThanOrEqualTo(_insets.top));
    expect(rect.bottom, lessThanOrEqualTo(size.height - _insets.bottom));
  }
  expect(tester.takeException(), isNull);
}

void main() {
  setUpAll(() async {
    final text = FontLoader('Montserrat')
      ..addFont(rootBundle.load('assets/fonts/Montserrat-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Montserrat-Bold.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await Future.wait([text.load(), icons.load()]);
  });
  for (final size in _sizes) {
    for (final scale in [1.0, 1.6, 2.0]) {
      testWidgets('daily $size text $scale all states keep actions visible', (
        tester,
      ) async {
        var response = Completer<bool>();
        await _open(
          tester,
          DailyBonusDialog(amount: 2500, onClaim: () => response.future),
          size,
          scale,
        );
        _visibleActions(tester, size);
        await tester.tap(find.byKey(const ValueKey('reward-action')));
        await tester.pump();
        _visibleActions(tester, size);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(
          tester
              .widget<ElevatedButton>(
                find.byKey(const ValueKey('reward-action')),
              )
              .onPressed,
          isNull,
        );
        response.completeError(StateError('offline'));
        await tester.pumpAndSettle();
        _visibleActions(tester, size);
        expect(
          find.text('Bonus alınamadı. Lütfen tekrar deneyin.'),
          findsOneWidget,
        );
        response = Completer<bool>();
        await tester.tap(find.byKey(const ValueKey('reward-action')));
        response.complete(false);
        await tester.pumpAndSettle();
        _visibleActions(tester, size);
        expect(find.text('Bugünkü ödülün alındı'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('reward-close')));
        await tester.pumpAndSettle();
        expect(find.byType(DailyBonusDialog), findsNothing);
        // A fresh dialog verifies a confirmed win, not just the duplicate path.
        await tester.pumpWidget(const SizedBox.shrink());
        await _open(
          tester,
          DailyBonusDialog(amount: 2500, onClaim: () async => true),
          size,
          scale,
        );
        await tester.tap(find.byKey(const ValueKey('reward-action')));
        await tester.pumpAndSettle();
        _visibleActions(tester, size);
        expect(find.text('Harika! Kazandın.'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('reward-action')));
        await tester.pumpAndSettle();
        expect(find.byType(DailyBonusDialog), findsNothing);
      });
      testWidgets(
        'welcome $size text $scale actions visible without scrolling',
        (tester) async {
          await _open(
            tester,
            const WelcomeRewardDialog(amount: 10000),
            size,
            scale,
          );
          _visibleActions(tester, size);
          await tester.tap(find.byKey(const ValueKey('reward-action')));
          await tester.pumpAndSettle();
          expect(find.byType(WelcomeRewardDialog), findsNothing);
        },
      );
    }
  }
  for (final welcome in [false, true]) {
    testWidgets('landscape golden ${welcome ? 'welcome' : 'daily'}', (
      tester,
    ) async {
      await _open(
        tester,
        welcome
            ? const WelcomeRewardDialog(amount: 10000)
            : DailyBonusDialog(amount: 2500, onClaim: () async => true),
        const Size(800, 360),
        1,
      );
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile(
          'goldens/${welcome ? 'welcome' : 'daily'}_landscape.png',
        ),
      );
    });
  }
}
