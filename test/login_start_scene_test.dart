import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/screens/login_screen.dart' show OkeyixLegalBlock;
import 'package:okeyix/ui/login_start_scene.dart';

const sizes = [
  Size(640, 360),
  Size(800, 360),
  Size(844, 390),
  Size(932, 430),
  Size(1024, 600),
];
Future<void> pumpScene(
  WidgetTester tester, {
  Size size = const Size(800, 360),
  double scale = 1,
  bool reduced = false,
  String? error,
  Future<void> Function()? apple,
  Future<void> Function()? google,
  Future<void> Function()? guest,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Montserrat'),
      builder: (context, child) => RepaintBoundary(
        key: const ValueKey('login-capture'),
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            viewPadding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            textScaler: TextScaler.linear(scale),
            disableAnimations: reduced,
          ),
          child: child!,
        ),
      ),
      home: LoginStartScene(
        onApple: apple ?? () async {},
        onGoogle: google ?? () async {},
        onGuest: guest ?? () async {},
        error: error,
        legal: const OkeyixLegalBlock(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void visible(WidgetTester tester, Size size) {
  final legal = tester.getRect(find.byType(OkeyixLegalBlock));
  expect(legal.bottom, lessThanOrEqualTo(size.height - 24));
  expect(
    tester.getRect(find.byKey(const ValueKey('login-guest'))).bottom,
    lessThan(legal.top),
  );
  expect(find.text('Sıradaki el senin.'), findsOneWidget);
  expect(find.text('Oyun başlasın.'), findsNothing);
  for (final id in ['apple', 'google', 'guest']) {
    final rect = tester.getRect(find.byKey(ValueKey('login-$id')));
    expect(rect.left, greaterThanOrEqualTo(24));
    expect(rect.top, greaterThanOrEqualTo(12));
    expect(rect.right, lessThanOrEqualTo(size.width - 24));
    expect(rect.bottom, lessThanOrEqualTo(size.height - 24));
    expect(rect.height, greaterThanOrEqualTo(44));
    expect(rect.height, lessThanOrEqualTo(56));
    expect(rect.width, lessThanOrEqualTo(310));
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
  for (final size in sizes) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('landscape $size text $scale ready loading error', (
        tester,
      ) async {
        var pending = Completer<void>();
        await pumpScene(
          tester,
          size: size,
          scale: scale,
          guest: () => pending.future,
        );
        visible(tester, size);
        await tester.tap(find.byKey(const ValueKey('login-guest')));
        await tester.pump();
        visible(tester, size);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        pending.completeError(StateError('offline'));
        await tester.pumpAndSettle();
        visible(tester, size);
        expect(
          find.text('Bağlantı kurulamadı. Lütfen tekrar dene.'),
          findsOneWidget,
        );
        pending = Completer<void>();
        await tester.tap(find.byKey(const ValueKey('login-guest')));
        pending.complete();
        await tester.pumpAndSettle();
        visible(tester, size);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(tester.binding.transientCallbackCount, 0);
      });
    }
  }
  for (final provider in ['apple', 'google', 'guest']) {
    testWidgets('$provider callback, loading and duplicate protection', (
      tester,
    ) async {
      final pending = Completer<void>();
      final calls = <String>[];
      Future<void> action(String id) {
        calls.add(id);
        return pending.future;
      }

      await pumpScene(
        tester,
        apple: () => action('apple'),
        google: () => action('google'),
        guest: () => action('guest'),
      );
      await tester.tap(find.byKey(ValueKey('login-$provider')));
      await tester.tap(find.byKey(ValueKey('login-$provider')));
      await tester.pump();
      for (final id in ['apple', 'google', 'guest']) {
        expect(
          tester
              .widget<TextButton>(find.byKey(ValueKey('login-$id')))
              .onPressed,
          isNull,
        );
      }
      expect(calls, [provider]);
      pending.complete();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextButton>(find.byKey(ValueKey('login-$provider')))
            .onPressed,
        isNotNull,
      );
    });
  }
  testWidgets('reduced motion renders immediately and has no idle ticker', (
    tester,
  ) async {
    await pumpScene(
      tester,
      reduced: true,
      error: 'Google ile giriş başarısız.',
    );
    expect(find.text('Google ile giriş başarısız.'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    visible(tester, const Size(800, 360));
  });
  testWidgets('pending login can finish after disposal', (tester) async {
    final pending = Completer<void>();
    await pumpScene(tester, apple: () => pending.future);
    await tester.tap(find.byKey(const ValueKey('login-apple')));
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  for (final size in [const Size(640, 360), const Size(932, 430)]) {
    testWidgets('opening scene golden $size', (tester) async {
      await pumpScene(tester, size: size);
      await expectLater(
        find.byKey(const ValueKey('login-capture')),
        matchesGoldenFile(
          'goldens/login_${size.width.toInt()}x${size.height.toInt()}.png',
        ),
      );
    });
  }
}
