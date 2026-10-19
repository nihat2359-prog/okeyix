import 'dart:async';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/game/game_activity_probe.dart';
import 'package:okeyix/game/observed_effect.dart';
import 'package:okeyix/services/game_view_data_source.dart';
import 'game_view_data_source_test.dart' show Harness;
import 'game_stage4b_test.dart' show mount, wakes;

void main() {
  test(
    'continuous invalidation yields after three reads; fallback recovers',
    () async {
      final h = Harness();
      var event = 0;
      h.delayedTable = () async {
        h.data.tableChanged('burst-${++event}');
        return {'current_turn': event};
      };
      await expectLater(h.data.table(), throwsStateError);
      expect(h.counts['table'], 3);
      h.delayedTable = null;
      h.state['current_turn'] = 1;
      h.advance();
      expect((await h.data.table())!['current_turn'], 1);
      expect(h.counts['table'], 4);
      h.data.dispose();
    },
  );

  test(
    'reconnect rejects an in-flight profile cache and permits fresh coins',
    () async {
      final first = Completer<ViewRows>();
      var requests = 0;
      final source = GameViewDataSource(
        tableId: 'offline-fixture',
        currentUser: () => 'a',
        fetchTable: () async => {},
        fetchPlayers: () async => [],
        fetchUsers: (_) async => [],
        fetchLeague: (_) async => [],
        fetchProfiles: (_) async => ++requests == 1
            ? first.future
            : [
                {'id': 'a', 'coins': 5000},
              ],
      );
      final pending = source.profiles(['a']);
      source.invalidateAll();
      first.complete([
        {'id': 'a', 'coins': 100},
      ]);
      await expectLater(pending, throwsStateError);
      expect((await source.profiles(['a'])).single['coins'], 5000);
      expect(requests, 2);
      source.dispose();
    },
  );

  test(
    'disabled production adapter preserves callback and adds no observer',
    () {
      final probe = GameActivityProbe();
      void callback() {}
      final effect = MoveEffect.to(
        Vector2.all(1),
        EffectController(duration: 0.2),
        onComplete: callback,
      );
      expect(observeGameEffect(effect, probe, 'disabled'), same(effect));
      expect(effect.onComplete, same(callback));
      expect(effect.children, isEmpty);
      expect(probe.snapshot()['openEffects'], 0);
      probe.dispose();
    },
    skip: GameActivityProbe.enabled ? 'explicit instrumentation build' : false,
  );

  testWidgets('cancelling a sequence closes both running and delayed effects', (
    tester,
  ) async {
    final game = await mount(tester);
    final probe = GameActivityProbe();
    final tile = PositionComponent();
    await game.add(tile);
    await tester.pump();
    var completed = 0;
    final sequence = attachEffectObservation(
      SequenceEffect([
        attachEffectObservation(
          MoveEffect.to(Vector2(100, 0), EffectController(duration: 1)),
          probe,
          'running',
        ),
        attachEffectObservation(
          ScaleEffect.to(Vector2.all(0.8), EffectController(duration: 1)),
          probe,
          'not-started',
        ),
      ], onComplete: () => completed++),
      probe,
      'sequence',
    );
    tile.add(sequence);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    sequence.removeFromParent();
    await tester.pump();
    await tester.pump();
    expect(completed, 0);
    expect(probe.snapshot()['openEffects'], 0);
    expect(wakes(probe)['effectCancelled'], 3);
    await tester.pumpWidget(const SizedBox.shrink());
    probe.dispose();
  });
}
