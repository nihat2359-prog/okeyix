import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:okeyix/services/pisti_service.dart';
import 'package:okeyix/screens/pisti_table_screen.dart';
import 'package:okeyix/dev/pisti/pisti_cards.dart';
import 'pisti_online_test.dart' as fixtures;

class PreparationService extends fixtures.FakePistiService {
  PreparationService() {
    data = fixtures.fixture(status: 'waiting');
    data['room'] = Map<String, dynamic>.from(data['room'] as Map);
    data['room']['owner_id'] = null;
    data['room']['seats'] = [
      {'id': 'me', 'name': 'Deniz', 'bot': false, 'ready': false},
    ];
  }
  String? rejectAction;
  String rejection = 'NOT_A_MEMBER';
  bool left = false;
  @override
  Future<List<Map<String, dynamic>>> invitablePlayers(String roomId) async => [
    {'id': 'bot', 'username': 'Ada', 'is_bot': true, 'is_online': true},
    {'id': 'friend', 'username': 'Ece', 'is_bot': false, 'is_online': true},
  ];
  @override
  Future<Map<String, dynamic>> command(
    String action,
    Map<String, dynamic> args, {
    String? request,
  }) async {
    calls.add((action: action, args: Map.of(args), request: request));
    if (action == rejectAction || (action == 'snapshot' && left)) {
      throw FunctionException(status: 409, details: {'error': rejection});
    }
    if (action == 'bot') {
      (data['room']['seats'] as List).add({
        'id': 'bot',
        'name': 'Ada',
        'bot': true,
        'ready': true,
      });
    }
    if (action == 'ready') {
      data['room']['seats'][0]['ready'] = true;
    }
    if (['bot', 'ready'].contains(action) &&
        (data['room']['seats'] as List).length == 2) {
      data = fixtures.fixture(status: 'playing');
    }
    if (action == 'leave') left = true;
    return action == 'snapshot' ? data : {'room_id': 'local-room'};
  }
}

class PreparationController extends PistiController {
  PreparationController(PreparationService service)
    : super('local-room', service) {
    snapshot = service.data;
  }
  @override
  void start() {
    active = true;
  }
}

void main() {
  test(
    'successful leave is final without a spectator refresh or heartbeat',
    () async {
      final service = PreparationService();
      final c = PreparationController(service)..active = true;
      await c.send('leave');
      expect(c.membershipEnded, isTrue);
      expect(c.error, isNull);
      expect(service.calls.map((e) => e.action), ['leave']);
      await c.refresh();
      expect(service.calls, hasLength(1));
      c.dispose();
    },
  );

  test(
    'definitive lost membership stops commands and pending retries',
    () async {
      final service = PreparationService()..rejectAction = 'bot';
      final c = PreparationController(service)..active = true;
      await c.send('bot');
      expect(c.membershipEnded, isTrue);
      await c.retry();
      await c.send('leave');
      expect(service.calls.map((e) => e.action), ['bot']);
      c.dispose();
    },
  );

  test(
    'lost private-room snapshot access ends a previously seated session',
    () async {
      final service = PreparationService()
        ..rejectAction = 'snapshot'
        ..rejection = 'VIEW_DENIED';
      final c = PreparationController(service)..active = true;
      await c.refresh();
      expect(c.membershipEnded, isTrue);
      c.dispose();
    },
  );

  Future<void> open(WidgetTester tester, PreparationController c) async {
    tester.view.physicalSize = const Size(568, 280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      PistiTableScreen(roomId: 'local-room', controller: c),
                ),
              ),
              child: const Text('Pişti lobisi'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pişti lobisi'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'table waits and selected bot is invited through the player list',
    (tester) async {
      final service = PreparationService();
      final c = PreparationController(service);
      await open(tester, c);
      expect(find.text('Hazırım'), findsNothing);
      expect(find.text('Hazır değilim'), findsNothing);
      expect(find.text('Botla oyna'), findsNothing);
      expect(c.snapshot!['room']['status'], 'waiting');
      await tester.tap(find.text('Oyuncu davet et'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('invite-player-bot')));
      await tester.pumpAndSettle();
      expect(
        service.calls
            .where((e) => ['bot', 'ready'].contains(e.action))
            .map((e) => e.action),
        ['ready', 'bot'],
      );
      expect(
        service.calls.firstWhere((e) => e.action == 'bot').args['bot_id'],
        'bot',
      );
      expect(c.snapshot!['room']['status'], 'playing');
      expect(find.byType(PistiCardView), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('an in-flight command is not mistaken for a successful leave', (
    tester,
  ) async {
    final service = PreparationService();
    final c = PreparationController(service)..busy = true;
    await open(tester, c);
    await tester.tap(find.byTooltip('Lobiye dön'));
    await tester.pumpAndSettle();
    expect(find.byType(PistiTableScreen), findsOneWidget);
    expect(service.calls, isEmpty);
    c.busy = false;
    await tester.tap(find.byTooltip('Lobiye dön'));
    await tester.pumpAndSettle();
    expect(find.byType(PistiTableScreen), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final alreadyRemoved in [false, true]) {
    testWidgets(
      'Lobiye dön pops after leave; already removed: $alreadyRemoved',
      (tester) async {
        final service = PreparationService();
        if (alreadyRemoved) service.rejectAction = 'leave';
        final c = PreparationController(service);
        await open(tester, c);
        await tester.tap(find.byTooltip('Lobiye dön'));
        await tester.pumpAndSettle();
        expect(find.byType(PistiTableScreen), findsNothing);
        expect(find.text('Pişti lobisi'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('expired membership has a direct exit with no extra RPC', (
    tester,
  ) async {
    final service = PreparationService();
    final c = PreparationController(service)..membershipEnded = true;
    await open(tester, c);
    await tester.tap(find.text('Lobiye dön'));
    await tester.pumpAndSettle();
    expect(find.byType(PistiTableScreen), findsNothing);
    expect(service.calls, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
