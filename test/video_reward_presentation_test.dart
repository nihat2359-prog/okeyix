import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/reward_dialogs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final text = FontLoader('Montserrat')
      ..addFont(rootBundle.load('assets/fonts/Montserrat-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Montserrat-Bold.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await Future.wait([text.load(), icons.load()]);
  });
  test(
    'video reward art has genuine transparency and mobile-sized dimensions',
    () async {
      final file = File('assets/images/coins/video_reward_coins_v2.png');
      final bytes = await file.readAsBytes();
      expect(bytes.length, lessThan(1100000));
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      expect(image.width, 960);
      expect(image.height, 640);
      final rgba = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      expect(rgba.getUint8(3), 0);
      expect(rgba.getUint8((image.width - 1) * 4 + 3), 0);
      image.dispose();
      codec.dispose();
    },
  );

  for (final size in [const Size(568, 320), const Size(844, 390)]) {
    testWidgets('video reward tabletop presentation at $size', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final claim = Completer<bool>();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            fontFamily: 'Montserrat',
            scaffoldBackgroundColor: const Color(0xFF071D18),
          ),
          builder: (context, child) => RepaintBoundary(
            key: const ValueKey('video-capture'),
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                viewPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
              child: child!,
            ),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => RewardedVideoDialog(
                      onSound: (_) {},
                      onClaim: () => claim.future,
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        final context = tester.element(find.byType(Scaffold));
        await Future.wait([
          precacheImage(const AssetImage('assets/images/table.png'), context),
          precacheImage(
            const AssetImage('assets/images/coins/video_reward_coins_v2.png'),
            context,
          ),
        ]);
      });
      await tester.tap(find.text('open'));
      // This also verifies that the tabletop artwork has no looping float animation.
      await tester.pumpAndSettle();
      final art = find.byKey(const ValueKey('video-reward-art'));
      final asset = tester.widget<Image>(art).image as AssetImage;
      expect(asset.assetName, 'assets/images/coins/video_reward_coins_v2.png');
      expect(find.text('+ 15 Bin'), findsOneWidget);
      for (final key in ['reward-action', 'reward-close']) {
        final bounds = tester.getRect(find.byKey(ValueKey(key)));
        expect(bounds.left, greaterThanOrEqualTo(16));
        expect(bounds.right, lessThanOrEqualTo(size.width - 16));
        expect(bounds.bottom, lessThanOrEqualTo(size.height - 8));
      }
      final restingBounds = tester.getRect(art);
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.getRect(art), restingBounds);
      await expectLater(
        find.byKey(const ValueKey('video-capture')),
        matchesGoldenFile('goldens/video_reward_${size.width.toInt()}.png'),
      );
      await tester.tap(find.byKey(const ValueKey('reward-action')));
      await tester.pump();
      claim.complete(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.getRect(art), restingBounds);
      await tester.pumpAndSettle();
      expect(tester.getRect(art), restingBounds);
      expect(find.text('Harika! Kazandın.'), findsOneWidget);
      expect(find.text('Masaya dön'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
