import 'package:flame/components.dart';
import 'dart:ui' as ui;
import 'package:flame/effects.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:okeyix/engine/models/tile.dart';
import 'package:okeyix/game/components/indicator_component.dart';
import 'package:okeyix/game/rack/tile_component.dart';
import 'package:okeyix/game/tile_theme.dart';
import 'package:okeyix/services/tile_theme_service.dart';
import 'package:okeyix/services/user_state.dart';
import 'package:okeyix/ui/tile_themes_dialog.dart';
import 'tile_visual_identity_test.dart' as fixture;
import 'lobby_utility_scenes_test.dart' as settings;

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Montserrat',
    )..addFont(rootBundle.load('assets/fonts/Montserrat-Bold.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TileThemeService.selected.value = TileThemeId.porcelain;
  });
  tearDown(() => TileThemeService.selected.value = TileThemeId.porcelain);

  test(
    'solid ink or outlined ink has contrast at actual number and dot positions',
    () async {
      final bytes = await rootBundle.load('assets/images/tile_base.png');
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      final source = (await codec.getNextFrame()).image;
      codec.dispose();
      // Classic is intentionally unchanged and uses its original yellow contour.
      for (final palette in TileThemePalette.all.where(
        (p) => p.id != TileThemeId.porcelain,
      )) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawImageRect(
          source,
          Rect.fromLTWH(
            0,
            0,
            source.width.toDouble(),
            source.height.toDouble(),
          ),
          const Rect.fromLTWH(0, 0, 90, 118),
          Paint()..colorFilter = palette.filter,
        );
        TileSurfaceFx(
          size: Vector2(90, 118),
          position: Vector2.zero(),
        ).renderDecoration(canvas);
        final picture = recorder.endRecording();
        final image = await picture.toImage(90, 118);
        final rgba = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        for (final point in [
          const Offset(30, 40),
          const Offset(45, 40),
          const Offset(60, 40),
          const Offset(45, 84),
        ]) {
          final index = (point.dy.toInt() * 90 + point.dx.toInt()) * 4;
          final background = Color.fromARGB(
            255,
            rgba.getUint8(index),
            rgba.getUint8(index + 1),
            rgba.getUint8(index + 2),
          );
          for (final (color, blind) in [
            for (final color in TileColor.values) (color, false),
            (TileColor.yellow, true),
          ]) {
            final ink = palette.ink(color, colorBlind: blind);
            final edge = palette.inkOutline(color, colorBlind: blind);
            final a = ink.computeLuminance(),
                b = (edge ?? background).computeLuminance();
            final ratio = a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason: '${palette.name} $ink at $point',
            );
          }
        }
        image.dispose();
        picture.dispose();
      }
      source.dispose();
    },
  );

  testWidgets(
    'existing settings opens theme selector and returns without losing preferences',
    (tester) async {
      await settings.scene(tester, const Size(640, 360), false, []);
      await tester.tap(find.text('Taş Temaları'));
      await tester.pumpAndSettle();
      expect(find.byType(TileThemesDialog), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tile-theme-gold')));
      await tester.pumpAndSettle();
      expect(TileThemeService.selected.value, TileThemeId.gold);
      await tester.tap(find.byTooltip('Kapat').last);
      await tester.pumpAndSettle();
      expect(find.byType(TileThemesDialog), findsNothing);
      expect(find.byKey(const ValueKey('setting-Ses')), findsOneWidget);
    },
  );

  test(
    'six distinct palettes, unchanged classic, readable and distinct inks',
    () {
      expect(
        TileThemePalette.of(TileThemeId.gold).surface,
        const Color(0xFFC69A24),
      );
      expect(
        TileThemePalette.of(TileThemeId.gold).shadow,
        const Color(0xFF594009),
      );
      expect(
        TileThemePalette.of(TileThemeId.pink).surface,
        const Color(0xFFE78FB5),
      );
      expect(
        TileThemePalette.of(TileThemeId.pink).shadow,
        const Color(0xFF71304F),
      );
      expect(TileThemePalette.all.length, 6);
      expect(TileThemePalette.all.first.filter, isNull);
      expect(
        TileThemePalette.all.first.ink(TileColor.red),
        const Color(0xFFD12B3F),
      );
      for (final p in TileThemePalette.all) {
        expect(p.inks.toSet().length, 4);
        for (final color in TileColor.values) {
          final a = p.ink(color).computeLuminance();
          final b = (p.inkOutline(color) ?? p.surface).computeLuminance();
          final contrast = (a > b
              ? (a + .05) / (b + .05)
              : (b + .05) / (a + .05));
          expect(
            contrast,
            greaterThanOrEqualTo(p.dark ? 4.5 : 3),
            reason: '${p.name} $color',
          );
        }
        expect(
          p.ink(TileColor.yellow, colorBlind: true),
          isNot(p.ink(TileColor.yellow)),
        );
      }
    },
  );

  test(
    'selection survives reload, invalid preferences fall back, rapid writes preserve latest',
    () async {
      await TileThemeService.load();
      expect(TileThemeService.selected.value, TileThemeId.porcelain);
      await Future.wait([
        TileThemeService.select(TileThemeId.midnight),
        TileThemeService.select(TileThemeId.burgundy),
        TileThemeService.select(TileThemeId.pink),
      ]);
      TileThemeService.selected.value = TileThemeId.porcelain;
      await TileThemeService.load();
      expect(TileThemeService.selected.value, TileThemeId.pink);
      final prefs = await SharedPreferences.getInstance();
      for (final legacy in {
        'champagne': TileThemeId.emerald,
        'anthracite': TileThemeId.gold,
        'lavender': TileThemeId.pink,
        'turquoise': TileThemeId.gold,
        'copper': TileThemeId.pink,
      }.entries) {
        await prefs.setString(TileThemeService.preferenceKey, legacy.key);
        await TileThemeService.load();
        expect(TileThemeService.selected.value, legacy.value);
      }
      await prefs.setString(TileThemeService.preferenceKey, 'unknown');
      await TileThemeService.load();
      expect(TileThemeService.selected.value, TileThemeId.porcelain);
    },
  );

  for (final size in [
    const Size(480, 270),
    const Size(568, 320),
    const Size(844, 390),
  ]) {
    testWidgets(
      'six real asset previews and selection fit landscape $size with safe areas',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'Montserrat'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: const EdgeInsets.symmetric(horizontal: 44),
                textScaler: const TextScaler.linear(1.3),
              ),
              child: child!,
            ),
            home: const Scaffold(
              body: RepaintBoundary(
                key: ValueKey('theme-capture'),
                child: TileThemesDialog(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(TileThemePreview), findsNWidgets(6));
        expect(find.byType(Image), findsNWidgets(24));
        if (size.width == 844) {
          await expectLater(
            find.byKey(const ValueKey('theme-capture')),
            matchesGoldenFile('goldens/tile_themes_844x390.png'),
          );
        }
        for (final theme in TileThemeId.values) {
          final item = find.byKey(ValueKey('tile-theme-${theme.name}'));
          expect(tester.getRect(item).bottom, lessThan(size.height));
          await tester.tap(item);
          await tester.pumpAndSettle();
          expect(TileThemeService.selected.value, theme);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'live tiles change palette without changing model, slots, joker state or movement',
    (tester) async {
      final game = await fixture.mount(tester);
      final tiles = [
        for (final c in TileColor.values)
          TileComponent(
            tile: TileModel(id: c.name, value: 8, color: c),
            position: Vector2(150, 150),
          ),
      ];
      final joker = fixture.visual('joker', joker: true);
      final fake = fixture.visual('fake', fake: true);
      final indicator = IndicatorComponent(
        tile: const TileModel(id: 'indicator', value: 9, color: TileColor.blue),
        position: Vector2(220, 150),
      );
      game.world.addAll([...tiles, joker, fake, indicator]);
      await fixture.settle(tester, game);
      final first = tiles.first;
      final surface = first.children.whereType<TileSurfaceFx>().single;
      first.currentSlotIndex = 7;
      final effect = MoveEffect.to(
        Vector2(300, 150),
        EffectController(duration: 10),
      );
      first.add(effect);
      await tester.pump();
      for (final palette in TileThemePalette.all) {
        await TileThemeService.select(palette.id);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        for (final tile in tiles) {
          expect(
            (tile.numberText.textRenderer as TextPaint).style.color,
            palette.ink(tile.color),
          );
          expect(
            tile.children.whereType<TileGemBadge>().single.coreColor,
            palette.ink(tile.color),
          );
          expect(tile.size, Vector2(90, 118));
          expect(tile.tile.value, 8);
          expect(
            tile.children.whereType<TextComponent>().length,
            tile.color == TileColor.yellow ? 1 : 2,
          );
        }
        expect(first.currentSlotIndex, 7);
        expect(first.children.contains(effect), isTrue);
        expect(first.children.whereType<TileSurfaceFx>().single, same(surface));
        expect(joker.isFaceDown, isTrue);
        expect(joker.children.contains(joker.backSprite), isTrue);
        expect(
          joker.backSprite.paint.colorFilter,
          palette.id == TileThemeId.porcelain ? isNull : isNotNull,
        );
        expect(fake.children.whereType<StarComponent>(), hasLength(1));
        final indicatorInk =
            (indicator.children.whereType<TextComponent>().single.textRenderer
                    as TextPaint)
                .style
                .color;
        if (palette.id != TileThemeId.porcelain) {
          expect(indicatorInk, palette.ink(TileColor.blue));
        }
        expect(
          indicator.children
              .whereType<CircleComponent>()
              .where((dot) => dot.radius == 10)
              .single
              .paint
              .color
              .toARGB32(),
          indicatorInk!.toARGB32(),
        );
      }
      final changes = [
        TileThemeService.select(TileThemeId.midnight),
        TileThemeService.select(TileThemeId.burgundy),
        TileThemeService.select(TileThemeId.pink),
      ];
      await Future.wait(changes);
      await tester.pump();
      expect(
        (first.numberText.textRenderer as TextPaint).style.color,
        TileThemePalette.of(TileThemeId.pink).ink(first.color),
      );
      UserState.colorBlindMode = true;
      TileThemeService.selected.refreshPresentation();
      await tester.pump();
      expect(
        (tiles.last.numberText.textRenderer as TextPaint).style.color,
        TileThemeService.palette.ink(TileColor.yellow, colorBlind: true),
      );
      UserState.colorBlindMode = false;
      TileThemeService.selected.refreshPresentation();
      first.removeFromParent();
      await tester.pump();
      await TileThemeService.select(TileThemeId.midnight);
      await tester.pump();
      expect(tester.takeException(), isNull);
      game.world.removeAll([...tiles.skip(1), joker, fake, indicator]);
      await tester.pump();
      // Inspect listener disposal without exposing test-only production APIs.
      // ignore: invalid_use_of_protected_member
      expect(TileThemeService.selected.hasListeners, isFalse);
    },
  );
}
