import 'dart:async';
import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/game/okey_game.dart';
import 'package:okeyix/game/spectator_game.dart';
import 'package:okeyix/game/rack/preview_component.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TestChannel extends Fake implements RealtimeChannel {
  final String name;
  TestChannel(this.name);
  void Function(RealtimeSubscribeStatus, Object?)? status;
  final List<(PostgresChangeEvent, void Function(PostgresChangePayload))>
  events = [];
  @override
  RealtimeChannel subscribe([
    void Function(RealtimeSubscribeStatus, Object?)? callback,
    Duration? timeout,
  ]) {
    status = callback;
    return this;
  }

  @override
  RealtimeChannel onPostgresChanges({
    required PostgresChangeEvent event,
    String? schema,
    String? table,
    PostgresChangeFilter? filter,
    required void Function(PostgresChangePayload) callback,
  }) {
    events.add((event, callback));
    return this;
  }

  void deleted(String tableId) {
    for (final entry in events.where(
      (e) => e.$1 == PostgresChangeEvent.delete,
    )) {
      entry.$2(
        PostgresChangePayload(
          schema: 'public',
          table: 'tables',
          commitTimestamp: DateTime.utc(2026),
          eventType: PostgresChangeEvent.delete,
          newRecord: {},
          oldRecord: {'id': tableId},
          errors: null,
        ),
      );
    }
  }
}

class TestClient extends Fake implements SupabaseClient {
  final List<TestChannel> channels = [];
  final Map<RealtimeChannel, int> removed = {};
  Completer<String>? closeGate;
  @override
  dynamic noSuchMethod(Invocation call) {
    if (call.memberName == #channel) {
      final channel = TestChannel(call.positionalArguments.first as String);
      channels.add(channel);
      return channel;
    }
    if (call.memberName == #removeChannel) {
      final channel = call.positionalArguments.first as TestChannel;
      removed[channel] = (removed[channel] ?? 0) + 1;
      // Simulate the SDK reporting closed during intentional removal.
      channel.status?.call(RealtimeSubscribeStatus.closed, null);
      return closeGate?.future ?? Future<String>.value('ok');
    }
    return super.noSuchMethod(call);
  }
}

// Only bypass native/network onLoad. Exercise the real lifecycle and channel code.
class LoadedGame extends OkeyGame {
  LoadedGame(TestClient client, String table)
    : super(tableId: table, isCreator: false, realtimeClient: client);
  @override
  bool get isLoaded => true;
}

class LoadedSpectator extends SpectatorGame {
  LoadedSpectator(TestClient client, String table, void Function() closed)
    : super(tableId: table, realtimeClient: client, onTableClosed: closed);
  @override
  bool get isLoaded => true;
}

void showResult(OkeyGame game) =>
    game.showFinishFromGame([], {}, 'winner', true, false, 2500, false, false);

OkeyGame finishFixture(TestClient client) {
  final game = OkeyGame(
    tableId: 'finish',
    isCreator: false,
    realtimeClient: client,
  );
  game.world = World();
  game.previewBox = PreviewComponent(size: Vector2(10, 10));
  return game;
}

