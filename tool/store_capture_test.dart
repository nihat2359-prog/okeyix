// Local marketing fixture. Does not connect to accounts or change game data.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:okeyix/game/stage.dart';
import 'package:okeyix/game/rack/rack_slot_generator.dart';
import 'package:okeyix/game/rack/tile_component.dart';
import 'package:okeyix/engine/models/tile.dart';
import '../test/tile_visual_identity_test.dart' as visual;
import 'package:okeyix/ui/reward_dialogs.dart';
import 'package:okeyix/ui/tile_themes_dialog.dart';
import '../test/lobby_presentation_test.dart' as lobby;
import '../test/create_table_scene_test.dart' as create;
import '../test/lobby_social_panel_test.dart' as social;

class StoreTableDetail extends visual.VisualGame {
  @override
  Future<void> onLoad() async {
    world = World();
    cameraComponent = CameraComponent.withFixedResolution(
      world: world,
      width: 1600,
      height: 900,
    );
    cameraComponent.viewfinder.position = Vector2(800, 450);
    addAll([world, cameraComponent]);
    await images.loadAll([
      'table.png',
      'rack.png',
      'tile_base.png',
      'tile_back.png',
    ]);
    world.add(
      SpriteComponent(
        sprite: Sprite(images.fromCache('table.png')),
        size: Vector2(1600, 900),
      )..priority = -10,
    );
    world.add(Stage());
    final slots = RackSlotGenerator.generate();
    final colors = [
      TileColor.red,
      TileColor.blue,
      TileColor.black,
      TileColor.yellow,
    ];
    for (var i = 0; i < 14; i++) {
      final slot = i < 7 ? i + 13 : i - 7;
      world.add(
        TileComponent(
          tile: TileModel(
            id: 'promo-$i',
            value: [1, 2, 3, 7, 7, 7, 11, 4, 5, 6, 9, 10, 11, 13][i],
            color: colors[[0, 0, 0, 0, 1, 2, 2, 1, 1, 1, 3, 3, 3, 0][i]],
          ),
          position: slots[slot],
        ),
      );
    }
    for (var i = 0; i < 3; i++) {
      world.add(
        SpriteComponent(
          sprite: Sprite(images.fromCache('tile_back.png')),
          size: Vector2(72, 96),
          position: Vector2(710 + i * 3, 270 - i * 3),
        ),
      );
    }
    world.add(
      TileComponent(
        tile: TileModel(id: 'indicator', value: 12, color: TileColor.blue),
        position: Vector2(845, 320),
      ),
    );
    world.add(
      TileComponent(
        tile: TileModel(id: 'discard', value: 5, color: TileColor.red),
        position: Vector2(350, 300),
      ),
    );
  }
}

void main() {
  const size = Size(932, 430);
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await (FontLoader('Montserrat')
          ..addFont(rootBundle.load('assets/fonts/Montserrat-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Montserrat-Bold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets('capture game detail', (tester) async {
    await tester.binding.setSurfaceSize(const Size(960, 540));
    final key = GlobalKey();
    final game = StoreTableDetail();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: GameWidget(game: game),
      ),
    );
    await tester.runAsync(() => game.loaded);
    await tester.runAsync(() => game.ready());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('artifacts/sources/game.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });
  for (final name in ['lobby', 'create', 'friends', 'rewards', 'themes']) {
    testWidgets('capture $name', (tester) async {
      await tester.binding.setSurfaceSize(size);
      if (name == 'lobby') {
        await lobby.lobby(
          tester,
          size,
          1,
          [],
          openTables: [
            lobby.table('waiting')..['id'] = 'preview-a',
            lobby.table('playing')..['id'] = 'preview-b',
            lobby.table('waiting')..['id'] = 'preview-c',
          ],
        );
      } else if (name == 'create') {
        await create.scene(tester, size, create.Draft());
      } else if (name == 'friends') {
        await social.scene(tester, size, 1, []);
      } else {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'Montserrat'),
            home: Scaffold(
              body: Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      'assets/images/lobby/lobby.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                  if (name == 'themes')
                    const TileThemesDialog()
                  else
                    DailyBonusDialog(
                      amount: 20000,
                      rewardDay: 4,
                      weeklyRewards: const [
                        2500,
                        5000,
                        10000,
                        20000,
                        40000,
                        80000,
                        160000,
                      ],
                      onSound: (_) {},
                      onClaim: () async => true,
                      onStore: () {},
                    ),
                ],
              ),
            ),
          ),
        );
      }
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: app.theme,
            builder: app.builder,
            home: app.home,
          ),
        ),
      );
      await tester.runAsync(() async {
        final context = key.currentContext!;
        for (final path in [
          'assets/images/lobby/lobby.png',
          'assets/images/table.png',
            'assets/images/tile_base.png',
          'assets/images/coins/coins_small.png',
          'assets/images/coins/coins_medium.png',
          'assets/images/coins/coins_large.png',
          'assets/images/coins/coins_huge.png',
        ]) {
          await precacheImage(AssetImage(path), context);
        }
      });
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 3);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('artifacts/sources/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
      await tester.binding.setSurfaceSize(null);
    });
  }
}
