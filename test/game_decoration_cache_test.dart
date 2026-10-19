import 'dart:ui' as ui;

import 'package:flame/effects.dart';
import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/game/rack/preview_component.dart';
import 'package:okeyix/game/rack/tile_component.dart';

class CountedSurface extends TileSurfaceFx {
  int recordings = 0;
  CountedSurface() : super(size: Vector2(64, 90), position: Vector2.zero());

  @override
  void renderDecoration(ui.Canvas canvas) {
    recordings++;
    super.renderDecoration(canvas);
  }
}

Future<List<int>> pixels(void Function(ui.Canvas) draw) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..scale(1.75);
  draw(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(256, 256);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final result = bytes!.buffer.asUint8List().toList();
  image.dispose();
  picture.dispose();
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'static surface records once over 600 frames; resize and removal invalidate',
    () {
      final surface = CountedSurface();
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      for (var i = 0; i < 600; i++) {
        surface.render(canvas);
      }
      expect(surface.recordings, 1);
      // Position/scale changes are external to the recorded local decoration.
      surface.position.setValues(20, 30);
      surface.scale.setValues(0.8, 1.2);
      surface.render(canvas);
      expect(surface.recordings, 1);
      surface.size.x = 70;
      surface.render(canvas);
      expect(surface.recordings, 2);
      surface.onRemove();
      surface.render(canvas);
      expect(surface.recordings, 3);
      recorder.endRecording().dispose();
      surface.onRemove();
    },
  );

  test(
    'surface and preview cached drawing matches original commands after resize',
    () async {
      final surface = CountedSurface();
      final preview = PreviewComponent(size: Vector2(64, 90));
      for (final size in [Vector2(64, 90), Vector2(90, 115)]) {
        surface.size.setFrom(size);
        preview.size.setFrom(size);
        expect(
          await pixels(surface.render),
          await pixels(surface.renderDecoration),
        );
        expect(
          await pixels(preview.render),
          await pixels(preview.renderDecoration),
        );
      }
      surface.onRemove();
      preview.onRemove();
    },
  );

  test('hidden preview emits no pixels and becomes visible again', () async {
    final preview = PreviewComponent(size: Vector2(64, 90));
    preview.position.setValues(40, 50);
    final shown = await pixels(preview.renderTree);
    preview.isVisible = false;
    expect(await pixels(preview.renderTree), await pixels((_) {}));
    preview.isVisible = true;
    expect(await pixels(preview.renderTree), shown);
    preview.onRemove();
  });

  testWidgets(
    'move effects and child updates continue through decoration cache',
    (tester) async {
      final game = FlameGame();
      final surface = CountedSurface();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: GameWidget(game: game),
        ),
      );
      await tester.pump();
      await game.add(surface);
      await tester.pump();
      surface.add(
        MoveEffect.to(Vector2(100, 50), EffectController(duration: 0.2)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(surface.position.x, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 200));
      expect(surface.position.x, closeTo(100, 0.001));
      expect(surface.position.y, closeTo(50, 0.001));
      expect(surface.recordings, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
