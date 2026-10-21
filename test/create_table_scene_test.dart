import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/lobby/create_table_scene.dart';

class Draft {
  final stakes = [100, 200, 400, 800, 1600, 3200];
  int selected = 0, speed = 20, created = 0, closed = 0;
  bool spectator = true, chat = true;
}

Future<void> scene(
  WidgetTester tester,
  Size size,
  Draft draft, {
  double scale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Montserrat'),
      home: RepaintBoundary(
        key: const ValueKey('create-capture'),
        child: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
            padding: const EdgeInsets.fromLTRB(59, 0, 44, 21),
            viewPadding: const EdgeInsets.fromLTRB(59, 0, 44, 21),
          ),
          child: SafeArea(
            child: Scaffold(
              backgroundColor: const Color(0xFF071210),
              body: DecoratedBox(
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('assets/images/lobby/lobby.png'),
                    fit: BoxFit.cover,
                  ),
                ),
                child: StatefulBuilder(
                  builder: (context, refresh) => CreateTableScene(
                    leagueName: 'Şampiyonlar',
                    stakes: draft.stakes,
                    selectedIndex: draft.selected,
                    turnSeconds: draft.speed,
                    spectator: draft.spectator,
                    chat: draft.chat,
                    canCreate: draft.stakes[draft.selected] <= 1000,
                    formatStake: (n) => '$n',
                    onStake: (n) => refresh(() => draft.selected = n),
                    onSpeed: (n) => refresh(() => draft.speed = n),
                    onSpectator: () =>
                        refresh(() => draft.spectator = !draft.spectator),
                    onChat: () => refresh(() => draft.chat = !draft.chat),
                    onCreate: () => draft.created++,
                    onClose: () => draft.closed++,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('real dialog route preserves the backdrop through its face', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(932, 430));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final capture = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Stack(
                fit: StackFit.expand,
                children: [
                  const Positioned.fill(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: ColoredBox(color: Color(0xFFFF0000))),
                        Expanded(child: ColoredBox(color: Color(0xFF0000FF))),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      barrierColor: const Color(0x33020507),
                      builder: (_) => CreateTableScene(
                        leagueName: 'Acemiler',
                        stakes: const [1000, 2000, 4000],
                        selectedIndex: 0,
                        turnSeconds: 20,
                        spectator: true,
                        chat: true,
                        canCreate: true,
                        formatStake: (n) => '$n',
                        onStake: (_) {},
                        onSpeed: (_) {},
                        onSpectator: () {},
                        onChat: () {},
                        onCreate: () {},
                        onClose: () {},
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final data = await tester.runAsync(() async {
      final image =
          await (capture.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1);
      try {
        return await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      } finally {
        image.dispose();
      }
    });
    final left = (240 * 932 + 70) * 4, right = (240 * 932 + 862) * 4;
    // The darker face requested for readability still preserves the backdrop.
    expect(data!.getUint8(left) - data.getUint8(left + 2), greaterThan(15));
    expect(data.getUint8(right + 2) - data.getUint8(right), greaterThan(15));
    expect(tester.takeException(), isNull);
  });
  setUpAll(() async {
    await (FontLoader('Montserrat')
          ..addFont(rootBundle.load('assets/fonts/Montserrat-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Montserrat-Bold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final size in [
    const Size(568, 320),
    const Size(640, 360),
    const Size(800, 360),
    const Size(844, 390),
    const Size(932, 430),
    const Size(1024, 600),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        '$size scale $scale controls and fixed actions stay accessible',
        (tester) async {
          final draft = Draft();
          await scene(tester, size, draft, scale: scale);
          expect(
            find.descendant(
              of: find.byType(CreateTableScene),
              matching: find.byType(Image),
            ),
            findsNothing,
          );
          expect(
            tester
                .getRect(find.byKey(const ValueKey('create-confirm')))
                .center
                .dx,
            closeTo(tester.getRect(find.byType(Dialog)).center.dx, .5),
          );
          for (final key in [
            'create-confirm',
            'create-close',
            'speed-fast',
            'speed-normal',
            'setting-spectator',
            'setting-chat',
            'stake-0',
            'stake-5',
          ]) {
            expect(find.byKey(ValueKey(key)).hitTestable(), findsOneWidget);
            final rect = tester.getRect(find.byKey(ValueKey(key)));
            expect(rect.bottom, lessThanOrEqualTo(size.height - 21));
          }
          await tester.tap(find.byKey(const ValueKey('speed-fast')));
          await tester.pumpAndSettle();
          expect(draft.speed, 15);
          expect(find.text('2 OYUNCU · 15 SN'), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('setting-chat')));
          await tester.tap(find.byKey(const ValueKey('setting-spectator')));
          expect(draft.chat, false);
          expect(draft.spectator, false);
          await tester.tap(find.byKey(const ValueKey('create-confirm')));
          expect(draft.created, 1);
          await tester.tap(find.byKey(const ValueKey('create-close')));
          expect(draft.closed, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('all stakes fit without arrows; low coins still disable create', (
    tester,
  ) async {
    final draft = Draft();
    draft.stakes.addAll([6400, 12800, 25600, 51200]);
    await scene(tester, const Size(640, 360), draft);
    expect(find.byKey(const ValueKey('stake-next')), findsNothing);
    expect(find.byKey(const ValueKey('stake-previous')), findsNothing);
    for (var i = 0; i < draft.stakes.length; i++) {
      expect(find.byKey(ValueKey('stake-$i')).hitTestable(), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('stake-9')));
    await tester.pumpAndSettle();
    expect(draft.selected, 9);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('preview-stake'))).data,
      '51200',
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('create-confirm')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('create-confirm')));
    expect(draft.created, 0);
  });
  for (final size in [const Size(640, 360), const Size(932, 430)]) {
    testWidgets('preparation scene golden $size', (tester) async {
      await scene(tester, size, Draft());
      await expectLater(
        find.byKey(const ValueKey('create-capture')),
        matchesGoldenFile(
          'goldens/create_${size.width.toInt()}x${size.height.toInt()}.png',
        ),
      );
    });
  }
}
