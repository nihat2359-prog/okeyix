import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/startup_screen.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('Montserrat')
          ..addFont(rootBundle.load('assets/fonts/Montserrat-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Montserrat-SemiBold.ttf')))
        .load();
  });
  testWidgets('startup scene preview', (tester) async {
    await tester.binding.setSurfaceSize(const Size(844, 390));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Montserrat'),
        home: const RepaintBoundary(
          key: ValueKey('startup-preview'),
          child: StartupScreen(
            progress: .7,
            message: 'Oturum kontrol ediliyor…',
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      final context = tester.element(find.byType(StartupScreen));
      await Future.wait([
        precacheImage(
          const AssetImage('assets/images/login_lounge_lit.png'),
          context,
        ),
        precacheImage(
          const AssetImage('assets/images/logo/okeyix_logo.png'),
          context,
        ),
      ]);
    });
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('startup-preview')),
      matchesGoldenFile('goldens/startup_844x390.png'),
    );
  });
  for (final size in [
    const Size(568, 320),
    const Size(844, 390),
    const Size(1024, 600),
  ]) {
    testWidgets('startup landscape $size with large text and retry', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var retries = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: const EdgeInsets.fromLTRB(59, 0, 44, 21),
              textScaler: TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: StartupScreen(
            progress: .7,
            message: 'Oturum kontrol ediliyor…',
            onRetry: () => retries++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('%70'), findsOneWidget);
      final retry = find.text('Tekrar dene');
      expect(retry.hitTestable(), findsOneWidget);
      expect(tester.getRect(retry).bottom, lessThan(size.height - 21));
      await tester.tap(retry);
      expect(retries, 1);
    });
  }

  testWidgets('startup reports real progress then mounts app once complete', (
    tester,
  ) async {
    final pending = Completer<void>();
    late StartupProgress report;
    await tester.pumpWidget(
      StartupHost(
        initialize: (_, callback) {
          report = callback;
          return pending.future;
        },
        ready: (_) => const MaterialApp(home: Text('ready')),
      ),
    );
    report(.4, 'Servisler hazırlanıyor');
    await tester.pumpAndSettle();
    expect(find.text('%40'), findsOneWidget);
    expect(find.text('ready'), findsNothing);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('ready'), findsOneWidget);
  });

  testWidgets('failed startup can retry successfully', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      StartupHost(
        initialize: (_, report) async {
          attempts++;
          if (attempts == 1) throw StateError('offline');
          report(1, 'Masan hazır!');
        },
        ready: (_) => const MaterialApp(home: Text('ready')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tekrar dene'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('ready'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('startup completion after disposal is safe', (tester) async {
    final pending = Completer<void>();
    await tester.pumpWidget(
      StartupHost(
        initialize: (_, report) => pending.future,
        ready: (_) => const SizedBox(),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    pending.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
