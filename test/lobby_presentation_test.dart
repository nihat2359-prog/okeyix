import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/lobby/lobby_columns.dart';
import 'package:okeyix/ui/lobby/lobby_league_list.dart';
import 'package:okeyix/ui/lobby/lobby_bottom_dock.dart';
import 'package:okeyix/ui/lobby/LobbyTableWheel.dart';

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
  EdgeInsets insets = const EdgeInsets.fromLTRB(24, 12, 24, 20),
  String selected = 'l0',
  List<Map<String, dynamic>>? openTables,
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
            padding: insets,
            viewPadding: insets,
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
                            selectedLeagueId: selected,
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
                          tables:
                              openTables ??
                              (state == 'empty' ? [] : [table(state)]),
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
                    center: LobbyDockCreate(onTap: () => calls.add('create')),
                    right: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final entry in {
                          'store': Icons.shopping_bag_outlined,
                          'cup': Icons.emoji_events_outlined,
                          'friends': Icons.people_outline,
                          'messages': Icons.mail_outline,
                        }.entries)
                          LobbyDockAction(
                            key: ValueKey(entry.key),
                            label: {
                              'store': 'Mağaza',
                              'cup': 'Sıralama',
                              'friends': 'Sosyal',
                              'messages': 'Mesajlar',
                            }[entry.key]!,
                            onTap: () => calls.add(entry.key),
                            emblem: {
                              'store': LobbyDockEmblemKind.store,
                              'cup': LobbyDockEmblemKind.ranking,
                              'friends': LobbyDockEmblemKind.social,
                              'messages': LobbyDockEmblemKind.messages,
                            }[entry.key],
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
  testWidgets(
    'game dock actions retain callbacks and settle without a repeating ticker',
    (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: LobbyBottomDock(
                left: LobbyDockAction(
                  label: 'Menü',
                  icon: Icons.menu_rounded,
                  onTap: () => calls.add('menu'),
                ),
                center: LobbyDockCreate(onTap: () => calls.add('create')),
                right: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final id in [
                      'Mağaza',
                      'Sıralama',
                      'Sosyal',
                      'Mesajlar',
                    ])
                      LobbyDockAction(
                        key: ValueKey(id),
                        label: id,
                        icon: Icons.star_outline,
                        onTap: () => calls.add(id),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      await tester.tap(find.byType(LobbyDockCreate));
      for (final id in ['Mağaza', 'Sıralama', 'Sosyal', 'Mesajlar']) {
        await tester.tap(find.byKey(ValueKey(id)));
      }
      await tester.tap(find.byType(LobbyDockAction).first);
      await tester.pumpAndSettle();
      expect(calls, [
        'create',
        'Mağaza',
        'Sıralama',
        'Sosyal',
        'Mesajlar',
        'menu',
      ]);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );
  for (final size in [const Size(640, 360), const Size(844, 390)]) {
    testWidgets('notched $size keeps all league cards visible in 2-2-1', (
      tester,
    ) async {
      final calls = <String>[];
      await lobby(
        tester,
        size,
        1.5,
        calls,
        insets: const EdgeInsets.fromLTRB(59, 0, 44, 21),
        selected: 'l4',
      );
      final cards = [
        for (var i = 0; i < 5; i++)
          tester.getRect(find.byKey(ValueKey('league-l$i'))),
      ];
      expect(cards[0].top, cards[1].top);
      expect(cards[2].top, cards[3].top);
      expect(cards[4].left, cards[0].left);
      expect(cards[4].right, cards[1].right);
      for (var i = 0; i < 5; i++) {
        expect(
          find.byKey(ValueKey('league-l$i')).hitTestable(),
          findsOneWidget,
        );
        expect(cards[i].left, greaterThanOrEqualTo(59));
        expect(cards[i].bottom, lessThan(size.height - 21));
      }
      expect(find.text('SEÇİLİ'), findsNothing);
      expect(find.text('KİLİTLİ'), findsNothing);
      expect(find.text('AÇIK'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('league-l4')));
      expect(calls, contains('l4'));
      expect(tester.takeException(), isNull);
    });
  }
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
        await tester.tap(find.byType(LobbyDockCreate));
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
        await tester.tap(find.byKey(const ValueKey('join-live')));
        expect(calls, contains('join'));
      }
    });
  }
  testWidgets('vertical tables scroll, refresh and two-seat actions', (
    tester,
  ) async {
    final calls = <String>[];
    final waiting = table('waiting')..['id'] = 'waiting';
    final full = table('playing')..['id'] = 'full';
    final closed = table('playing')
      ..['id'] = 'closed'
      ..['spectators_enabled'] = false;
    final fake = table('playing')
      ..['id'] = 'fake'
      ..['is_fake'] = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 260,
              child: LobbyTableWheel(
                tables: [waiting, full, closed, fake],
                blockedUserIds: const {'a'},
                onJoin: (t) => calls.add('join-${t['id']}'),
                onSpectate: (t) => calls.add('watch-${t['id']}'),
                onUserTap: (p) => calls.add('user-${p['user_id']}'),
                canSpectateAll: true,
                onRefresh: () async {
                  calls.add('refresh');
                },
                loading: false,
                playerCoin: 10000,
                playerRating: 1000,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ListWheelScrollView), findsNothing);
    expect(find.text('1/2'), findsNothing);
    expect(find.text('Boş yer'), findsNothing);
    expect(find.text('Masa 1'), findsNothing);
    expect(find.text('Masa 2'), findsNothing);
    expect(find.text('2.5 K'), findsWidgets);
    expect(find.text('5 K'), findsWidgets);
    expect(find.text('3 el · 20 sn'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('join-waiting')));
    await tester.tap(find.byKey(const ValueKey('seat-waiting-0')));
    expect(calls, containsAll(['join-waiting', 'user-a']));
    await tester.drag(
      find.byKey(const ValueKey('vertical-tables')),
      const Offset(0, -24),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('spectate-full')));
    await tester.tap(find.byKey(const ValueKey('spectate-full')));
    expect(calls, contains('watch-full'));

    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('join-closed')));
    await tester.tap(find.byKey(const ValueKey('join-closed')));
    expect(calls, isNot(contains('watch-closed')));
    expect(calls, isNot(contains('join-closed')));

    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('join-fake')));
    await tester.tap(find.byKey(const ValueKey('join-fake')));
    expect(calls, isNot(contains('watch-fake')));
    expect(calls, isNot(contains('join-fake')));

    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Masaları yenile'));
    expect(calls, contains('refresh'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  for (final size in sizes) {
    testWidgets('three complete compact tables visible at $size', (
      tester,
    ) async {
      final openTables = List.generate(
        6,
        (i) => table(i.isEven ? 'waiting' : 'playing')..['id'] = 'table-$i',
      );
      await lobby(tester, size, 2, [], openTables: openTables);
      final viewport = tester.getRect(
        find.byKey(const ValueKey('vertical-tables')),
      );
      Rect? previous;
      for (var i = 0; i < 3; i++) {
        final card = tester.getRect(find.byKey(ValueKey('table-$i')));
        expect(card.top, greaterThanOrEqualTo(viewport.top));
        expect(card.bottom, lessThanOrEqualTo(viewport.bottom));
        expect(card.height, lessThanOrEqualTo(92));
        if (previous != null) expect(card.top, greaterThan(previous.bottom));
        previous = card;
      }
      final scrollable = tester.widget<ListView>(find.byType(ListView));
      expect(scrollable.scrollDirection, Axis.vertical);
      await tester.drag(
        find.byKey(const ValueKey('vertical-tables')),
        const Offset(0, -170),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('table-3')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  for (final size in [const Size(640, 360), const Size(932, 430)]) {
    testWidgets('lobby component golden $size', (tester) async {
      await lobby(
        tester,
        size,
        1,
        [],
        openTables: List.generate(
          5,
          (i) => table(i.isEven ? 'waiting' : 'playing')..['id'] = 'preview-$i',
        ),
      );
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile(
          'goldens/lobby_${size.width.toInt()}x${size.height.toInt()}.png',
        ),
      );
    });
  }
}
