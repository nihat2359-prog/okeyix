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
  testWidgets(
    'server bot match is ready immediately without a wait or opt-in phase',
    (tester) async {
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
    },
  );
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
    expect(backend.calls, ['start']);
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
    'old server waiting result never exposes a ten-second waiting flow',
    (tester) async {
      final backend = FakeBackend()
        ..responses.add(
          Future.value({'state': 'waiting', 'table_id': 'legacy'}),
        );
      final flow = QuickPlayController(backend);
      await flow.start();
      expect(flow.phase, QuickPlayPhase.error);
      expect(flow.message, contains('sunucu güncellemesi'));
      await tester.pump(const Duration(seconds: 20));
      expect(backend.calls, ['start']);
      backend.responses.add(Future.value({'state': 'cancelled'}));
      await flow.cancel();
      expect(flow.phase, QuickPlayPhase.cancelled);
      flow.dispose();
    },
  );
  for (final size in [const Size(568, 320), const Size(844, 390)]) {
    testWidgets(
      'instant search panel fits landscape $size without waiting choices',
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
}
