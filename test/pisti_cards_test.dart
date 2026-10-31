import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/dev/pisti/pisti_cards.dart';
import 'package:okeyix/dev/pisti/pisti_model.dart';

void main() {
  test(
    'standard pip layouts have the exact rank, balanced columns and mirrored lower half',
    () {
      for (var rank = 1; rank <= 10; rank++) {
        final positions = pistiPipPositions(rank);
        expect(positions.length, rank);
        expect(positions.toSet().length, rank);
        expect(
          positions.every(
            (p) => p.dx >= .3 && p.dx <= .7 && p.dy >= .2 && p.dy <= .8,
          ),
          isTrue,
        );
        expect(
          positions.where((p) => p.dx < .5).length,
          positions.where((p) => p.dx > .5).length,
        );
      }
    },
  );
  testWidgets(
    'all 52 faces render, including twelve double-ended court illustrations',
    (tester) async {
      tester.view.physicalSize = const Size(1116, 544);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await (FontLoader(
        'Montserrat',
      )..addFont(rootBundle.load('assets/fonts/Montserrat-Bold.ttf'))).load();
      final capture = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: capture,
              child: ColoredBox(
                color: const Color(0xff162137),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      for (final suit in PistiSuit.values)
                        Expanded(
                          child: Row(
                            children: [
                              for (final rank in [
                                1,
                                2,
                                3,
                                4,
                                5,
                                6,
                                7,
                                8,
                                9,
                                10,
                                11,
                                12,
                                13,
                              ])
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: PistiCardView(
                                      card: PistiCard(suit, rank),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (Platform.environment['PISTI_CAPTURE_CARDS'] == '1') {
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final rendered = await boundary.toImage(pixelRatio: 1.5);
          final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/pisti_demo_captures').create(recursive: true);
          await File(
            'build/pisti_demo_captures/standard_52_cards.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          rendered.dispose();
        });
      }
    },
  );
}
