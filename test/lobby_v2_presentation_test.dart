import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/lobby_v2/l3d_hud.dart';
import 'package:okeyix/ui/lobby_v2/l3d_leagues.dart';
import 'package:okeyix/ui/lobby_v2/l3d_room.dart';
import 'package:okeyix/ui/lobby_v2/l3d_theme.dart';

const _sizes = [
  Size(568, 320),
  Size(640, 360),
  Size(800, 360),
  Size(844, 390),
  Size(932, 430),
  Size(1024, 600),
  Size(1280, 720),
];

final _leagues = List.generate(
  5,
  (i) => <String, dynamic>{
    'id': 'l$i',
    'name': ['Acemiler', 'Çıraklar', 'Kalfalar', 'Ustalar', 'Şampiyonlar'][i],
    'min_coin': i * 10000,
    'min_rating': i * 1000,
  },
);

Map<String, dynamic> _table(int i) => {
  'id': 't$i',
  'max_players': i % 3 == 0 ? 4 : 2,
  'status': i.isEven ? 'waiting' : 'playing',
  'spectators_enabled': true,
  'entry_coin': 2500 * (i + 1),
  'round_count': i + 1,
  'pot_amount': 5000 * (i + 1),
  '_players': [
    {'seat_index': 0, 'user_id': 'a$i', 'username': 'Deniz'},
    if (i.isOdd) {'seat_index': 1, 'user_id': 'b$i', 'username': 'Ece', 'is_bot': true},
  ],
};

Widget _tile(String id, List<String> calls, {int badge = 0}) => L3dTile(
  key: ValueKey(id),
  label: id,
  icon: Icons.storefront_rounded,
  color: const Color(0xFF3D7BFF),
  badge: badge,
  onTap: () => calls.add(id),
);

