import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/lobby/lobby_columns.dart';
import 'package:okeyix/ui/lobby/lobby_league_list.dart';
import 'package:okeyix/ui/lobby/lobby_bottom_dock.dart';
import 'package:okeyix/ui/lobby/LobbyTableWheel.dart';
import 'package:okeyix/widgets/create_button.dart';

const sizes = [
  Size(640, 360),
  Size(800, 360),
  Size(844, 390),
  Size(932, 430),
  Size(1024, 600),
];
final leagues = List.generate(
  5,
  (i) => <String, dynamic>{
    'id': 'l$i',
    'name': ['Acemiler', 'Çıraklar', 'Kalfalar', 'Ustalar', 'Şampiyonlar'][i],
    'min_coin': i * 10000,
    'min_rating': i * 1000,
  },
);
Map<String, dynamic> table(String status) => {
  'id': 'live',
  'max_players': 2,
  'status': status,
  'spectators_enabled': true,
  'entry_coin': 2500,
  'round_count': 3,
  'pot_amount': 5000,
  'turn_seconds': 20,
  '_players': [
    {
      'seat_index': 0,
      'user_id': 'a',
      'username': 'Deniz',
      'avatar_url': 'assets/images/avatars/avatar1.png',
    },
    if (status == 'playing')
      {'seat_index': 1, 'user_id': 'b', 'username': 'Ece'},
  ],
};
Future<void> lobby(
  WidgetTester tester,
  Size size,
  double scale,
  List<String> calls, {
  String state = 'playing',
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Montserrat'),
      builder: (context, child) => RepaintBoundary(
        key: const ValueKey('capture'),
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
            viewPadding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        ),
      ),
      home: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/lobby/lobby.png',
                fit: BoxFit.cover,
              ),
            ),
            const Positioned.fill(child: ColoredBox(color: Color(0x66060F14))),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  const SizedBox(height: 7),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: LobbyColumns(
                        leagues: Padding(
                          padding: const EdgeInsets.all(8),
                          child: LobbyLeagueList(
                            leagues: leagues,
                            selectedLeagueId: 'l0',
                            leagueActivePlayers: {
                              for (var i = 0; i < 5; i++) 'l$i': 24 + i,
                            },
                            leagueActiveTables: {
                              for (var i = 0; i < 5; i++) 'l$i': 12 + i,
                            },
                            onSelect: (l) => calls.add(l['id']),
                            userCoin: 10000,
                            userRating: 1200,
                            loading: false,
                          ),
                        ),
                        tables: LobbyTableWheel(
                          tables: state == 'empty' ? [] : [table(state)],
                          blockedUserIds: const {},
                          onJoin: (_) => calls.add('join'),
                          onSpectate: (_) => calls.add('spectate'),
                          canSpectateAll: true,
                          onUserTap: (_) => calls.add('user'),
                          onRefresh: () async {
                            calls.add('refresh');
                          },
                          loading: state == 'loading',
                          isLocked: state == 'locked',
                          lockedLeague: leagues.last,
                          playerCoin: 10000,
                          playerRating: 1200,
                          onCreateTable: () async {
                            calls.add('create');
                          },
                        ),
                      ),
                    ),
                  ),
                  LobbyBottomDock(
                    left: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final id in ['menu', 'profile', 'balance'])
                          TextButton(
                            key: ValueKey(id),
                            onPressed: () => calls.add(id),
                            child: Text(
                              {
                                'menu': '☰',
                                'profile': 'Deniz · Lv.12',
                                'balance': '25.000 coin',
                              }[id]!,
                              style: const TextStyle(color: Color(0xFFEAD6A7)),
                            ),
                          ),
                      ],
                    ),
                    center: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 60,
                          height: 60,
                          child: FittedBox(
                            child: CreateButton(
                              onTap: () => calls.add('create'),
                            ),
                          ),
                        ),
                        const SizedBox(
                          height: 12,
                          child: FittedBox(
                            child: Text(
                              'MASA AÇ',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    right: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final entry in {
                          'store': Icons.shopping_bag_outlined,
                          'cup': Icons.emoji_events_outlined,
                          'friends': Icons.people_outline,
                          'messages': Icons.mail_outline,
                        }.entries)
                          IconButton(
                            key: ValueKey(entry.key),
                            onPressed: () => calls.add(entry.key),
                            icon: Icon(
                              entry.value,
                              color: const Color(0xFFEAD6A7),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 450));
}

void main() {
  setUpAll(() async {
    final font = FontLoader('Montserrat')
      ..addFont(rootBundle.load('assets/fonts/Montserrat-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Montserrat-Bold.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await Future.wait([font.load(), icons.load()]);
  });
  for (final size in sizes) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('lobby $size scale $scale selection spectate and dock', (
        tester,
      ) async {
        final calls = <String>[];
        await lobby(tester, size, scale, calls);
        expect(tester.takeException(), isNull);
        final leagueArea = tester.getRect(find.byType(LobbyLeagueList));
        final cards = [
          for (var i = 0; i < 5; i++)
            tester.getRect(find.byKey(ValueKey('league-l$i'))),
        ];
        for (final card in cards) {
          expect(leagueArea.contains(card.topLeft), isTrue);
          expect(card.bottom, lessThanOrEqualTo(leagueArea.bottom + .01));
          expect(card.right, lessThanOrEqualTo(leagueArea.right + .01));
        }
        expect(cards[0].top, closeTo(cards[1].top, .01));
        expect(cards[2].top, closeTo(cards[3].top, .01));
        expect(cards[2].top, greaterThan(cards[0].bottom));
        expect(cards[4].top, greaterThan(cards[2].bottom));
        expect(cards[4].left, closeTo(cards[0].left, .01));
        expect(cards[4].right, closeTo(cards[1].right, .01));
        expect(
          find.descendant(
            of: find.byType(LobbyLeagueList),
            matching: find.byType(Scrollable),
          ),
          findsNothing,
        );
        final spectate = find.byKey(const ValueKey('spectate-live'));
        await tester.tap(spectate);
        expect(calls, contains('spectate'));
        await tester.tap(find.text('Deniz').first);
        expect(calls, contains('user'));
        await tester.tap(find.byKey(const ValueKey('league-l4')));
        expect(
          calls,
          contains('l4'),
        ); // locked selection must still reach existing rules
        for (final id in [
          'menu',
          'profile',
          'balance',
          'store',
          'cup',
          'friends',
          'messages',
        ]) {
          final target = find.byKey(ValueKey(id));
          final rect = tester.getRect(target);
          expect(rect.bottom, lessThanOrEqualTo(size.height - 20));
          await tester.tap(target);
          expect(calls, contains(id));
        }
        await tester.tap(find.byType(CreateButton));
        expect(calls, contains('create'));
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final state in ['loading', 'empty', 'locked', 'waiting']) {
    testWidgets('small lobby $state state', (tester) async {
      final calls = <String>[];
      await lobby(tester, const Size(640, 360), 2, calls, state: state);
      expect(tester.takeException(), isNull);
      if (state == 'waiting') {
        await tester.tap(find.byIcon(Icons.login_rounded).first);
        expect(calls, contains('join'));
      }
    });
  }
  for (final size in [const Size(640, 360), const Size(932, 430)]) {
    testWidgets('lobby component golden $size', (tester) async {
      await lobby(tester, size, 1, []);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile(
          'goldens/lobby_${size.width.toInt()}x${size.height.toInt()}.png',
        ),
      );
    });
  }
}