void main() {
  testWidgets(
    'leaving during reconnect cancels old work; new table stays independent',
    (tester) async {
      final client = TestClient();
      final old = LoadedGame(client, 'old')..onAttach();
      final channel = client.channels.single;
      channel.status!(RealtimeSubscribeStatus.channelError, null);
      old.onDetach();
      old.onRemove();
      old.onRemove();
      final next = LoadedGame(client, 'next')..onAttach();
      channel.status!(RealtimeSubscribeStatus.closed, null);
      await tester.pump(const Duration(seconds: 10));
      expect(client.channels.map((e) => e.name), ['table_old', 'table_next']);
      expect(client.removed[channel], 1);
      next.onDetach();
      next.onRemove();
    },
  );

  testWidgets('normal reconnect coalesces errors; success resets backoff', (
    tester,
  ) async {
    final client = TestClient();
    final game = LoadedGame(client, 'active')..onAttach();
    final first = client.channels.single;
    first.status!(RealtimeSubscribeStatus.channelError, null);
    first.status!(RealtimeSubscribeStatus.closed, null);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(client.channels.length, 2);
    expect(client.removed[first], 1);
    final second = client.channels.last;
    second.status!(RealtimeSubscribeStatus.channelError, null);
    second.status!(RealtimeSubscribeStatus.subscribed, null);
    await tester.pump(const Duration(seconds: 3));
    expect(client.channels.length, 2);
    second.status!(RealtimeSubscribeStatus.channelError, null);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(client.channels.length, 3);
    game.onDetach();
    game.onRemove();
  });

  testWidgets(
    'close pending during reconnect cannot create a channel after removal',
    (tester) async {
      final client = TestClient();
      final game = LoadedGame(client, 'race')..onAttach();
      client.closeGate = Completer<String>();
      client.channels.single.status!(
        RealtimeSubscribeStatus.channelError,
        null,
      );
      await tester.pump(const Duration(seconds: 1));
      game.onDetach();
      game.onRemove();
      client.closeGate!.complete('ok');
      await tester.pump();
      expect(client.channels.length, 1);
    },
  );

  testWidgets(
    'repeated spectator entry cleans only owned channels; stale callbacks ignored',
    (tester) async {
      final client = TestClient();
      var calls = 0;
      final unrelated = client.channel('screen-owned') as TestChannel;
      for (var i = 0; i < 3; i++) {
        final game = LoadedSpectator(client, 'watch', () => calls++)
          ..onAttach();
        final channel = client.channels.last;
        await game.startRealtime();
        channel.deleted('watch');
        expect(calls, i + 1);
        game.onDetach();
        game.onRemove();
        game.onRemove();
        for (final entry in channel.events) {
          entry.$2(
            PostgresChangePayload(
              schema: 'public',
              table: 'tables',
              commitTimestamp: DateTime.utc(2026),
              eventType: entry.$1,
              newRecord: {'move_type': 'discard', 'tile_data': 'invalid-json'},
              oldRecord: {'id': 'watch'},
              errors: null,
            ),
          );
        }
        expect(calls, i + 1);
        channel.deleted('watch');
        expect(calls, i + 1);
        expect(client.removed[channel], 1);
      }
      expect(client.removed.containsKey(unrelated), false);
      expect(client.channels.length, 4);
    },
  );

  testWidgets(
    'spectator detach/attach waits for old close and rejects its events',
    (tester) async {
      final client = TestClient();
      var calls = 0;
      final game = LoadedSpectator(client, 'watch', () => calls++)..onAttach();
      final old = client.channels.single;
      client.closeGate = Completer<String>();
      game.onDetach();
      game.onAttach();
      expect(client.channels.length, 1);
      old.deleted('watch');
      expect(calls, 0);
      client.closeGate!.complete('ok');
      await tester.pump();
      expect(client.channels.length, 2);
      client.channels.last.deleted('watch');
      expect(calls, 1);
      game.onDetach();
      game.onRemove();
    },
  );

  testWidgets('finish timeout cannot access a removed game', (tester) async {
    final game = finishFixture(TestClient());
    final states = <bool>[];
    game.onFinishVisibilityChanged = states.add;
    showResult(game);
    game.onDetach();
    game.onRemove();
    game.onRemove();
    await tester.pump(const Duration(seconds: 10));
    showResult(game);
    game.hideFinish();
    expect(states, [true]);
  });

  testWidgets(
    'normal finish preserves result; replacement receives its own four seconds',
    (tester) async {
      final game = finishFixture(TestClient());
      final states = <bool>[];
      game.onFinishVisibilityChanged = states.add;
      showResult(game);
      expect(game.finishView!.winAmount, 2500);
      expect(game.finishView!.winnerName, 'winner');
      await tester.pump(const Duration(seconds: 2));
      final old = game.finishView;
      showResult(game);
      expect(identical(game.finishView, old), false);
      await tester.pump(const Duration(seconds: 2));
      expect(game.isFinishOpen, true);
      await tester.pump(const Duration(seconds: 2));
      expect(game.isFinishOpen, false);
      game.hideFinish();
      expect(states, [true, true, false]);
      game.onRemove();
    },
  );
}
