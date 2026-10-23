import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:okeyix/engine/models/tile.dart';
import 'package:okeyix/game/components/closed_pile_component.dart';
import 'package:okeyix/game/components/themed_tile_back.dart';
import 'package:okeyix/game/tile_theme.dart';
import 'package:okeyix/services/tile_theme_service.dart';
import 'package:okeyix/services/user_state.dart';
import 'package:okeyix/ui/game_settings_dialog.dart';
import 'package:okeyix/ui/tile_themes_dialog.dart';
import 'tile_visual_identity_test.dart' as fixture;

class CountedPileDecoration extends ClosedPileDecoration {
  int recordings = 0;
  @override
  void renderDecoration(Canvas canvas) {
    recordings++;
    super.renderDecoration(canvas);
  }
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Montserrat',
    )..addFont(rootBundle.load('assets/fonts/Montserrat-Bold.ttf'))).load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TileThemeService.selected.value = TileThemeId.porcelain;
    UserState.colorBlindMode = false;
  });
  tearDown(() {
    UserState.colorBlindMode = false;
    TileThemeService.selected.value = TileThemeId.porcelain;
  });

  testWidgets(
    'deck, counter, closed drag and spectator back follow all six themes',
    (tester) async {
      final game = await fixture.mount(tester);
      final pile = ClosedPileComponent(
        position: Vector2(200, 170),
        initialCount: 65,
      );
      final back = ThemedTileBack(
        sprite: Sprite(game.images.fromCache('tile_back.png')),
        size: Vector2(90, 118),
        position: Vector2(300, 170),
      );
      final count = ThemedDeckCount(
        classicStyle: const TextStyle(color: Color(0xFF000C4E), fontSize: 46),
        text: '65',
        position: Vector2(300, 170),
      );
      final preview = fixture.visual('__closed_draw_preview__', joker: true);
      game.world.addAll([pile, back, count, preview]);
      await fixture.settle(tester, game);
      for (final palette in TileThemePalette.all) {
        await TileThemeService.select(palette.id);
        await tester.pump();
        final filterMatcher = palette.id == TileThemeId.porcelain
            ? isNull
            : isNotNull;
        expect(pile.backSprite.paint.colorFilter, filterMatcher);
        expect(preview.backSprite.paint.colorFilter, filterMatcher);
        expect(back.paint.colorFilter, filterMatcher);
        expect(preview.isFaceDown, isTrue);
        expect(preview.position, Vector2.zero());
        expect(pile.position, Vector2(200, 170));
        expect(pile.size, Vector2(100, 140));
        expect(
          pile.countText!.position,
          ClosedPileDecoration.topTileCenter(pile.size),
        );
        expect((pile.countText!.textRenderer as TextPaint).style.fontSize, 48);
        expect(
          (pile.countText!.textRenderer as TextPaint).style.color,
          palette.id == TileThemeId.porcelain
              ? const Color(0xFF253A63)
              : palette.ink(TileColor.black),
        );
        expect(
          (count.textRenderer as TextPaint).style.color,
          palette.id == TileThemeId.porcelain
              ? const Color(0xFF000C4E)
              : palette.ink(TileColor.black),
        );
        pile.updateCount(42);
        expect(pile.countText!.text, '42');
      }
      // The ui.Picture records once, then only again on a visual theme change.
      final decoration = CountedPileDecoration()
        ..size = Vector2(100, 140)
        ..backSprite = Sprite(game.images.fromCache('tile_back.png'));
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      decoration.render(canvas);
      decoration.render(canvas);
      expect(decoration.recordings, 1);
      decoration.palette = TileThemePalette.of(TileThemeId.midnight);
      decoration.backSprite.paint.colorFilter = decoration.palette.filter;
      decoration.render(canvas);
      decoration.render(canvas);
      expect(decoration.recordings, 2);
      recorder.endRecording().dispose();
      decoration.onRemove();
      game.world.removeAll([pile, back, count, preview]);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(480, 270), const Size(844, 390)]) {
    testWidgets(
      'in-game settings opens themes and persists color-blind preference at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'Montserrat'),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => GameSettingsDialog(
                      initialInvites: true,
                      saveInvites: (_) async {},
                    ),
                  ),
                  child: const Text('Ayarları aç'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ayarları aç'));
        await tester.pumpAndSettle();
        expect(find.text('Hesabı Sil'), findsNothing);
        final blind = find.byKey(const ValueKey('setting-Renk Körü Modu'));
        await tester.scrollUntilVisible(
          blind,
          60,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(blind);
        await tester.pumpAndSettle();
        expect(UserState.colorBlindMode, isTrue);
        expect(
          (await SharedPreferences.getInstance()).getBool('color_blind_mode'),
          isTrue,
        );
        await tester.tap(find.text('Taş Temaları'));
        await tester.pumpAndSettle();
        expect(find.byType(TileThemesDialog), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('tile-theme-midnight')));
        await tester.pumpAndSettle();
        expect(TileThemeService.selected.value, TileThemeId.midnight);
        expect(find.byType(TileThemesDialog), findsNothing);
        expect(find.byType(GameSettingsDialog), findsNothing);
        expect(find.text('Ayarları aç'), findsOneWidget);
        await tester.tap(find.text('Ayarları aç'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Taş Temaları'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Kapat').last);
        await tester.pumpAndSettle();
        expect(find.byType(TileThemesDialog), findsNothing);
        expect(find.byType(GameSettingsDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
