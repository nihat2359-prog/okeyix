import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/services/quick_play_service.dart';
import 'package:okeyix/ui/lobby/quick_play_panel.dart';

class FakeBackend implements QuickPlayBackend {
  final calls = <String>[];
  final responses = <Future<Map<String, dynamic>>>[];
  @override
  Future<Map<String, dynamic>> command(String action) {
    calls.add(action);
    return responses.isEmpty ? Future.value(ready) : responses.removeAt(0);
  }

  @override
  Future<void> close() async {}
}

const ready = <String, dynamic>{
  'state': 'ready',
  'table_id': 'table-1',
  'is_creator': false,
  'bot': false,
};
void main() {
  testWidgets('linked account header has no guest separator or unused tap area', (tester) async {
    var plays = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(
      child: SizedBox(width: 360, child: LobbyQuickPlayBar(onPlay: () => plays++)),
    ))));
    await tester.pump();
    expect(find.byType(VerticalDivider), findsNothing);
    final button = find.byKey(const ValueKey('quick-play'));
    final bounds = tester.getRect(button);
    expect(bounds.width, 344);
    final alignment = tester.widget<Align>(find.descendant(of: button, matching: find.byType(Align)).first);
    expect(alignment.alignment, Alignment.center);
    await tester.tapAt(Offset(bounds.right - 4, bounds.center.dy));
    expect(plays, 1);
  });
  test(
    'human-only league rejection explains the available human-table options',
    () async {
      final backend = FakeBackend()
        ..responses.add(Future.error(StateError('HUMAN_ONLY_LEAGUE')));
      final flow = QuickPlayController(backend);
      await flow.start();
      expect(flow.phase, QuickPlayPhase.error);
      expect(flow.message, contains('Ustalar ve Şampiyonlar'));
      expect(flow.message, contains('masa açabilirsin'));
      expect(flow.result, isNull);
      flow.dispose();
    },
  );
  testWidgets(
    'double activation performs one scan and immediately joins the human table',
    (tester) async {
      final backend = FakeBackend();
      final flow = QuickPlayController(backend);
      await Future.wait([flow.start(), flow.start()]);
      expect(backend.calls, ['start']);
      expect(flow.phase, QuickPlayPhase.ready);
      expect(flow.result!['bot'], isFalse);
      await tester.pump(const Duration(seconds: 30));
      expect(backend.calls, ['start']);
      flow.dispose();
    },
  );
  testWidgets('server deadline result enters the bot table once', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..responses.add(
        Future.value({...ready, 'bot': true, 'is_creator': true}),
      );
    final flow = QuickPlayController(backend);
    await flow.start();
    expect(flow.phase, QuickPlayPhase.ready);
    expect(flow.result!['bot'], isTrue);
    expect(backend.calls, ['start']);
    flow.dispose();
  });
  testWidgets(
    'cancel during an ambiguous pending request is reconciled with the server',
    (tester) async {
      final backend = FakeBackend();
      final pending = Completer<Map<String, dynamic>>();
      backend.responses.addAll([
        pending.future,
        Future.value({'state': 'cancelled'}),
      ]);
      final flow = QuickPlayController(backend);
      final start = flow.start();
      await flow.cancel();
      pending.completeError(TimeoutException('lost response'));
      await start;
      await tester.pump();
      expect(backend.calls, ['start', 'cancel']);
      expect(flow.phase, QuickPlayPhase.cancelled);
      flow.dispose();
    },
  );
  testWidgets('a committed match is not destroyed by a late cancellation', (
    tester,
  ) async {
    final backend = FakeBackend();
    final pending = Completer<Map<String, dynamic>>();
    backend.responses.add(pending.future);
    final flow = QuickPlayController(backend);
    final start = flow.start();
    await flow.cancel();
    pending.complete(ready);
    await start;
    expect(flow.phase, QuickPlayPhase.ready);
    expect(backend.calls, ['start', 'cancel']);
    flow.dispose();
  });
  testWidgets(
    'lost reply retries the same operation; no available bot is an explicit error',
    (tester) async {
      final backend = FakeBackend();
      backend.responses.add(
        Future.error(StateError('QUICK_PLAY_NO_BOT_AVAILABLE')),
      );
      final flow = QuickPlayController(backend);
      await flow.start();
      expect(flow.phase, QuickPlayPhase.error);
      expect(flow.message, contains('uygun açık masa veya bot yok'));
      await flow.retry();
      expect(backend.calls, ['start', 'start']);
      expect(flow.phase, QuickPlayPhase.ready);
      flow.dispose();
    },
  );
  testWidgets(
    'waiting polls the same server request and stops after matching',
    (tester) async {
      final backend = FakeBackend()
        ..responses.add(
          Future.value({'state': 'waiting', 'remaining_ms': 10000}),
        );
      final flow = QuickPlayController(backend);
      await flow.start();
      expect(flow.phase, QuickPlayPhase.finding);
      await tester.pump(const Duration(seconds: 1));
      expect(backend.calls, ['start', 'refresh']);
      expect(flow.phase, QuickPlayPhase.ready);
      await tester.pump(const Duration(seconds: 20));
      expect(backend.calls, ['start', 'refresh']);
      flow.dispose();
    },
  );
  testWidgets('cancellation stops waiting heartbeats', (tester) async {
    final backend = FakeBackend()
      ..responses.addAll([
        Future.value({'state': 'waiting', 'remaining_ms': 10000}),
        Future.value({'state': 'cancelled'}),
      ]);
    final flow = QuickPlayController(backend);
    await flow.start();
    await flow.cancel();
    await tester.pump(const Duration(seconds: 12));
    expect(backend.calls, ['start', 'cancel']);
    expect(flow.phase, QuickPlayPhase.cancelled);
    flow.dispose();
  });
  testWidgets('background cancels waiting and a committed race resumes once', (
    tester,
  ) async {
    final backend = FakeBackend();
    final pending = Completer<Map<String, dynamic>>();
    backend.responses.addAll([
      Future.value({'state': 'waiting', 'remaining_ms': 10000}),
      pending.future,
    ]);
    final flow = QuickPlayController(backend);
    var navigations = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final result = await showDialog<Map<String, dynamic>>(
                context: context,
                builder: (_) => QuickPlayWaitDialog(
                  controller: flow,
                  leagueName: 'Tüm ligler',
                ),
              );
              if (result != null) navigations++;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Gerçek rakip aranıyor…'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(backend.calls, ['start', 'cancel']);
    pending.complete(ready);
    await tester.pump();
    expect(navigations, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(navigations, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    flow.dispose();
  });
  testWidgets(
    'deadline human-only rejection is shown without another bot request',
    (tester) async {
      final backend = FakeBackend()
        ..responses.addAll([
          Future.value({'state': 'waiting', 'remaining_ms': 100}),
          Future.value({'state': 'error', 'code': 'HUMAN_ONLY_LEAGUE'}),
        ]);
      final flow = QuickPlayController(backend);
      await flow.start();
      await tester.pump(const Duration(milliseconds: 100));
      expect(flow.phase, QuickPlayPhase.error);
      expect(flow.message, contains('Ustalar ve Şampiyonlar'));
      await tester.pump(const Duration(seconds: 20));
      expect(backend.calls, ['start', 'refresh']);
      flow.dispose();
    },
  );
  for (final size in [
    const Size(480, 270),
    const Size(568, 320),
    const Size(844, 390),
  ]) {
    testWidgets(
      'search panel fits landscape $size without manual bot choices',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var tapped = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: size.width * .48,
                height: size.height - 100,
                child: QuickPlayPanel(
                  leagueName: 'Tüm ligler',
                  onPlay: () => tapped++,
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('quick-play')));
        expect(tapped, 1);
        expect(tester.takeException(), isNull);
        final backend = FakeBackend();
        final pending = Completer<Map<String, dynamic>>();
        backend.responses.add(pending.future);
        final flow = QuickPlayController(backend);
        await tester.pumpWidget(
          MaterialApp(
            home: QuickPlayWaitDialog(
              controller: flow,
              leagueName: 'Tüm ligler',
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Botla Başla'), findsNothing);
        expect(find.text('Rakip Bekle'), findsNothing);
        expect(tester.takeException(), isNull);
        pending.completeError(StateError('QUICK_PLAY_NO_BOT_AVAILABLE'));
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
        flow.dispose();
      },
    );
  }
  testWidgets('large text in a short landscape dialog keeps cancel visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(480, 270);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = FakeBackend()
      ..responses.addAll([
        Future.value({'state': 'waiting', 'remaining_ms': 10000}),
        Future.value({'state': 'cancelled'}),
      ]);
    final flow = QuickPlayController(backend);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: QuickPlayWaitDialog(controller: flow, leagueName: 'Tüm ligler'),
      ),
    );
    await tester.pump();
    final cancel = find.widgetWithText(TextButton, 'Vazgeç');
    final rect = tester.getRect(cancel);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(270));
    expect(cancel.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    flow.dispose();
  });
}
