import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:okeyix/game/components/finish_screen.dart';
import 'package:okeyix/game/rack/tile_component.dart';
import 'package:okeyix/services/feedback_settings_service.dart';
import 'package:okeyix/ui/spectator_finish_notice.dart';
import 'tile_visual_identity_test.dart' as fixture;

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await FeedbackSettingsService.setSoundEnabled(false);
  });
  for (final size in [const Size(568, 320), const Size(932, 430)]) {
    for (final withTiles in [false, true]) {
      testWidgets('centered spectator panel $size tiles=$withTiles', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var readyCount = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                padding: const EdgeInsets.fromLTRB(59, 0, 44, 21),
                textScaler: TextScaler.linear(2),
              ),
              child: Scaffold(
                body: SpectatorFinishNotice(
                  onReady: () => readyCount++,
                  winnerName: 'Uzun İsimli Kazanan Oyuncu',
                  finishLabel: 'Okey atarak bitiş',
                  slots: withTiles
                      ? [
                          for (var i = 0; i < 14; i++)
                            {'i': i, 'tile': fixture.payload('tile-$i')},
                        ]
                      : const [],
                  finishTile: fixture.payload('finish'),
                ),
              ),
            ),
          ),
        );
        if (withTiles) {
          final game =
              tester
                      .widget<GameWidget>(
                        find.byWidgetPredicate((w) => w is GameWidget),
                      )
                      .game!
                  as FlameGame;
          await tester.runAsync(() async {
            await game.toBeLoaded();
          });
          for (var i = 0; i < 25; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump(const Duration(milliseconds: 16));
          }
          final view = game.camera.viewport.children
              .whereType<FinishRackView>()
              .single;
          expect(view.rack.children.whereType<TileComponent>().length, 14);
          expect(view.children.whereType<TileComponent>().single.id, 'finish');
          for (final tile in view.children.whereType<TileComponent>()) {
            expect(
              view.position.y +
                  tile.position.y -
                  tile.size.y * tile.scale.y / 2,
              greaterThan(0),
            );
          }
        } else {
          await tester.pumpAndSettle();
        }
        expect(find.text('ELİN KAZANANI'), findsOneWidget);
        final panel = tester.getRect(
          find.byKey(const ValueKey('spectator-finish-panel')),
        );
        expect(panel.center.dx, closeTo((size.width + 59 - 44) / 2, 1));
        expect(panel.center.dy, closeTo((size.height - 21) / 2, 1));
        expect(panel.left, greaterThanOrEqualTo(59));
        expect(panel.width, lessThanOrEqualTo(640));
        expect(panel.height, lessThan(size.height * .8));
        expect(panel.bottom, lessThanOrEqualTo(size.height - 21));
        for (final text in [
          'Uzun İsimli Kazanan Oyuncu',
          'Okey atarak bitiş',
        ]) {
          expect(panel.contains(tester.getCenter(find.text(text))), isTrue);
        }
        expect(tester.takeException(), isNull);
        expect(readyCount, withTiles ? 1 : 0);
        await tester.pump(const Duration(seconds: 2));
        expect(readyCount, withTiles ? 1 : 0);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
