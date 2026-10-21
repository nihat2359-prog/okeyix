import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/models/table_gift.dart';
import 'package:okeyix/services/table_gift_service.dart';
import 'package:okeyix/ui/table_gift_layer.dart';
import 'package:okeyix/game/table_gift_flight.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GiftStore {
  final List<Map<String, dynamic>> events = [];
  final Map<String, int> balances = {'a': 100000, 'b': 100000, 'viewer': 0};
  int debits = 0;
}

class GiftFake extends TableGiftService {
  GiftFake(this.store, this.identity)
    : super(
        client: SupabaseClient(
          'https://fixture.invalid',
          'fixture',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  final GiftStore store;
  final String identity;
  bool insufficient = false, loseResponse = false;
  final List<String> requests = [];
  VoidCallback? change, reconnect;
  @override
  String get userId => identity;
  @override
  Future<void> Function() watch(
    String tableId,
    VoidCallback changed,
    VoidCallback reconnected,
  ) {
    change = changed;
    reconnect = reconnected;
    return () async {};
  }

  @override
  Future<Map<String, dynamic>> snapshot(String tableId) async {
    final latest = <String, Map<String, dynamic>>{};
    for (final e in store.events.where((e) => e['table_id'] == tableId)) {
      latest[e['recipient_id'] as String] = {
        'table_id': tableId,
        'user_id': e['recipient_id'],
        'purchase_seq': e['seq'],
        'gift_id': e['gift_id'],
      };
    }
    return {
      'table_id': tableId,
      'cursor':
          store.events
              .where((e) => e['table_id'] == tableId)
              .lastOrNull?['seq'] ??
          0,
      'balance': store.balances[identity],
      'catalog': [
        for (final id in TableGiftItem.ids)
          {
            'id': id,
            'filename': '$id.png',
            'name_tr': id == 'cay' ? 'Çay' : id,
            'name_en': id == 'cay' ? 'Tea' : id,
            'price': 1000,
          },
      ],
      'last_gifts': latest.values.toList(),
    };
  }

  @override
  Future<List<TableGiftEvent>> events(String tableId, int after) async => store
      .events
      .where((e) => e['table_id'] == tableId && (e['seq'] as int) > after)
      .map(TableGiftEvent.fromJson)
      .toList();
  @override
  Future<Map<String, dynamic>> buy(
    String tableId,
    String recipient,
    String gift,
    String request,
  ) async {
    requests.add(request);
    if (insufficient) {
      throw const PostgrestException(
        message: 'GIFT_INSUFFICIENT_COINS',
        code: 'P0001',
      );
    }
    var e = store.events
        .where((e) => e['sender_id'] == identity && e['request_id'] == request)
        .firstOrNull;
    if (e == null) {
      e = {
        'seq': store.events.length + 1,
        'request_id': request,
        'table_id': tableId,
        'sender_id': identity,
        'recipient_id': recipient,
        'gift_id': gift,
      };
      store.events.add(e);
      store.debits++;
      store.balances[identity] = store.balances[identity]! - 1000;
    }
    if (loseResponse) {
      loseResponse = false;
      throw StateError('lost response after commit');
    }
    return {'event': e, 'balance': store.balances[identity]};
  }
}

class DelayedGiftFake extends GiftFake {
  DelayedGiftFake() : super(GiftStore(), 'a');
  final completion = Completer<Map<String, dynamic>>();
  @override
  Future<Map<String, dynamic>> snapshot(String tableId) => completion.future;
}

void main() {
  test('catalog references all 14 real PNGs without duplicates', () {
    expect(TableGiftItem.ids.length, 14);
    for (final id in TableGiftItem.ids) {
      expect(File('assets/images/hediyeler/$id.png').existsSync(), isTrue);
    }
  });
  test(
    'both viewers see ordered real sender/recipient, self and replacement gifts once',
    () async {
      final store = GiftStore();
      final sa = GiftFake(store, 'a'), sb = GiftFake(store, 'b');
      final ca = TableGiftController(
            tableId: 'table',
            service: sa,
            spectator: false,
          ),
          cb = TableGiftController(
            tableId: 'table',
            service: sb,
            spectator: false,
          );
      addTearDown(ca.dispose);
      addTearDown(cb.dispose);
      final fa = <TableGiftEvent>[], fb = <TableGiftEvent>[];
      ca.onEvents = fa.addAll;
      cb.onEvents = fb.addAll;
      await ca.restore();
      await cb.restore();
      await ca.buy('b', 'cay');
      await cb.sync();
      expect(fa.single.senderId, 'a');
      expect(fb.single.recipientId, 'b');
      expect(ca.balance, 99000);
      await cb.buy('a', 'pasta');
      await ca.sync();
      expect(fa.last.senderId, 'b');
      expect(fa.last.recipientId, 'a');
      await ca.buy('a', 'kahve');
      await cb.sync();
      expect(fa.last.senderId, fa.last.recipientId);
      expect(cb.latest['a']!.giftId, 'kahve');
      await ca.sync();
      await cb.sync();
      expect(fa.length, 3);
      expect(fb.length, 3);
    },
  );
  test('a disposed old-table request cannot populate a new table', () async {
    final delayed = DelayedGiftFake();
    final old = TableGiftController(
      tableId: 'old',
      service: delayed,
      spectator: false,
    );
    final pending = old.restore();
    old.dispose();
    delayed.completion.complete({
      'table_id': 'old',
      'cursor': 1,
      'balance': 1000,
      'catalog': [],
      'last_gifts': [
        {
          'table_id': 'old',
          'user_id': 'b',
          'gift_id': 'cay',
          'purchase_seq': 1,
        },
      ],
    });
    await pending;
    expect(old.latest, isEmpty);
    final next = TableGiftController(
      tableId: 'new',
      service: GiftFake(GiftStore(), 'a'),
      spectator: false,
    );
    addTearDown(next.dispose);
    await next.restore();
    expect(next.latest, isEmpty);
  });
  testWidgets(
    'spectator late join and realtime update have no buttons or Flame flights',
    (t) async {
      final store = GiftStore();
      final source = GiftFake(store, 'a'), viewer = GiftFake(store, 'viewer');
      await source.buy('table', 'a', 'cay', 'one');
      await source.buy('table', 'b', 'pasta', 'two');
      final a = GlobalKey(), b = GlobalKey();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  top: 20,
                  left: 100,
                  child: SizedBox(key: a, width: 80, height: 60),
                ),
                Positioned(
                  top: 200,
                  left: 100,
                  child: SizedBox(key: b, width: 80, height: 60),
                ),
                Positioned.fill(
                  child: TableGiftLayer(
                    tableId: 'table',
                    service: viewer,
                    spectator: true,
                    anchors: [
                      TableGiftAnchor('a', 'A', a),
                      TableGiftAnchor('b', 'B', b),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('last-gift:a:1')), findsOneWidget);
      expect(find.byKey(const ValueKey('last-gift:b:2')), findsOneWidget);
      expect(find.byType(GameWidget<TableGiftFlightGame>), findsNothing);
      expect(find.byIcon(Icons.card_giftcard_rounded), findsNothing);
      await source.buy('table', 'b', 'kirmizi_gul', 'three');
      viewer.change!();
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('last-gift:b:2')), findsNothing);
      expect(find.byKey(const ValueKey('last-gift:b:3')), findsOneWidget);
      viewer.reconnect!();
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('last-gift:b:3')), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  test(
    'insufficient coins produce no flight; ambiguous retries reuse request and debit only once',
    () async {
      final service = GiftFake(GiftStore(), 'a');
      final c = TableGiftController(
        tableId: 'table',
        service: service,
        spectator: false,
      );
      addTearDown(c.dispose);
      final flights = <TableGiftEvent>[];
      c.onEvents = flights.addAll;
      await c.restore();
      service.insufficient = true;
      await expectLater(c.buy('b', 'cay'), throwsA(isA<PostgrestException>()));
      expect(flights, isEmpty);
      expect(service.store.debits, 0);
      service.insufficient = false;
      service.loseResponse = true;
      await expectLater(c.buy('b', 'cay'), throwsStateError);
      final pending = service.requests.last;
      await expectLater(c.buy('b', 'pasta'), throwsStateError);
      await c.buy('b', 'cay');
      expect(service.requests.last, pending);
      expect(service.store.debits, 1);
      expect(flights.length, 1);
    },
  );
  test(
    'spectator updates state without flights and reconnect does not replay history',
    () async {
      final store = GiftStore();
      final sender = GiftFake(store, 'a'), viewer = GiftFake(store, 'viewer');
      final c = TableGiftController(
        tableId: 'table',
        service: viewer,
        spectator: true,
      );
      addTearDown(c.dispose);
      var animations = 0;
      c.onEvents = (_) => animations++;
      await sender.buy('table', 'b', 'cay', 'one');
      await c.restore();
      expect(c.latest['b']!.giftId, 'cay');
      expect(animations, 0);
      await sender.buy('table', 'b', 'pasta', 'two');
      await c.sync();
      expect(c.latest['b']!.giftId, 'pasta');
      expect(animations, 0);
      await c.restore();
      expect(c.latest['b']!.giftId, 'pasta');
      expect(animations, 0);
      await expectLater(c.buy('a', 'cay'), throwsStateError);
      final next = TableGiftController(
        tableId: 'new-table',
        service: viewer,
        spectator: true,
      );
      addTearDown(next.dispose);
      await next.restore();
      expect(next.latest, isEmpty);
    },
  );
  for (final size in [const Size(480, 270), const Size(844, 390)]) {
    testWidgets('avatar targets and right gift catalog fit $size', (t) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      t.binding.platformDispatcher.localeTestValue = const Locale('tr');
      addTearDown(t.binding.platformDispatcher.clearLocaleTestValue);
      final a = GlobalKey(),
          b = GlobalKey(),
          service = GiftFake(GiftStore(), 'a');
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  top: 12,
                  left: 100,
                  child: SizedBox(key: a, width: 100, height: 48),
                ),
                Positioned(
                  top: 115,
                  left: 100,
                  child: SizedBox(key: b, width: 100, height: 48),
                ),
                Positioned.fill(
                  child: TableGiftLayer(
                    tableId: 'table',
                    service: service,
                    anchors: [
                      TableGiftAnchor('a', 'A', a),
                      TableGiftAnchor('b', 'B', b),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byIcon(Icons.card_giftcard_rounded), findsNWidgets(2));
      final giftButton = find.byTooltip('Hediye · B');
      final landingPoint = t.getCenter(giftButton);
      final cardRect = t.getRect(find.byKey(b));
      expect(cardRect.contains(t.getTopLeft(giftButton)), isTrue);
      expect(cardRect.contains(t.getBottomRight(giftButton)), isTrue);
      await t.tap(find.byTooltip('Hediye · B'));
      await t.pumpAndSettle();
      expect(find.text('Alıcı: B'), findsOneWidget);
      expect(find.text('Çay'), findsOneWidget);
      service.insufficient = true;
      await t.tap(find.text('Çay'));
      await t.pumpAndSettle();
      expect(find.text('Yetersiz coin'), findsOneWidget);
      expect(find.text('Hediyeler'), findsOneWidget);
      expect(t.takeException(), isNull);
      service.insufficient = false;
      final game = t
          .widget<GameWidget<TableGiftFlightGame>>(
            find.byType(GameWidget<TableGiftFlightGame>),
          )
          .game!;
      await t.runAsync(() async {
        await game.images.load('hediyeler/cay.png');
      });
      await t.tap(find.text('Çay'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 250));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Hediyeler'), findsNothing);
      expect(game.children.whereType<SpriteComponent>(), isNotEmpty);
      for (final sprite in game.children.whereType<SpriteComponent>()) {
        expect(sprite.angle, 0);
      }
      await t.pump(const Duration(seconds: 2));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('last-gift:b:1')), findsOneWidget);
      final delivered = find.byKey(const ValueKey('last-gift:b:1'));
      expect(t.getSize(delivered), const Size(48, 48));
      expect(t.getCenter(delivered), landingPoint);
      expect(find.byIcon(Icons.card_giftcard_rounded), findsOneWidget);
      await t.pump(const Duration(seconds: 20));
      expect(find.byKey(const ValueKey('last-gift:b:1')), findsOneWidget);
      expect(game.paused, isTrue);
      await t.tap(delivered);
      await t.pumpAndSettle();
      expect(find.text('Alıcı: B'), findsOneWidget);
      await t.tap(find.byTooltip('Kapat'));
      await t.pumpAndSettle();
      await t.pump(const Duration(milliseconds: 300));
      await t.pumpWidget(const SizedBox());
      await t.pump();
    });
  }
}
