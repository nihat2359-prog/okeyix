import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:okeyix/services/update_service.dart';
import 'package:okeyix/ui/update_notice_dialog.dart';

AppUpdateInfo available() => AppUpdateInfo(
  updateAvailability: UpdateAvailability.updateAvailable,
  immediateUpdateAllowed: false,
  flexibleUpdateAllowed: false,
  immediateAllowedPreconditions: null,
  flexibleAllowedPreconditions: null,
  availableVersionCode: 200,
  installStatus: InstallStatus.unknown,
  packageName: 'com.okeyix.app',
  clientVersionStalenessDays: 0,
  updatePriority: 0,
);

Future<BuildContext> screen(WidgetTester tester) async {
  late BuildContext context;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (c) {
          context = c;
          return const Scaffold(body: Text('Giriş ekranı'));
        },
      ),
    ),
  );
  return context;
}

void main() {
  test('compares numeric store versions', () {
    expect(UpdateService.compareVersions('1.9.0', '1.10.0'), lessThan(0));
    expect(UpdateService.compareVersions('2.0', '2.0.0'), 0);
    expect(UpdateService.compareVersions('2.1.0+25', '2.0.9'), greaterThan(0));
  });
  testWidgets(
    'Android offers update even when in-app installation is unavailable',
    (tester) async {
      final opened = <Uri>[];
      final service = UpdateService.forTesting(
        platform: TargetPlatform.android,
        androidCheck: () async => available(),
        openStore: (uri) async => opened.add(uri),
      );
      final context = await screen(tester);
      final check = service.checkForUpdatesOnStartup(context);
      await tester.pumpAndSettle();
      expect(find.byType(UpdateNoticeDialog), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('update-now')));
      await tester.pumpAndSettle();
      await check;
      expect(opened.single.host, 'play.google.com');
      expect(opened.single.queryParameters['id'], 'com.okeyix.app');
    },
  );
  testWidgets('failed first check can retry without restarting', (
    tester,
  ) async {
    var attempts = 0;
    var now = DateTime(2026, 10, 23);
    final service = UpdateService.forTesting(
      platform: TargetPlatform.android,
      now: () => now,
      androidCheck: () async {
        if (++attempts == 1) throw StateError('offline');
        return available();
      },
    );
    final context = await screen(tester);
    await service.checkForUpdatesOnStartup(context);
    await service.checkForUpdatesOnStartup(context);
    expect(attempts, 1);
    now = now.add(const Duration(minutes: 2));
    final check = service.checkForUpdatesOnStartup(context);
    await tester.pumpAndSettle();
    expect(find.byType(UpdateNoticeDialog), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('update-later')));
    await tester.pumpAndSettle();
    await check;
    expect(attempts, 2);
  });
  testWidgets(
    'iOS opens the returned store URL and does not repeat the same notice',
    (tester) async {
      var now = DateTime(2026, 10, 23);
      final opened = <Uri>[];
      final service = UpdateService.forTesting(
        platform: TargetPlatform.iOS,
        now: () => now,
        iosLookup: () async => (
          current: '1.9.0',
          latest: '1.10.0',
          store: Uri.parse('https://apps.apple.com/tr/app/id123'),
        ),
        openStore: (uri) async => opened.add(uri),
      );
      final context = await screen(tester);
      final check = service.checkForUpdatesOnStartup(context);
      await tester.pumpAndSettle();
      expect(find.text('Okeyix 1.10.0'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('update-now')));
      await tester.pumpAndSettle();
      await check;
      expect(opened.single.path, '/tr/app/id123');
      now = now.add(const Duration(hours: 5));
      await service.checkForUpdatesOnStartup(context);
      await tester.pumpAndSettle();
      expect(find.byType(UpdateNoticeDialog), findsNothing);
    },
  );
  testWidgets('current iOS version does not show an update', (tester) async {
    final service = UpdateService.forTesting(
      platform: TargetPlatform.iOS,
      iosLookup: () async => (
        current: '2.0',
        latest: '1.9',
        store: Uri.parse('https://apps.apple.com/tr/app/id123'),
      ),
    );
    await service.checkForUpdatesOnStartup(await screen(tester));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateNoticeDialog), findsNothing);
  });
  testWidgets('startup host checks from the login navigator', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    final service = UpdateService.forTesting(
      platform: TargetPlatform.android,
      androidCheck: () async => available(),
    );
    await tester.pumpWidget(
      UpdateCheckHost(
        navigatorKey: navigator,
        service: service,
        child: MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('Giriş')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(UpdateNoticeDialog), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('update-later')));
    await tester.pumpAndSettle();
  });
  testWidgets('resume retries a failed startup check', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    var now = DateTime(2026, 10, 23);
    var attempts = 0;
    final service = UpdateService.forTesting(
      platform: TargetPlatform.android,
      now: () => now,
      androidCheck: () async {
        if (++attempts == 1) throw StateError('offline');
        return available();
      },
    );
    await tester.pumpWidget(
      UpdateCheckHost(
        navigatorKey: navigator,
        service: service,
        child: MaterialApp(navigatorKey: navigator, home: const Scaffold()),
      ),
    );
    await tester.pumpAndSettle();
    expect(attempts, 1);
    now = now.add(const Duration(minutes: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byType(UpdateNoticeDialog), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('update-later')));
    await tester.pumpAndSettle();
  });
  for (final size in [
    const Size(568, 320),
    const Size(640, 360),
    const Size(932, 430),
  ]) {
    testWidgets('update dialog fits landscape $size with large text', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: size, textScaler: TextScaler.linear(2)),
            child: const Scaffold(body: UpdateNoticeDialog(version: '1.10.0')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final key in ['update-now', 'update-later']) {
        expect(find.byKey(ValueKey(key)).hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
