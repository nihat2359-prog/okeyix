import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:okeyix/services/pisti_service.dart';
import 'package:okeyix/screens/pisti_lobby_screen.dart';
import 'package:okeyix/screens/pisti_table_screen.dart';
import 'package:okeyix/dev/pisti/pisti_cards.dart';

class FakePistiService extends PistiService {
  FakePistiService()
    : super(
        client: SupabaseClient(
          'https://pisti.invalid',
          'local-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  final calls =
      <({String action, Map<String, dynamic> args, String? request})>[];
  bool fail = false;
  @override
  Future<List<Map<String, dynamic>>> recentMessages(String roomId) async => [];
  @override
  RealtimeChannel? watchMessages(
    String roomId,
    void Function(Map<String, dynamic>) receive,
    VoidCallback reconnect,
  ) => null;
  Map<String, dynamic> data = fixture();
  @override
  Future<Map<String, dynamic>> command(
    String action,
    Map<String, dynamic> args, {
    String? request,
  }) async {
    calls.add((action: action, args: Map.of(args), request: request));
    if (action == 'snapshot') return data;
    if (action == 'heartbeat') return {};
    if (fail) throw TimeoutException('transport outcome unknown');
    return {'room_id': 'local-room'};
  }

  @override
  Future<Map<String, dynamic>> lobby() async => {
    'settings': {
      'enabled': true,
      'target': 101,
      'turn_seconds': 20,
      'stakes': [1000, 5000, 10000],
    },
    'rooms': <Map<String, dynamic>>[],
    'invites': <Map<String, dynamic>>[],
  };
}

Map<String, dynamic> fixture({String status = 'playing', int viewer = 0}) => {
  'now': DateTime.now().toUtc().toIso8601String(),
  'viewer': viewer,
  'room': {
    'id': 'local-room',
    'owner_id': 'me',
    'version': 1,
    'match_id': 'match',
    'status': status,
    'entry_coin': 1000,
    'deadline': DateTime.now()
        .add(const Duration(seconds: 20))
        .toUtc()
        .toIso8601String(),
    'seats': [
      {'id': 'me', 'name': 'Deniz', 'bot': false, 'ready': true},
      {'id': 'them', 'name': 'Rakip', 'bot': false, 'ready': true},
    ],
  },
  'settings': {'target': 101, 'turn_seconds': 20},
  'rematch': <String>[],
  'game': status == 'waiting'
      ? null
      : {
          'rules': 'okeyix-pisti-101-v1',
          'target': 101,
          'round': 1,
          'deal': 1,
          'turn': 0,
          'total': [status == 'finished' ? 101 : 0, 0],
          'rounds': [],
          'pistis': [0, 0],
          'status': status,
          'winner': status == 'finished' ? 0 : null,
          'reason': status == 'finished' ? 'normal' : null,
          'seq': 0,
          'deck_count': 40,
          'pile_count': 4,
          'top': 6,
          'hand': viewer >= 0 ? [0, 1, 2, 3] : <int>[],
          'hand_counts': [4, 4],
          'won_counts': [0, 0],
          'event': null,
        },
};

class StaticController extends PistiController {
  StaticController(
    FakePistiService service, {
    String status = 'playing',
    int viewer = 0,
  }) : super('local-room', service) {
    snapshot = fixture(status: status, viewer: viewer);
  }
  @override
  void start() {
    active = true;
  }

  @override
  void setActive(bool value) {
    active = value;
  }

  @override
  Future<void> refresh() async {}
}

void main() {
  test(
    'unknown move outcome retains request id and original arguments across retry',
    () async {
      final service = FakePistiService()..fail = true;
      final c = PistiController('local-room', service);
      await c.send('play', {'card': 1, 'version': 5, 'match_id': 'm'});
      expect(c.error, isNotNull);
      service.fail = false;
      await c.send('play', {'card': 2, 'version': 6, 'match_id': 'other'});
      final moves = service.calls.where((e) => e.action == 'play').toList();
      expect(moves.length, 2);
      expect(moves[0].request, moves[1].request);
      expect(moves[1].args, moves[0].args);
      c.dispose();
      await service.client.dispose();
    },
  );
  for (final size in [
    const Size(568, 280),
    const Size(640, 320),
    const Size(960, 320),
  ]) {
    testWidgets(
      'production lobby and waiting/playing/result fit landscape $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final service = FakePistiService();
        Widget host(Widget child) => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              textScaler: TextScaler.linear(1.3),
            ),
            child: child,
          ),
        );
        await tester.pumpWidget(host(PistiLobbyScreen(service: service)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester
              .getRect(find.widgetWithText(FilledButton, 'Botla Oyna'))
              .bottom,
          lessThanOrEqualTo(size.height - 8),
        );
        for (final status in ['waiting', 'playing', 'finished']) {
          final c = StaticController(service, status: status);
          await tester.pumpWidget(
            host(
              PistiTableScreen(
                key: ValueKey(status),
                roomId: 'local-room',
                controller: c,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: status);
          if (status == 'waiting') {
            expect(find.text('Hazırım'), findsNothing);
            expect(find.text('Hazır değilim'), findsNothing);
          }
          if (status == 'finished') {
            expect(
              tester.getRect(find.text('Rövanş iste')).bottom,
              lessThanOrEqualTo(size.height - 8),
            );
          }
          if (status == 'playing') {
            await tester.tap(find.byTooltip('Kurallar ve el puanları'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(
              tester.getRect(find.text('Masaya dön')).bottom,
              lessThanOrEqualTo(size.height - 8),
            );
            await tester.tap(find.text('Masaya dön'));
            await tester.pumpAndSettle();
            await tester.tap(find.byIcon(Icons.exit_to_app));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(
              tester.getRect(find.text('Oyuna dön')).bottom,
              lessThanOrEqualTo(size.height - 8),
            );
            await tester.tap(find.text('Oyuna dön'));
            await tester.pumpAndSettle();
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets('spectator sees card backs for both hands and cannot play', (
    tester,
  ) async {
    final c = StaticController(FakePistiService(), viewer: -1);
    await tester.pumpWidget(
      MaterialApp(
        home: PistiTableScreen(roomId: 'local-room', controller: c),
      ),
    );
    await tester.pumpAndSettle();
    final faces = tester
        .widgetList<PistiCardView>(find.byType(PistiCardView))
        .where((card) => card.faceUp)
        .toList();
    expect(faces.length, 1); // only the public top card
    expect(find.textContaining('SEYİRCİ'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
