import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:okeyix/game/components/finish_screen.dart';
import 'package:okeyix/game/rack/tile_component.dart';
import 'package:okeyix/services/feedback_settings_service.dart';
import 'tile_visual_identity_test.dart' as fixture;

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await FeedbackSettingsService.setSoundEnabled(false);
    await (FontLoader(
      'Montserrat',
    )..addFont(rootBundle.load('assets/fonts/Montserrat-Bold.ttf'))).load();
  });
  for (final width in [640.0, 932.0]) {
    testWidgets('actual finish tiles contact both shelves at width $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 390));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final game = await fixture.mount(tester);
      await tester.runAsync(() => game.images.load('rack.png'));
      final view = FinishRackView(
        [
          for (final i in [0, 1, 12, 13, 14, 25])
            {'i': i, 'tile': fixture.payload('tile-$i')},
        ],
        fixture.payload('finish'),
        'Winner',
        true,
        false,
        100,
        false,
        false,
      );
      game.camera.viewport.add(view);
      await fixture.settle(tester, game);
      for (final tile in view.rack.children.whereType<TileComponent>()) {
        final top =
            tile.id != 'finish' && int.parse(tile.id.split('-').last) >= 13;
        final bottom = tile.position.y + tile.size.y * tile.scale.y / 2;
        expect(
          bottom,
          closeTo(view.rack.size.y * (top ? 160 / 424 : 303 / 424), .001),
        );
        expect(
          tile.position.y - tile.size.y * tile.scale.y / 2,
          greaterThan(0),
        );
      }
      final finish = view.children.whereType<TileComponent>().single;
      expect(finish.id, 'finish');
      expect(finish.position.x, view.rack.position.x);
      expect(
        finish.position.y + finish.size.y * finish.scale.y / 2,
        lessThan(view.rack.position.y - view.rack.size.y / 2),
      );
      await expectLater(
        find.byType(GameWidget<fixture.VisualGame>),
        matchesGoldenFile('goldens/finish_rack_${width.toInt()}.png'),
      );
    });
  }
}
