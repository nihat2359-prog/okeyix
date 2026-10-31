import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/services/pisti_service.dart';
import 'package:okeyix/screens/pisti_table_screen.dart';
import 'pisti_online_test.dart' as fixtures;

class BotTurnService extends fixtures.FakePistiService {
  int heartbeats = 0;
  BotTurnService() {
    data['game']['turn'] = 1;
    data['room']['seats'][1]['bot'] = true;
    data['now'] = '2026-10-31T00:00:00Z';
    data['room']['deadline'] = '2026-10-31T00:00:00.700Z';
  }
  @override
  Future<Map<String, dynamic>> command(
    String action,
    Map<String, dynamic> args, {
    String? request,
  }) async {
    if (action == 'heartbeat' && ++heartbeats == 2) {
      data = fixtures.fixture();
      data['room']['version'] = 2;
    }
    return super.command(action, args, request: request);
  }
}

class ClockController extends fixtures.StaticController {
  ClockController(super.service);
  void pulse() => notifyListeners();
}

void main() {
  testWidgets(
    'bot is reconciled at its deadline without Realtime or the 15 second poll',
    (tester) async {
      final service = BotTurnService();
      final controller = PistiController('local-room', service)..active = true;
      await controller.refresh();
      expect(service.heartbeats, 1);
      await tester.pump(const Duration(milliseconds: 950));
      await tester.pump();
      expect(service.heartbeats, 2);
      expect(controller.snapshot!['game']['turn'], 0);
      controller.dispose();
    },
  );
  testWidgets('background cancels pending bot reconciliation', (tester) async {
    final service = BotTurnService();
    final controller = PistiController('local-room', service)..active = true;
    await controller.refresh();
    controller.setActive(false);
    await tester.pump(const Duration(seconds: 3));
    expect(service.heartbeats, 1);
    controller.dispose();
  });
  testWidgets(
    'countdown stays with the player and does not reset on a busy notification',
    (tester) async {
      tester.view.physicalSize = const Size(568, 280);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = fixtures.FakePistiService();
      final controller = ClockController(service);
      await tester.pumpWidget(
        MaterialApp(
          home: PistiTableScreen(roomId: 'local-room', controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      int seconds() => int.parse(
        (tester
                .widget<Text>(
                  find.textContaining(RegExp(r'SIRA SENDE · \d+ sn')),
                )
                .data!)
            .split(' · ')
            .last
            .split(' ')
            .first,
      );
      final initial = seconds();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1200)),
      );
      await tester.pump(const Duration(seconds: 2));
      final elapsed = seconds();
      expect(elapsed, lessThan(initial));
      controller.busy = true;
      controller.pulse();
      await tester.pump();
      expect(seconds(), lessThanOrEqualTo(elapsed));
      expect(
        tester.getRect(find.textContaining('SIRA SENDE ·')).left,
        lessThan(170),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
