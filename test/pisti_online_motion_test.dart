import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/dev/pisti/pisti_screen.dart';
import 'package:okeyix/services/pisti_service.dart';
import 'pisti_online_test.dart' as fixtures;

class DelayedMoveController extends PistiController {
  DelayedMoveController() : super('local-room', fixtures.FakePistiService()) {
    snapshot = fixtures.fixture();
  }
  final confirmation = Completer<void>();
  int plays = 0;
  @override
  Future<void> send(
    String action, [
    Map<String, dynamic> args = const {},
    String? request,
  ]) async {
    if (action != 'play') return;
    plays++;
    busy = true;
    notifyListeners();
    await confirmation.future;
    final id = args['card'] as int;
    snapshot = fixtures.fixture();
    snapshot!['room']['version'] = 2;
    snapshot!['game']['hand'] = [1, 2, 3];
    snapshot!['game']['hand_counts'] = [3, 4];
    snapshot!['game']['top'] = id;
    snapshot!['game']['pile_count'] = 5;
    snapshot!['game']['turn'] = 1;
    snapshot!['game']['seq'] = 1;
    snapshot!['game']['event'] = {
      'seq': 1,
      'card': id,
      'seat': 0,
      'captured': 0,
      'bonus': 0,
    };
    busy = false;
    notifyListeners();
  }
}

void main() {
  for (final drag in [false, true]) {
    testWidgets(
      'online card stays at centre while awaiting confirmation; drag=$drag',
      (tester) async {
        tester.view.physicalSize = const Size(844, 390);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = DelayedMoveController();
        await tester.pumpWidget(MaterialApp(home: PistiDemoScreen(online: c)));
        await tester.pumpAndSettle();
        final hand = find.byKey(const ValueKey('pisti-card-0'));
        final handY = tester.getCenter(hand).dy;
        if (drag) {
          final target = tester.getCenter(
            find.byKey(const ValueKey('pisti-drop-zone')),
          );
          await tester.timedDrag(
            hand,
            target - tester.getCenter(hand),
            const Duration(milliseconds: 350),
          );
        } else {
          await tester.tap(hand);
          await tester.pump(const Duration(milliseconds: 200));
          await tester.tap(hand);
        }
        await tester.pumpAndSettle();
        final flight = find.byKey(const ValueKey('pisti-flight-0'));
        expect(flight, findsOneWidget);
        final centre = tester.getCenter(flight);
        expect(centre.dy, lessThan(handY - 25));
        expect(hand, findsNothing);
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.getCenter(flight), centre);
        c.confirmation.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        expect(
          flight,
          findsNothing,
          reason: 'server confirmation must not restart a hand-to-table flight',
        );
        expect(hand, findsNothing);
        expect(c.plays, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
      },
    );
  }
}
