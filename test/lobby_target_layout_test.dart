import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/lobby/lobby_columns.dart';
import 'package:okeyix/ui/lobby/lobby_league_list.dart';
import 'package:okeyix/ui/lobby/lobby_metal_surface.dart';
import 'package:okeyix/ui/lobby/lobby_micro_motion.dart';
import 'package:okeyix/ui/lobby/quick_play_panel.dart';
import 'package:okeyix/ui/lobby/LobbyTableWheel.dart';
import 'package:okeyix/ui/lobby/lobby_bottom_dock.dart';

void main() {
  setUpAll(() async {
    await Future.wait([
      (FontLoader('Montserrat')
            ..addFont(rootBundle.load('assets/fonts/Montserrat-Regular.ttf'))
            ..addFont(rootBundle.load('assets/fonts/Montserrat-Bold.ttf')))
          .load(),
      (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load(),
    ]);
  });
  for (final size in [
    const Size(480, 270),
    const Size(568, 320),
    const Size(844, 390),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'wood lobby $size scale $scale keeps actions and all tables',
        (tester) async {
          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final calls = <String>[];
          final tables = List.generate(
            8,
            (i) => <String, dynamic>{
              'id': 't$i',
              'status': i == 0 ? 'waiting' : 'playing',
              'is_fake': i > 1,
              'entry_coin': 1000,
              'pot_amount': i * 1000,
              'round_count': i + 1,
              '_players': List.generate(
                i == 0 ? 1 : 2,
                (j) => {
                  'seat_index': j,
                  'user_id': '$i-$j',
                  'username': 'Çok Uzun Oyuncu Adı $i',
                },
              ),
            },
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(fontFamily: 'Montserrat'),
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(scale),
                  padding: const EdgeInsets.fromLTRB(24, 0, 20, 12),
                  disableAnimations: true,
                ),
                child: Scaffold(
                  body: SafeArea(
                    child: Column(
                      children: [
                        const SizedBox(height: 7),
                        Expanded(
                          child: LobbyColumns(
                            leagues: Padding(
                              padding: const EdgeInsets.fromLTRB(9, 9, 9, 8),
                              child: Column(
                                children: [
                                  const SizedBox(
                                    height: 40,
                                    child: LobbyMotto(),
                                  ),
                                  const SizedBox(height: 10),
                                  Expanded(
                                    child: LobbyLeagueList(
                                      leagues: [
                                        for (final (i, name) in [
                                          'Acemiler',
                                          'Çıraklar',
                                          'Kalfalar',
                                          'Ustalar',
                                          'Şampiyonlar',
                                        ].indexed)
                                          {'id': '$i', 'name': name},
                                      ],
                                      selectedLeagueId: '0',
                                      leagueActivePlayers: const {},
                                      leagueActiveTables: const {'0': 8},
                                      onSelect: (_) => calls.add('league'),
                                      userCoin: 10000,
                                      userRating: 1000,
                                      loading: false,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            tables: Padding(
                              padding: const EdgeInsets.only(top: 9, bottom: 8),
                              child: Column(
                                children: [
                                  LobbyQuickPlayBar(
                                    onPlay: () => calls.add('play'),
                                    guestControl: TextButton(
                                      onPressed: () => calls.add('link'),
                                      child: const Text('Misafir modu · Bağla'),
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  LobbyLiveIndicator(tables: tables),
                                  const SizedBox(height: 3),
                                  Expanded(
                                    child: LobbyTableWheel(
                                      tables: tables,
                                      blockedUserIds: const {},
                                      onJoin: (_) => calls.add('join'),
                                      onSpectate: (_) => calls.add('watch'),
                                      onUserTap: (_) => calls.add('profile'),
                                      canSpectateAll: true,
                                      onRefresh: () async {},
                                      loading: false,
                                      playerCoin: 10000,
                                      playerRating: 1000,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        LobbyBottomDock(
                          left: const Text('Oyuncu · Seviye 3 · 125 Bin'),
                          center: LobbyDockCreate(
                            onTap: () => calls.add('create'),
                          ),
                          right: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final (i, name) in [
                                'Oyunlarımız',
                                'Mağaza',
                                'Davet',
                                'Sıralama',
                                'Arkadaşlar',
                                'Mesajlar',
                              ].indexed) ...[
                                if (i > 0) const LobbyDockDivider(),
                                LobbyDockAction(
                                  label: name,
                                  icon: Icons.star,
                                  badgeCount: i == 1 ? 4 : null,
                                  onTap: () => calls.add(name),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const ValueKey('quick-play')));
          await tester.tap(find.text('Misafir modu · Bağla'));
          await tester.tap(find.text('MASA AÇ'));
          await tester.tap(find.byKey(const ValueKey('seat-t0-1')));
          await tester.tap(find.text('Mağaza'));
          expect(calls, ['play', 'link', 'create', 'join', 'Mağaza']);
          await tester.drag(
            find.byKey(const ValueKey('vertical-tables')),
            const Offset(0, -700),
          );
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('t7')), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
