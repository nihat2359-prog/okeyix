import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/lobby/lobby_side_menu.dart';
import 'package:okeyix/ui/lobby/lobby_bottom_dock.dart';
import 'package:okeyix/ui/lobby/_ui_helpers.dart';
import 'package:okeyix/screens/game_rules_screen.dart';

const sizes = [
  Size(640, 360),
  Size(800, 360),
  Size(844, 390),
  Size(932, 430),
  Size(1024, 600),
];

Future<void> scene(
  WidgetTester tester,
  Size size,
  double scale,
  List<String> calls,
) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  var open = false;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Montserrat'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          padding: const EdgeInsets.fromLTRB(44, 12, 24, 21),
          viewPadding: const EdgeInsets.fromLTRB(44, 12, 24, 21),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: RepaintBoundary(
          key: const ValueKey('menu-capture'),
          child: StatefulBuilder(
            builder: (context, update) => Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: Image.asset(
                    'assets/images/lobby/lobby.png',
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  left: 50,
                  bottom: 24,
                  child: LobbyDockAction(
                    label: 'Menü',
                    onTap: () => update(() => open = !open),
                    child: LobbyDockEmblem(
                      kind: LobbyDockEmblemKind.menu,
                      active: open,
                    ),
                  ),
                ),
                LobbySideMenu(
                  open: open,
                  onClose: () {
                    calls.add('close');
                    update(() => open = false);
                  },
                  onSupport: () => calls.add('support'),
                  onAnnouncements: () => calls.add('announcements'),
                  onProfileCard: () => calls.add('profile'),
                  onSettings: () => calls.add('settings'),
                  onLogout: () => calls.add('logout'),
                  menuButtonBuilder: lobbySideMenuButton,
                  goldBorderColor: const Color(0xCCB07A1A),
                  goldBorderWidth: .3,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byType(LobbyDockAction));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Montserrat',
    )..addFont(rootBundle.load('assets/fonts/Montserrat-Bold.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final size in sizes) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'menu $size scale $scale keeps logout fixed and callbacks intact',
        (tester) async {
          final calls = <String>[];
          await scene(tester, size, scale, calls);
          expect(find.byType(BackdropFilter), findsNothing);
          expect(
            tester.widget<LobbyDockEmblem>(find.byType(LobbyDockEmblem)).active,
            isTrue,
          );
          for (final item in {
            'Destek / Şikayet Gönder': 'support',
            'Sistem Duyuruları': 'announcements',
            'Profil Kartım': 'profile',
            'Ayarlar': 'settings',
          }.entries) {
            final target = find.byKey(ValueKey('menu-${item.key}'));
            expect(target.hitTestable(), findsOneWidget);
            await tester.tap(target);
            expect(calls, contains(item.value));
          }
          final logout = find.byKey(const ValueKey('menu-Çıkış Yap'));
          final rect = tester.getRect(logout);
          expect(rect.bottom, lessThanOrEqualTo(size.height - 21));
          expect(rect.left, greaterThanOrEqualTo(44));
          await tester.tap(logout);
          expect(calls, contains('logout'));
          await tester.tap(find.byKey(const ValueKey('menu-close')));
          await tester.pumpAndSettle();
          expect(find.text('Oyun Menüsü'), findsNothing);
          expect(
            tester.widget<LobbyDockEmblem>(find.byType(LobbyDockEmblem)).active,
            isFalse,
          );
          expect(tester.binding.transientCallbackCount, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('backdrop closes menu and guide retains its route', (
    tester,
  ) async {
    final calls = <String>[];
    await scene(tester, sizes.first, 1, calls);
    await tester.tapAt(const Offset(620, 180));
    await tester.pumpAndSettle();
    expect(calls, contains('close'));
    await tester.tap(find.byType(LobbyDockAction));
    await tester.pumpAndSettle();
    final guide = find.byKey(const ValueKey('menu-Oyun Rehberi'));
    expect(guide.hitTestable(), findsOneWidget);
    await tester.tap(guide);
    await tester.pumpAndSettle();
    expect(find.byType(GameRulesScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [sizes.first, sizes[3]]) {
    testWidgets('game menu golden $size', (tester) async {
      await scene(tester, size, 1, []);
      await expectLater(
        find.byKey(const ValueKey('menu-capture')),
        matchesGoldenFile(
          'goldens/menu_${size.width.toInt()}x${size.height.toInt()}.png',
        ),
      );
    });
  }
}
