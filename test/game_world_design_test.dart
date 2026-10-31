import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/screens/pisti_lobby_screen.dart';
import 'package:okeyix/screens/pisti_table_screen.dart';
import 'package:okeyix/ui/pisti_invite_window.dart';
import 'package:okeyix/ui/game_invite_dialog.dart';
import 'package:okeyix/ui/lobby/lobby_avatar.dart';
import 'pisti_online_test.dart' as fixtures;

void main() {
  setUpAll(() async {
    final configFile = File('.dart_tool/package_config.json');
    final packages =
        jsonDecode(configFile.readAsStringSync())['packages'] as List;
    final flutter = packages.firstWhere((p) => p['name'] == 'flutter');
    final rawRoot = flutter['rootUri'] as String;
    final flutterPackage = configFile.absolute.uri.resolve(
      rawRoot.endsWith('/') ? rawRoot : '$rawRoot/',
    );
    final font = FontLoader('Montserrat')
      ..addFont(rootBundle.load('assets/fonts/Montserrat-Regular.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File(
              flutterPackage
                  .resolve(
                    '../../bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
                  )
                  .toFilePath(),
            ).readAsBytesSync(),
          ),
        ),
      );
    await icons.load();
  });
  for (final size in [
    const Size(844, 390),
    const Size(568, 280),
    const Size(640, 320),
  ]) {
    testWidgets('Pişti Molası and windows ${size.width.toInt()}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      Widget host(Widget child) => RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Montserrat'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(size.width == 640 ? 1.3 : 1),
            ),
            child: child!,
          ),
          home: child,
        ),
      );
      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          for (final element in find.byType(Image).evaluate()) {
            await precacheImage((element.widget as Image).image, element);
          }
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: name);
        await expectLater(
          find.byKey(boundary),
          matchesGoldenFile(
            'goldens/game_world_${name}_${size.width.toInt()}.png',
          ),
        );
      }

      final service = fixtures.FakePistiService();
      await tester.pumpWidget(host(PistiLobbyScreen(service: service)));
      await capture('lobby');
      expect(find.text('Botla Oyna'), findsNWidgets(2));
      expect(find.text('Arkadaşımla Oyna'), findsNWidgets(2));
      expect(find.text('Masa oluştur'), findsNothing);
      for (final state in ['waiting', 'playing', 'finished']) {
        final c = fixtures.StaticController(service, status: state);
        c.snapshot!['room']['casual'] = true;
        c.snapshot!['room']['entry_coin'] = 0;
        await tester.pumpWidget(
          host(
            PistiTableScreen(
              key: ValueKey(state),
              roomId: 'local-room',
              controller: c,
            ),
          ),
        );
        await capture(state);
        if (state == 'playing') {
          await tester.tap(find.byTooltip('Kurallar ve el puanları'));
          await capture('rules');
          await tester.tap(find.text('Masaya dön'));
          await tester.pumpAndSettle();
          await tester.tap(find.byIcon(Icons.exit_to_app));
          await capture('leave');
          await tester.tap(find.text('Oyuna dön'));
          await tester.pumpAndSettle();
        }
      }
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showPistiInviteWindow(context),
                  child: const Text('Aç'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Aç'));
      await capture('invite');
      await tester.tap(find.text('Reddet'));
      await tester.pumpAndSettle();
      final waiting = fixtures.StaticController(service, status: 'waiting');
      waiting.snapshot!['room'] = Map<String, dynamic>.from(
        waiting.snapshot!['room'] as Map,
      );
      waiting.snapshot!['room']['seats'] = [
        waiting.snapshot!['room']['seats'][0],
      ];
      waiting.snapshot!['room']['owner_id'] = null;
      await tester.pumpWidget(
        host(
          PistiTableScreen(
            key: const ValueKey('one-seat'),
            roomId: 'local-room',
            controller: waiting,
          ),
        ),
      );
      await capture('bot_waiting');
      expect(find.text('Botla oyna'), findsNothing);
      expect(find.text('Oyuncu davet et'), findsOneWidget);
      waiting.error =
          'Bu masaya katılmak için yeterli Coin yok. Ortak bakiyeni mağazadan tamamlayabilirsin.';
      await tester.pumpWidget(
        host(
          PistiTableScreen(
            key: const ValueKey('one-seat'),
            roomId: 'local-room',
            controller: waiting,
          ),
        ),
      );
      await capture('waiting_error');
      await tester.pumpWidget(
        host(
          PistiLobbyScreen(
            key: const ValueKey('listed'),
            service: GalleryPistiService(),
          ),
        ),
      );
      await capture('tables');
      await tester.tap(find.text('Arkadaşının Pişti daveti').first);
      await capture('lobby_invite');
      await tester.tap(find.text('Reddet'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  child: const Text('Arkadaş davet et'),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => GameInviteDialog(
                      invitationHint: 'İki kişilik Pişti masası',
                      loadPlayers: () async => [
                        {
                          'id': 'friend',
                          'username': 'Deniz',
                          'is_online': true,
                        },
                      ],
                      onInvite: (_) async {},
                      avatarBuilder: (url, name) =>
                          LobbyAvatar(username: name, avatarUrl: url, size: 22),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Arkadaş davet et'));
      await capture('friend_picker');
      await tester.pumpWidget(const SizedBox.shrink());
      final closed = fixtures.StaticController(service, status: 'waiting');
      closed.snapshot!['room']['status'] = 'closed';
      await tester.pumpWidget(
        host(
          PistiTableScreen(
            key: const ValueKey('closed-room'),
            roomId: 'local-room',
            controller: closed,
          ),
        ),
      );
      await capture('closed');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  test('login returns to Okey and invitations bypass selection', () {
    final main = File('lib/main.dart').readAsStringSync();
    final login = File('lib/screens/login_screen.dart').readAsStringSync();
    expect(login, contains('const LobbyScreen()'));
    expect(main, contains('const LobbyScreen()'));
    final routing = main.substring(
      main.indexOf('Future<void> _handlePushTapData'),
      main.indexOf(
        'Widget build(BuildContext context)',
        main.indexOf('Future<void> _handlePushTapData'),
      ),
    );
    expect(routing, contains('PistiLobbyScreen'));
    expect(routing, contains('OkeyGameScreen'));
    expect(routing, isNot(contains('GameCentre')));
    final okey = File('lib/screens/okey_game_screen.dart').readAsStringSync();
    expect(okey, contains('LobbyScreen()'));
  });
}

class GalleryPistiService extends fixtures.FakePistiService {
  @override
  Future<Map<String, dynamic>> lobby() async => {
    ...await super.lobby(),
    'rooms': [
      fixtures.fixture(status: 'waiting')['room'],
      fixtures.fixture(status: 'playing')['room'],
    ],
    'invites': [
      {'id': 'invite', 'table_id': 'local-room'},
    ],
  };
}
