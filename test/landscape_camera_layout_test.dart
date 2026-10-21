import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// Exercise the production game's camera configuration independently of its
// network/game state. Screen sizes are test fixtures, not device measurements.
void main() {
  for (final size in [
    const Size(852, 393),
    const Size(844, 390),
    const Size(960, 432),
    const Size(640, 360),
    const Size(1024, 600),
  ]) {
    testWidgets('full GameWidget and rack projection at $size', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final world = World();
      final camera = CameraComponent.withFixedResolution(
        world: world,
        width: 1600,
        height: 900,
      );
      camera.viewfinder.position = Vector2(800, 450);
      final game = FlameGame(world: world, camera: camera);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: GameWidget(game: game),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(tester.getSize(find.byType(GameWidget<FlameGame>)), size);
      expect(game.canvasSize.x, closeTo(size.width, .001));
      expect(game.canvasSize.y, closeTo(size.height, .001));
      final scale = math.min(size.width / 1600, size.height / 900);
      expect(camera.viewport.size.x, closeTo(1600 * scale, .001));
      expect(camera.viewport.size.y, closeTo(900 * scale, .001));
      for (final point in [Vector2(260, 741), Vector2(1364, 605)]) {
        final projected = camera.localToGlobal(point.clone());
        // Same transform as DraggedTilesOverlay: dragging must stay aligned.
        expect(
          projected.x,
          closeTo(size.width / 2 + (point.x - 800) * scale, .001),
        );
        expect(
          projected.y,
          closeTo(size.height / 2 + (point.y - 450) * scale, .001),
        );
        expect(
          camera.globalToLocal(projected).distanceTo(point),
          lessThan(.001),
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
