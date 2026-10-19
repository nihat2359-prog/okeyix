import 'dart:async';
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/game/game_activity_probe.dart';
import 'package:okeyix/game/observed_effect.dart';

Map<String, int> wakes(GameActivityProbe probe) =>
    (probe.snapshot()['wakeCounts'] as Map<String, int>);

Future<FlameGame> mount(WidgetTester tester) async {
  final game = FlameGame();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: GameWidget(game: game),
    ),
  );
  await tester.pump();
  return game;
}

void main() {
  testWidgets(
    'short discard-like effect: same identity, completion callback and position',
    (tester) async {
      final game = await mount(tester);
      final probe = GameActivityProbe();
      var callbacks = 0;
      final tile = PositionComponent();
      await game.add(tile);
      await tester.pump();
      final effect = MoveEffect.to(
        Vector2(100, 20),
        EffectController(duration: 0.018),
        onComplete: () {
          callbacks++;
          expect(probe.snapshot()['openEffects'], 1);
        },
      );
      expect(
        attachEffectObservation(effect, probe, 'autoDiscard'),
        same(effect),
      );
      expect(effect, isA<MoveEffect>());
      tile.add(effect);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      await tester.pump();
      expect(tile.position.x, closeTo(100, 0.001));
      expect(callbacks, 1);
      expect(probe.snapshot()['openEffects'], 0);
      expect(wakes(probe)['effectCompleted'], 1);
      expect(wakes(probe)['effectCancelled'], isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      probe.dispose();
    },
  );

  testWidgets('remote motion cancelled by parent removal closes observation', (
    tester,
  ) async {
    final game = await mount(tester);
    final probe = GameActivityProbe();
    final transient = PositionComponent();
    await game.add(transient);
    await tester.pump();
    var callbacks = 0;
    transient.add(
      attachEffectObservation(
        MoveEffect.to(
          Vector2(100, 0),
          EffectController(duration: 1),
          onComplete: () => callbacks++,
        ),
        probe,
        'remote',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    transient.removeFromParent();
    await tester.pump();
    await tester.pump();
    expect(callbacks, 0);
    expect(probe.snapshot()['openEffects'], 0);
    expect(wakes(probe)['effectCancelled'], 1);
    await tester.pumpWidget(const SizedBox.shrink());
    probe.dispose();
  });

  testWidgets(
    'sequence with move and scale preserves child controllers and closes all scopes',
    (tester) async {
      final game = await mount(tester);
      final probe = GameActivityProbe();
      final tile = PositionComponent();
      await game.add(tile);
      await tester.pump();
      final move = attachEffectObservation(
        MoveEffect.to(Vector2(40, 0), EffectController(duration: 0.03)),
        probe,
        'deal',
      );
      final scale = attachEffectObservation(
        ScaleEffect.to(Vector2.all(0.8), EffectController(duration: 0.03)),
        probe,
        'scale',
      );
      tile.add(
        attachEffectObservation(
          SequenceEffect([move, scale]),
          probe,
          'sequence',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump();
      expect(tile.position.x, closeTo(40, 0.001));
      expect(tile.scale.x, closeTo(0.8, 0.001));
      expect(probe.snapshot()['openEffects'], 0);
      expect(wakes(probe)['effectCompleted'], 3);
      await tester.pumpWidget(const SizedBox.shrink());
      probe.dispose();
    },
  );

  test(
    'queued/unmounted effect and unresolved network work never produce confirmed idle',
    () async {
      var time = 0;
      final probe = GameActivityProbe(microseconds: () => time);
      probe.visibility(true);
      attachEffectObservation(
        MoveEffect.to(Vector2.all(1), EffectController(duration: 1)),
        probe,
        'queued',
      );
      final result = Completer<void>();
      final operation = probe.observeOperation(() => result.future);
      time = 100001;
      probe.sample(Component(), pending: false, dragging: false);
      expect(probe.snapshot()['openEffects'], 1);
      expect(probe.snapshot()['openOperations'], 1);
      expect(probe.snapshot()['confirmedIdleMeasured'], false);
      result.complete();
      await operation;
      expect(probe.snapshot()['openOperations'], 0);
      probe.dispose();
    },
  );

  test(
    'network exceptions close scope; unknown effects fail coverage; notifications never invoke engine',
    () async {
      final probe = GameActivityProbe();
      await expectLater(
        probe.observeOperation(() async {
          throw StateError('offline');
        }),
        throwsStateError,
      );
      expect(probe.snapshot()['openOperations'], 0);
      for (final reason in GameWakeReason.values) {
        probe.notifyWake(reason);
      }
      expect(
        probe.snapshot()['wakeRevision'],
        greaterThanOrEqualTo(GameWakeReason.values.length),
      );
      expect(probe.snapshot()['coverageComplete'], false);
      expect(probe.snapshot()['confirmedIdleMicroseconds'], 0);
      probe.dispose();
      final revision = probe.snapshot()['wakeRevision'];
      probe.notifyWake(GameWakeReason.network);
      expect(probe.snapshot()['wakeRevision'], revision);
    },
  );
}
