// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:okeyix/game/rack/preview_component.dart';
import 'tile_visual_identity_test.dart' show mount, settle, payload, visual;
import 'package:okeyix/game/rack/tile_component.dart';

const viewer = '00000000-0000-4000-8000-000000009901';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <String>[];
  var hand = List.generate(15, (i) => payload('latency-$i'));
  List<Map<String, dynamic>> tops = [];
  Completer<void>? gate;
  var delayTable = false;
  var legacyDraw = false;
  var rejectDraw = false;
  var delayDiscard = false;
  var rejectDiscard = false;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final token = '${base64Url.encode(utf8.encode('{"alg":"none"}'))}.'
        '${base64Url.encode(utf8.encode(jsonEncode({'sub': viewer, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})))}.fixture';
    await Supabase.initialize(
      url: 'https://latency-fixture.invalid', anonKey: 'fixture-only', debug: false,
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(), autoRefreshToken: false, detectSessionInUri: false),
      httpClient: MockClient((request) async {
        final route = request.url.path.split('/').last;
        calls.add(route);
        Object? result;
        if (request.url.path.contains('/auth/')) {
          result = {'access_token': token, 'refresh_token': 'fixture',
            'expires_in': 3600, 'token_type': 'bearer',
            'user': {'id': viewer, 'aud': 'authenticated',
              'created_at': '2026-10-25T00:00:00Z', 'app_metadata': {}, 'user_metadata': {}}};
        } else if (route == 'game_draw') {
          if (gate != null) await gate!.future;
          result = rejectDraw ? {'ok': false} : legacyDraw ? {'ok': true} :
            {'ok': true, 'table_id': 'visual-test', 'hand': hand};
        } else if (route == 'table_players') {
          result = [{'hand': hand}];
        } else if (route == 'get_full_table_state') {
          result = null;
        } else if (route == 'game_discard_fast') {
          if (delayDiscard && gate != null) await gate!.future;
          result = {'ok': !rejectDiscard};
        } else if (route == 'table_discards') {
          result = [];
        } else if (route == 'tables') {
          if (delayTable && gate != null) await gate!.future;
          result = [{'status': 'playing', 'current_turn': 1, 'round_count': 1,
            'turn_started_at': DateTime.now().toUtc().toIso8601String()}];
        } else if (route == 'table_discard_tops') {
          final snapshot = List<Map<String, dynamic>>.from(tops);
          if (gate != null) await gate!.future;
          result = snapshot;
        } else {
          throw StateError('Unexpected extra read: $route');
        }
        return http.Response(jsonEncode(result), 200,
          headers: {'content-type': 'application/json'}, request: request);
      }),
    );
    await Supabase.instance.client.auth.signInWithPassword(
      email: 'latency@example.invalid', password: 'fixture');
  });
  setUp(() { calls.clear(); tops = []; gate = null; delayTable = false;
    legacyDraw = false; rejectDraw = false;
    delayDiscard = false; rejectDiscard = false;
    hand = List.generate(15, (i) => payload('latency-$i')); });
  tearDownAll(() => Supabase.instance.dispose());

  testWidgets('dragging a rack tile does not request a recovery hand', (tester) async {
    final game = await mount(tester);
    game.overlays.addEntry('DraggedTiles', (_, _) => const SizedBox.shrink());
    game.debugPrepareLatencyState(14);
    game.debugSyncVisualHand(hand.take(14).toList(), initial: true);
    await settle(tester, game);
    final tile = game.tileComponentMap['latency-0']!;
    final slot = tile.currentSlotIndex!;
    game.occupiedSlots.remove(slot);
    tile.currentSlotIndex = null;
    game.showTileAboveAvatars(tile);
    await game.debugValidateRack();
    expect(calls, isEmpty);
    expect(tile.currentSlotIndex, isNull);
    game.hideTileAboveAvatars(tile);
    tile.currentSlotIndex = slot;
    game.occupiedSlots[slot] = tile;
  });

  testWidgets('a repeated initial snapshot keeps the same pending deal components', (tester) async {
    final game = await mount(tester);
    game.previewBox = PreviewComponent(size: game.size.clone());
    game.debugPrepareLatencyState(15);
    // No frame between adding the deal, validating it and the second snapshot.
    game.debugApplyOwnHand(hand, hardReset: true);
    final firstDeal = Map.of(game.tileComponentMap);
    await game.debugValidateRack();
    game.debugApplyOwnHand(hand, hardReset: true);
    expect(calls, isEmpty, reason: 'Queued deal tiles must not trigger recovery');
    for (final entry in firstDeal.entries) {
      expect(game.tileComponentMap[entry.key], same(entry.value));
    }
    await settle(tester, game);
    expect(game.tileComponentMap.length, 15);
    expect(game.occupiedSlots.length, 15);
  });

  testWidgets('a snapshot during dealing does not restart the in-progress animation', (tester) async {
    final game = await mount(tester);
    game.previewBox = PreviewComponent(size: game.size.clone());
    game.debugPrepareLatencyState(15);
    game.debugApplyOwnHand(hand, hardReset: true);
    await tester.runAsync(() => game.ready());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final firstDeal = Map.of(game.tileComponentMap);
    game.debugApplyOwnHand(hand, hardReset: true);
    for (final entry in firstDeal.entries) {
      expect(game.tileComponentMap[entry.key], same(entry.value));
    }
    expect(calls, isEmpty);
    await settle(tester, game);
  });

  testWidgets('a first-discard snapshot during dealing leaves every surviving face on its slot', (tester) async {
    final game = await mount(tester);
    game.previewBox = PreviewComponent(size: game.size.clone());
    game.debugPrepareLatencyState(15);
    game.debugApplyOwnHand(hand, hardReset: true);
    await tester.runAsync(() => game.ready());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    game.debugApplyOwnHand(hand.take(14).toList());
    await settle(tester, game);
    await tester.pump(const Duration(seconds: 1));
    for (final tile in game.tileComponentMap.values) {
      expect(tile.position.distanceTo(game.slotPositions[tile.currentSlotIndex!]),
        lessThan(.01), reason: 'Visible face ${tile.id} must match its assigned rack slot');
    }
    expect(game.occupiedSlots.length, 14);
  });

  testWidgets('sorting during the deal cannot leave faces outside their new slots', (tester) async {
    final game = await mount(tester);
    game.previewBox = PreviewComponent(size: game.size.clone());
    game.debugPrepareLatencyState(15);
    game.debugApplyOwnHand(hand, hardReset: true);
    await tester.runAsync(() => game.ready());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    game.arrangeSerial();
    await settle(tester, game);
    await tester.pump(const Duration(seconds: 1));
    for (final tile in game.tileComponentMap.values) {
      expect(tile.position.distanceTo(game.slotPositions[tile.currentSlotIndex!]),
        lessThan(.01), reason: tile.id);
    }
  });

  testWidgets('a delayed committed draw unlocks without a full-table read', (tester) async {
    final game = await mount(tester);
    game.debugPrepareLatencyState(14);
    game.debugSyncVisualHand(hand.take(14).toList(), initial: true);
    await settle(tester, game);
    gate = Completer<void>();
    late Future<void> drawing;
    await tester.runAsync(() async {
      drawing = game.debugDrawCommittedHand();
      await Future<void>.delayed(Duration.zero);
    });
    expect(game.debugActionInFlight, isTrue);
    gate!.complete();
    await tester.runAsync(() => drawing);
    await settle(tester, game);
    expect(game.debugActionInFlight, isFalse);
    expect(game.tileComponentMap.length, 15);
    expect(calls, ['game_draw']);
    expect(game.canDiscardByVoice(), isTrue);
  });

  for (final source in ['closed', 'discard']) {
    testWidgets('$source draw hands off at the preview position then settles without locking input', (tester) async {
      final game = await mount(tester);
      game.debugPrepareLatencyState(14);
      game.debugSyncVisualHand(hand.take(14).toList(), initial: true);
      await settle(tester, game);
      final pending = visual('pending-$source');
      pending.position = game.slotPositions[0].clone();
      game.world.add(pending);
      await settle(tester, game);
      final free = List.generate(26, (i) => i).firstWhere((i) => !game.occupiedSlots.containsKey(i));
      game.debugShowPendingDraw(pending, preferredSlot: free);
      pending.update(.04);
      final start = pending.position.clone();
      await tester.runAsync(() => game.debugDrawCommittedHand(
        preferredSlot: free, source: source, fromSeat: source == 'discard' ? 1 : null));
      final drawn = game.tileComponentMap['latency-14']!;
      expect(drawn.position, start);
      expect(pending.hideTileVisual, isTrue);
      expect(drawn.isMovingOnRack, isTrue);
      expect(game.debugActionInFlight, isFalse);
      expect(game.tileComponentMap.length, 15);
      expect(game.occupiedSlots.values.toSet().length, 15);
      await settle(tester, game);
      expect(drawn.position.distanceTo(game.slotPositions[drawn.currentSlotIndex!]), lessThan(.001));
      expect(calls, ['game_draw']);
    });
    for (final fullRow in [false, true]) {
      testWidgets('$source draw response inserts into a blocked row without losing tiles; fullRow=$fullRow', (tester) async {
        final game = await mount(tester);
        game.debugPrepareLatencyState(14);
        game.debugSyncVisualHand(hand.take(14).toList(), initial: true);
        await settle(tester, game);
        final layout = fullRow ? [...List.generate(13, (i) => i), 13]
            : [...List.generate(12, (i) => i + 1), 13, 14];
        game.occupiedSlots.clear();
        for (var i = 0; i < 14; i++) {
          final tile = game.tileComponentMap['latency-$i']!;
          tile.stopRackMotion();
          tile.currentSlotIndex = layout[i];
          tile.position = game.slotPositions[layout[i]].clone();
          game.occupiedSlots[layout[i]] = tile;
        }
        final existing = Map.of(game.tileComponentMap);
        await tester.runAsync(() => game.debugDrawCommittedHand(
          preferredSlot: 5, source: source, fromSeat: source == 'discard' ? 1 : null));
        await settle(tester, game);
        expect(calls, ['game_draw']);
        expect(game.tileComponentMap.length, 15);
        expect(game.occupiedSlots.length, 15);
        expect(game.occupiedSlots.values.toSet().length, 15);
        final drawn = game.tileComponentMap['latency-14']!;
        expect(drawn.currentSlotIndex, fullRow ? 14 : 5);
        for (final entry in existing.entries) {
          expect(game.tileComponentMap[entry.key], same(entry.value));
        }
        for (final tile in game.tileComponentMap.values) {
          expect(game.occupiedSlots[tile.currentSlotIndex], same(tile));
        }
        expect(game.debugActionInFlight, isFalse);
        expect(game.canDiscardByVoice(), isTrue);
      });
    }
  }

  testWidgets('confirmed discard only refreshes turn and preserves remaining slots', (tester) async {
    final game = await mount(tester);
    game.debugPrepareLatencyState(15);
    game.debugSyncVisualHand(hand, initial: true);
    await settle(tester, game);
    final survivor = game.tileComponentMap['latency-1']!;
    final originalSlot = survivor.currentSlotIndex;
    late bool accepted;
    await tester.runAsync(() async {
      accepted = await game.debugDiscardCommittedTile(game.tileComponentMap['latency-0']!);
    });
    await settle(tester, game);
    expect(accepted, isTrue);
    expect(calls, ['game_discard_fast', 'tables']);
    expect(survivor.currentSlotIndex, originalSlot);
    expect(game.tileComponentMap.length, 14);
    expect(game.currentTurn, 1);
  });

  testWidgets('legacy draw response keeps authoritative hand recovery', (tester) async {
    final game = await mount(tester);
    game.debugPrepareLatencyState(14);
    game.debugSyncVisualHand(hand.take(14).toList(), initial: true);
    await settle(tester, game);
    legacyDraw = true;
    await tester.runAsync(() => game.debugDrawCommittedHand());
    await settle(tester, game);
    expect(calls, ['game_draw', 'table_players', 'get_full_table_state']);
    expect(game.tileComponentMap.length, 15);
    expect(game.debugActionInFlight, isFalse);
  });

  testWidgets('rejected draw never commits a fifteenth tile', (tester) async {
    final game = await mount(tester);
    game.debugPrepareLatencyState(14);
    game.debugSyncVisualHand(hand.take(14).toList(), initial: true);
    await settle(tester, game);
    rejectDraw = true;
    await tester.runAsync(() => game.debugDrawCommittedHand());
    expect(calls, ['game_draw', 'get_full_table_state']);
    expect(game.tileComponentMap.length, 14);
    expect(game.debugActionInFlight, isFalse);
    expect(game.canDiscardByVoice(), isFalse);
  });

  for (final slotOnly in [false, true]) {
    testWidgets('remote pickup hides the source before animation and stale reads cannot restore it; slotOnly=$slotOnly', (tester) async {
      final game = await mount(tester);
      game.debugPrepareLatencyState(14);
      final old = visual('picked-up')..isLocked = true;
      game.world.add(old);
      game.debugSeedDiscard(0, old, slotOnly: slotOnly);
      await settle(tester, game);
      final animation = game.debugAnimateDiscardPickup(0, 1, payload(old.id));
      // Before the next frame, not after the 320 ms movement.
      expect(old.hideTileVisual, isTrue);
      expect(game.debugDiscardTop(0), isNull);
      tops = [{'seat_index': 0, 'tile': payload(old.id)}];
      await tester.runAsync(() => game.debugSyncDiscardTops());
      expect(game.debugDiscardTop(0), isNull);
      await tester.pump(const Duration(milliseconds: 400));
      await animation;
      await settle(tester, game);
      expect(old.isMounted, isFalse);
      expect(game.world.children.whereType<TileComponent>()
          .where((t) => t.id == old.id), isEmpty);
    });
  }

  testWidgets('delayed older pickup preserves a newer discard', (tester) async {
    final game = await mount(tester);
    game.debugPrepareLatencyState(14);
    final newer = visual('newer-top')..isLocked = true;
    game.world.add(newer);
    game.debugSeedDiscard(0, newer);
    await settle(tester, game);
    final animation = game.debugAnimateDiscardPickup(0, 1, payload('older-picked-up'));
    expect(game.debugDiscardTop(0), same(newer));
    expect(newer.hideTileVisual, isFalse);
    await tester.pump(const Duration(milliseconds: 400));
    await animation;
    await settle(tester, game);
    expect(newer.isMounted, isTrue);
  });

  testWidgets('slow discard confirmation cannot leave the original rack face under the picked-up visual', (tester) async {
    final game = await mount(tester);
    game.debugPrepareLatencyState(15);
    game.debugSyncVisualHand(hand, initial: true);
    final previous = visual('previous-top')..isLocked = true;
    game.world.add(previous);
    game.debugSeedDiscard(0, previous);
    await settle(tester, game);
    final original = game.tileComponentMap['latency-0']!;
    original.position = previous.position.clone();
    late Future<bool> discarding;
    await tester.runAsync(() async {
      gate = Completer<void>();
      delayDiscard = true;
      discarding = game.debugDiscardCommittedTile(original);
      await Future<void>.delayed(Duration.zero);
    });
    expect(original.hideTileVisual, isTrue);
    final optimistic = game.debugDiscardTop(0)!;
    expect(optimistic.id, original.id);
    final animation = game.debugAnimateDiscardPickup(0, 1, payload(original.id));
    expect(optimistic.hideTileVisual, isTrue);
    expect(original.hideTileVisual, isTrue);
    expect(game.debugDiscardTop(0)?.id, isNot(original.id));
    await tester.pump(const Duration(milliseconds: 400));
    await animation;
    await tester.runAsync(() async {
      gate!.complete();
      expect(await discarding, isTrue);
    });
    await settle(tester, game);
    expect(original.isMounted, isFalse);
    expect(game.tileComponentMap.length, 14);
  });

  testWidgets('failed discard restores the original tile visibility', (tester) async {
    final game = await mount(tester);
    game.debugPrepareLatencyState(15);
    game.debugSyncVisualHand(hand, initial: true);
    await settle(tester, game);
    final tile = game.tileComponentMap['latency-0']!;
    rejectDiscard = true;
    late bool accepted;
    await tester.runAsync(() async {
      accepted = await game.debugDiscardCommittedTile(tile);
    });
    expect(accepted, isFalse);
    expect(tile.hideTileVisual, isFalse);
    expect(game.tileComponentMap[tile.id], same(tile));
  });

  testWidgets('empty authoritative top clears a missed take visual', (tester) async {
    final game = await mount(tester);
    game.debugPrepareLatencyState(14);
    final tile = visual('stale-top')..isLocked = true;
    game.world.add(tile);
    game.debugSeedDiscard(1, tile);
    await settle(tester, game);
    await tester.runAsync(() => game.debugSyncDiscardTops());
    await settle(tester, game);
    expect(tile.isMounted, isFalse);
  });

  testWidgets('slow periodic turn reads share one in-flight request', (tester) async {
    final game = await mount(tester);
    game.debugPrepareLatencyState(14);
    gate = Completer<void>();
    delayTable = true;
    late Future<void> first;
    late Future<void> second;
    await tester.runAsync(() async {
      first = game.debugPollTurn();
      second = game.debugPollTurn();
      await Future<void>.delayed(Duration.zero);
    });
    expect(calls, ['tables']);
    gate!.complete();
    await tester.runAsync(() => Future.wait([first, second]));
    expect(calls, ['tables']);
  });

  testWidgets('post-discard turn read does not reuse an older periodic read', (tester) async {
    final game = await mount(tester);
    game.debugPrepareLatencyState(15);
    game.debugSyncVisualHand(hand, initial: true);
    await settle(tester, game);
    delayTable = true;
    late Future<void> polling;
    late Future<bool> discarding;
    await tester.runAsync(() async {
      gate = Completer<void>();
      polling = game.debugPollTurn();
      discarding = game.debugDiscardCommittedTile(game.tileComponentMap['latency-0']!);
      await Future<void>.delayed(Duration.zero);
    });
    await tester.runAsync(() async {
      gate!.complete();
      await polling.timeout(const Duration(seconds: 3));
      expect(await discarding.timeout(const Duration(seconds: 3),
        onTimeout: () => throw StateError('Pending discard; calls=$calls')), isTrue,
        reason: calls.toString());
    });
    expect(calls.where((c) => c == 'tables').length, 2);
    expect(calls, isNot(contains('get_full_table_state')));
  });

  testWidgets('an old empty top response cannot erase a newer discard', (tester) async {
    final game = await mount(tester);
    game.debugPrepareLatencyState(14);
    final tile = visual('newer-top')..isLocked = true;
    game.world.add(tile);
    game.debugSeedDiscard(1, tile);
    await settle(tester, game);
    gate = Completer<void>();
    late Future<void> syncing;
    await tester.runAsync(() async {
      syncing = game.debugSyncDiscardTops();
      await Future<void>.delayed(Duration.zero);
    });
    game.debugHoldDiscard(1);
    gate!.complete();
    await tester.runAsync(() => syncing);
    await settle(tester, game);
    expect(tile.isMounted, isTrue);
  });
}
