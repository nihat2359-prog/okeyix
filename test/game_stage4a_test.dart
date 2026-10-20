import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/game.dart' show FlameGame, GameWidget;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/game/stage.dart';
import 'package:okeyix/game/components/closed_pile_component.dart';
import 'package:okeyix/game/game_activity_probe.dart';
import 'game_decoration_cache_test.dart' show pixels;

class CountedPile extends ClosedPileDecoration {
  int recordings = 0;
  @override
  void renderDecoration(Canvas canvas) {
    recordings++;
    super.renderDecoration(canvas);
  }
}

class SampleTree extends Component {
  List<Component> observed = [];
  @override
  Iterable<Component> descendants({
    bool includeSelf = false,
    bool reversed = false,
  }) => observed;
}

void uncachedLabels(Canvas canvas, Vector2 size, String label) {
  final style = TextStyle(
    color: const Color(0xFFE5D3AA),
    fontSize: 23,
    fontWeight: FontWeight.w600,
    height: 1,
  );
  final paint = TextPaint(style: style);
  final lines = label.split(' ');
  const lineHeight = 27.0;
  var y = (size.y - lines.length * lineHeight) / 2;
  for (final line in lines) {
    final measure = TextPainter(
      text: TextSpan(text: line, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    paint.render(
      canvas,
      line,
      Vector2((size.x - measure.width) / 2, y),
      anchor: Anchor.topLeft,
    );
    measure.dispose();
    y += lineHeight;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('rack entrance effect continues with cached labels', (
    tester,
  ) async {
    final game = FlameGame();
    final button = RackActionButton(
      label: 'Seri Diz',
      targetPosition: Vector2(100, 40),
      startPosition: Vector2.zero(),
      size: Vector2(96, 200),
      onTap: () {},
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GameWidget(game: game),
      ),
    );
    await tester.pump();
    await game.add(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(button.position.x, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(button.position.x, closeTo(100, 0.001));
    expect(button.position.y, closeTo(40, 0.001));
    expect(button.textMeasurements, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test(
    'button retains text measurements; uncached pixels match; resize and cleanup',
    () async {
      final button = RackActionButton(
        label: 'Seri Diz',
        targetPosition: Vector2.zero(),
        startPosition: Vector2.zero(),
        size: Vector2(96, 200),
        onTap: () {},
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      for (var i = 0; i < 600; i++) {
        button.renderLabels(canvas);
      }
      expect(button.textMeasurements, 2);
      recorder.endRecording().dispose();
      for (final size in [Vector2(96, 200), Vector2(88, 90)]) {
        button.size.setFrom(size);
        expect(
          await pixels(button.renderLabels),
          await pixels((c) => uncachedLabels(c, size, button.label)),
        );
      }
      expect(button.textMeasurements, 4);
      button.onRemove();
      await pixels(button.renderLabels);
      expect(button.textMeasurements, 6);
      button.onRemove();
    },
  );

  test(
    'pile records once; original pixels match; sprite, size and removal invalidate',
    () async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 20, 30),
        Paint()..color = Colors.blue,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(20, 30);
      picture.dispose();
      final pile = CountedPile()
        ..size.setValues(100, 140)
        ..backSprite = Sprite(image);
      final frames = ui.PictureRecorder();
      final canvas = Canvas(frames);
      for (var i = 0; i < 600; i++) {
        pile.render(canvas);
      }
      expect(pile.recordings, 1);
      frames.endRecording().dispose();
      for (final size in [Vector2(100, 140), Vector2(80, 110)]) {
        pile.size.setFrom(size);
        expect(await pixels(pile.render), await pixels(pile.renderDecoration));
      }
      // Reference calls also count; isolate invalidation from those calls.
      final before = pile.recordings;
      pile.backSprite = Sprite(image);
      await pixels(pile.render);
      expect(pile.recordings, before + 1);
      pile.backSprite.paint.color = Colors.red;
      await pixels(pile.render);
      expect(pile.recordings, before + 2);
      pile.onRemove();
      await pixels(pile.render);
      expect(pile.recordings, before + 3);
      pile.onRemove();
      image.dispose();
    },
  );

  test(
    'probe distinguishes activity, hidden, unknown and unverified quiet',
    () {
      var now = 0;
      final probe = GameActivityProbe(microseconds: () => now);
      final root = SampleTree();
      probe.visibility(true);
      probe.sample(root, pending: false, dragging: false);
      now += 200000;
      probe.pointer(1, true);
      now += 100000;
      probe.sample(root, pending: false, dragging: false);
      probe.pointer(1, false);
      root.observed = [
        MoveEffect.to(Vector2.all(1), EffectController(duration: 1)),
      ];
      now += 100001;
      probe.sample(root, pending: false, dragging: false);
      root.observed = [];
      now += 100001;
      probe.sample(root, pending: true, dragging: false);
      now += 100001;
      probe.sample(root, pending: false, dragging: true);
      probe.event('dealRequested');
      probe.event('tableUpdateCandidate');
      probe.visibility(false);
      now += 200000;
      probe.visibility(true);
      now += 100000;
      final report = probe.snapshot();
      final times = report['microseconds'] as Map<String, int>;
      final events = report['events'] as Map<String, int>;
      expect(times['quietUnverified'], 200000);
      expect(times['active'], greaterThan(0));
      expect(times['hidden'], 200000);
      expect(times['unknown'], 100000);
      expect(events['effectFirstObserved'], 1);
      expect(events['effectNoLongerObserved'], 1);
      expect(events['pendingLifecycleSample'], 1);
      expect(events['dragSample'], 1);
      expect(report['confirmedIdleMicroseconds'], 0);
      probe.dispose();
    },
  );

  testWidgets(
    'route cover and return update visibility; pointer is observed without consuming input',
    (tester) async {
      final probe = GameActivityProbe();
      var tapped = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: GameActivityBoundary(
            probe: probe,
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  tapped++;
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(body: Text('covered')),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tapped, 1);
      var events = probe.snapshot()['events'] as Map<String, int>;
      expect(events['pointerDown'], 1);
      expect(events['pointerUpOrCancel'], 1);
      expect(events['hidden'], greaterThan(0));
      Navigator.of(tester.element(find.text('covered'))).pop();
      await tester.pump();
      await tester.pumpAndSettle();
      events = probe.snapshot()['events'] as Map<String, int>;
      expect(events['visible'], greaterThanOrEqualTo(2));
      await tester.pumpWidget(const SizedBox.shrink());
      probe.dispose();
    },
  );
}