Future<void> _scene(
  WidgetTester tester,
  Size size,
  List<String> calls, {
  double scale = 1,
  String selected = 'l0',
  bool locked = false,
  bool loading = false,
  int tableCount = 5,
  EdgeInsets insets = const EdgeInsets.fromLTRB(44, 0, 44, 21),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
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
        backgroundColor: L3d.night,
        body: LayoutBuilder(builder: (context, box) {
          final pad = MediaQuery.paddingOf(context);
          final innerW = box.maxWidth - pad.left - pad.right - 16;
          final leagueW = innerW * (innerW < 700 ? .40 : .36);
          final dockTop = pad.bottom + 4 + L3dDock.height;
          return Stack(children: [
            Positioned.fill(
              child: L3dRoom(
                viewInsets: EdgeInsets.fromLTRB(pad.left + 8 + leagueW + 12, pad.top + 6, pad.right + 8, dockTop + 4),
                leagueName: 'Acemiler',
                accent: const Color(0xFFFF9A52),
                tables: [for (var i = 0; i < tableCount; i++) _table(i)],
                loading: loading,
                locked: locked,
                lockedLeague: _leagues.last,
                userCoin: 25000,
                userRating: 2400,
                blockedUserIds: const {},
                onJoin: (t) => calls.add('join:${t['id']}'),
                onSpectate: (t) => calls.add('watch:${t['id']}'),
                onUserTap: (_) => calls.add('user'),
                onCreate: () => calls.add('create'),
                onStore: () => calls.add('store'),
                onRefresh: () async => calls.add('refresh'),
              ),
            ),
            Positioned(
              left: pad.left + 8,
              top: pad.top + 6,
              width: leagueW,
              bottom: dockTop + 6,
              child: L3dLeagueWall(
                leagues: _leagues,
                selectedLeagueId: selected,
                leagueActivePlayers: {for (var i = 0; i < 5; i++) 'l$i': 24 + i},
                leagueActiveTables: {for (var i = 0; i < 5; i++) 'l$i': 6 + i},
                userCoin: 25000,
                userRating: 2400,
                loading: false,
                onSelect: (l) => calls.add(l['id'] as String),
              ),
            ),
            Positioned(
              left: pad.left + 8,
              right: pad.right + 8,
              bottom: pad.bottom + 4,
              height: L3dDock.height,
              child: L3dDock(
                left: [
                  L3dProfileChip(
                    key: const ValueKey('v2-profile'),
                    name: 'Deniz',
                    avatarUrl: null,
                    rating: 12450,
                    onTap: () => calls.add('profile'),
                  ),
                  L3dCoinChip(
                    value: const Text('25 Bin', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                    onAdd: () => calls.add('coin+'),
                  ),
                ],
                center: L3dPlayButton(
                  key: const ValueKey('v2-quick-play'),
                  label: 'HIZLI OYNA',
                  caption: 'Uygun masaya otur',
                  onTap: () => calls.add('quick'),
                ),
                right: [
                  for (final id in ['nav-store', 'nav-ranking', 'nav-invite', 'nav-friends'])
                    _tile(id, calls),
                  _tile('nav-messages', calls, badge: 4),
                  _tile('v2-menu', calls),
                ],
              ),
            ),
          ]);
        }),
      ),
    ),
  );
  // Decode the illustrated assets so goldens show the real artwork.
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void _expectOnScreen(WidgetTester tester, Finder f, Size size, String what) {
  final r = tester.getRect(f);
  expect(r.left >= -.01 && r.top >= -.01 && r.right <= size.width + .01 && r.bottom <= size.height + .01, isTrue,
      reason: '$what off-screen at $size: $r');
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

  for (final size in _sizes) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('3d room $size scale $scale: 2-2-1, actions visible', (tester) async {
        final calls = <String>[];
        await _scene(tester, size, calls, scale: scale);
        expect(tester.takeException(), isNull);

        final wall = tester.getRect(find.byType(L3dLeagueWall));
        final cards = [for (var i = 0; i < 5; i++) tester.getRect(find.byKey(ValueKey('v2-league-l$i')))];
        for (final c in cards) {
          expect(wall.inflate(.01).contains(c.topLeft) && wall.inflate(.01).contains(c.bottomRight), isTrue);
          expect(c.height, greaterThan(36));
        }
        expect(cards[0].top, closeTo(cards[1].top, .01));
        expect(cards[2].top, closeTo(cards[3].top, .01));
        expect(cards[1].left, greaterThan(cards[0].right));
        expect(cards[2].top, greaterThan(cards[0].bottom));
        expect(cards[4].top, greaterThan(cards[2].bottom));
        expect(cards[4].width, closeTo(wall.width, .01));

        for (final key in [
          'v2-quick-play', 'v2-profile', 'v2-coin-add', 'v2-menu', 'v2-salon-create', 'v2-salon-refresh',
          'v2-table-t0', 'seat-t0-1', 'nav-store', 'nav-messages',
        ]) {
          _expectOnScreen(tester, find.byKey(ValueKey(key)), size, key);
        }
        // The focused table sits right of the league wall, not under it.
        expect(tester.getRect(find.byKey(const ValueKey('v2-table-t0'))).left, greaterThan(wall.right - 1));

        await tester.tap(find.byKey(const ValueKey('v2-league-l3')));
        await tester.tap(find.byKey(const ValueKey('v2-quick-play')));
        await tester.tap(find.byKey(const ValueKey('v2-salon-create')));
        await tester.tap(find.byKey(const ValueKey('nav-messages')));
        await tester.tap(find.byKey(const ValueKey('v2-coin-add')));
        expect(calls, containsAllInOrder(['l3', 'quick', 'create', 'nav-messages', 'coin+']));
      });
    }
  }

  testWidgets('camera: front table acts, neighbour glides to the front first', (tester) async {
    final calls = <String>[];
    await _scene(tester, const Size(932, 430), calls);
    await tester.tap(find.byKey(const ValueKey('seat-t0-1')));
    expect(calls, ['join:t0']);
    // Tap the part of the neighbour that peeks into view.
    final peek = tester.getRect(find.byKey(const ValueKey('v2-table-t1')));
    expect(peek.left, lessThan(932 - 20), reason: 'neighbour table should peek into view');
    await tester.tapAt(Offset((peek.left + 932) / 2, peek.center.dy));
    await _settle(tester);
    expect(calls, ['join:t0']);
    await tester.tap(find.byKey(const ValueKey('spectate-t1')));
    await tester.tap(find.byKey(const ValueKey('seat-t1-0')));
    expect(calls, ['join:t0', 'watch:t1', 'user']);
    expect(find.byKey(const ValueKey('spectate-t0')), findsNothing);
    // Swiping moves the camera to the next table.
    await tester.drag(find.byKey(const ValueKey('capture')), const Offset(-300, 0));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('seat-t2-1')));
    expect(calls.last, 'join:t2');
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty, loading and locked rooms render without overflow', (tester) async {
    final calls = <String>[];
    await _scene(tester, const Size(640, 360), calls, tableCount: 0);
    expect(find.text('Salon şu an sessiz.'), findsOneWidget);
    await _scene(tester, const Size(640, 360), calls, loading: true);
    expect(tester.takeException(), isNull);
    await _scene(tester, const Size(640, 360), calls, locked: true, selected: 'l4');
    expect(find.text('ŞAMPİYONLAR KİLİTLİ'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('v2-locked-store')));
    expect(calls, contains('store'));
    expect(tester.takeException(), isNull);
  });

  // Android can report a zero-width window while entering immersive mode.
  testWidgets('dock and room survive a zero-size window', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          SizedBox(
            width: 0,
            height: L3dDock.height,
            child: L3dDock(left: const [SizedBox(width: 40)], center: const SizedBox(), right: const [SizedBox(width: 40)]),
          ),
          SizedBox(
            width: 0,
            height: 120,
            child: L3dLeagueWall(
              leagues: _leagues,
              selectedLeagueId: 'l0',
              leagueActivePlayers: const {},
              leagueActiveTables: const {},
              userCoin: 0,
              userRating: 0,
              loading: false,
              onSelect: (_) {},
            ),
          ),
          SizedBox(
            width: 0,
            height: 0,
            child: L3dRoom(
              viewInsets: const EdgeInsets.fromLTRB(300, 6, 8, 70),
              leagueName: 'Acemiler',
              accent: L3d.amber,
              tables: [_table(0)],
              loading: false,
              locked: false,
              lockedLeague: null,
              userCoin: 0,
              userRating: 0,
              blockedUserIds: const {},
              onJoin: (_) {},
              onSpectate: (_) {},
              onUserTap: (_) {},
              onCreate: () {},
              onStore: () {},
              onRefresh: () async {},
            ),
          ),
        ]),
      ),
    ));
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(640, 360), const Size(932, 430)]) {
    testWidgets('3d room golden $size', (tester) async {
      await _scene(tester, size, []);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('goldens/lobby_v2_${size.width.toInt()}x${size.height.toInt()}.png'),
      );
    });
  }
  testWidgets('3d room golden locked 640x360', (tester) async {
    await _scene(tester, const Size(640, 360), [], locked: true, selected: 'l4');
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('goldens/lobby_v2_locked_640x360.png'),
    );
  });
}
