import 'package:flame/components.dart';
import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/game/rack/tile_flight.dart';
import 'tile_visual_identity_test.dart' show mount, settle, visual;

void main() {
  test('tap flight arcs above the chord and arrives exactly on time', () {
    final flight = TileFlight(start: Vector2.zero(), end: Vector2(200, 100),
        duration: .28, curve: Curves.easeOutCubic);
    flight.elapsed = .14;
    final p = flight.position;
    expect(p.y, lessThan(p.x / 2));
    flight.elapsed = .28;
    expect(flight.completed, isTrue);
    expect(flight.position, Vector2(200, 100));
  });

  test('drag flight preserves the release velocity and ends at its target', () {
    final velocity = Vector2(600, -220);
    final flight = TileFlight(start: Vector2.zero(), end: Vector2(120, 50),
        duration: .22, curve: Curves.easeOutExpo, velocity: velocity);
    flight.elapsed = .000001;
    expect((flight.position / .000001 - velocity).length, lessThan(.1));
    flight.elapsed = .22;
    expect(flight.position, Vector2(120, 50));
  });

  testWidgets('early confirmation preserves the closed flight until landing then flips', (tester) async {
    final game = await mount(tester);
    final preview = visual('__closed_draw_preview__', joker: true);
    final real = visual('confirmed');
    game.world.add(preview);
    game.world.add(real);
    await settle(tester, game);
    preview.position.setZero();
    preview.beginClosedDraw(Vector2(200, 100), dragged: false);
    preview.update(.1);
    real.position.setFrom(preview.position);
    real.inheritClosedDraw(preview);
    real.update(.17);
    expect(real.isDrawCovered, isTrue);
    expect(real.isRevealingDraw, isFalse);
    real.update(.011);
    expect(real.position, Vector2(200, 100));
    expect(real.isRevealingDraw, isTrue);
    await tester.pump();
    real.update(.079);
    await tester.pump();
    expect(real.isDrawCovered, isTrue);
    real.update(.002);
    expect(real.isDrawCovered, isFalse);
    real.update(.079);
    expect(real.isRevealingDraw, isFalse);
  });

  testWidgets('a late confirmation stays closed at rest and a drag settles exactly', (tester) async {
    final game = await mount(tester);
    final preview = visual('__closed_draw_preview__', joker: true);
    game.world.add(preview);
    await settle(tester, game);
    preview.position.setZero();
    preview.holdSourceDraw();
    preview.update(.12);
    expect(preview.presentationScale, closeTo(1.12, .0001));
    preview.beginClosedDraw(Vector2(200, 100), dragged: true);
    preview.update(.15);
    expect(preview.position.x, greaterThan(200));
    preview.update(.071);
    preview.update(.5);
    expect(preview.position, Vector2(200, 100));
    expect(preview.isDrawCovered, isTrue);
    expect(preview.isRevealingDraw, isFalse);
  });

  testWidgets('discard landing resets rotation and adds a single micro bounce', (tester) async {
    final game = await mount(tester);
    final tile = visual('landing');
    game.world.add(tile);
    await settle(tester, game);
    tile.angle = .06;
    tile.flyTo(Vector2(100, 100), duration: .22, curve: Curves.easeOutExpo,
        onComplete: tile.landOnDiscard);
    tile.update(.22);
    expect(tile.angle, 0.0);
    expect(tile.presentationScale, closeTo(1.05, .0001));
    tile.update(.14);
    expect(tile.presentationScale, 1);
    expect(tile.position, Vector2(100, 100));
  });
}
