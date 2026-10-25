import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/lobby/lobby_right_panel.dart';
import 'package:okeyix/ui/lobby/lobby_social_scenes.dart';

const sizes = [
  Size(568, 320),
  Size(640, 360),
  Size(844, 390),
  Size(932, 430),
  Size(1024, 600),
];
Future<void> scene(
  WidgetTester tester,
  Size size,
  double scale,
  List<String> calls, {
  bool messages = false,
  double keyboard = 0,
  bool empty = false,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final input = TextEditingController();
  final scroll = ScrollController();
  addTearDown(input.dispose);
  addTearDown(scroll.dispose);
  final friends = <Map<String, dynamic>>[
    if (!empty)
      for (var i = 0; i < 9; i++)
        {
          'id': '$i',
          'username': 'Oyuncu $i',
          'is_online': i.isEven,
          'rating': 12500,
          'coins': 1500000,
          'table_id': i == 0 ? 'table' : null,
          'table_spectators_enabled': true,
        },
  ];
  Widget avatar(Map<String, dynamic> f) => CircleAvatar(
    radius: messages ? 14 : 22,
    backgroundColor: const Color(0xFF6D5B38),
    child: Icon(Icons.person_outline, size: messages ? 18 : 26, color: const Color(0xFFEAD6A5)),
  );
  var open = true;
  var active = empty ? null : '0';
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Montserrat'),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          padding: EdgeInsets.fromLTRB(44, 12, 24, keyboard > 0 ? 0 : 21),
          viewInsets: EdgeInsets.only(bottom: keyboard),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          body: StatefulBuilder(
            builder: (context, update) {
              void close() {
                calls.add('close');
                update(() => open = false);
              }

              return Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => calls.add('lobby-tap'),
                      onPanStart: (_) => calls.add('lobby-drag'),
                      child: Image.asset(
                        'assets/images/lobby/lobby.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  LobbyRightPanel(
                    open: open,
                    onClose: close,
                    widthFactor: messages ? .62 : .80,
                    minWidth: messages ? 350 : 480,
                    maxWidth: messages ? 500 : 760,
                    panelContent: messages
                        ? LobbyMessagesScene(
                            friends: friends,
                            activeId: active,
                            unread: const {'1': 3},
                            avatarBuilder: avatar,
                            onSelect: (f) {
                              calls.add('select:${f['id']}');
                              update(() => active = f['id']?.toString());
                            },
                            onClose: close,
                            controller: input,
                            scrollController: scroll,
                            onSend: () => calls.add('send:${input.text}'),
                            onEmoji: () => calls.add('emoji'),
                            microphone: IconButton(
                              tooltip: 'Mikrofon',
                              onPressed: () => calls.add('mic'),
                              icon: const Icon(Icons.mic),
                            ),
                            messageCount: empty ? 0 : 25,
                            messageBuilder: (_, i) => Align(
                              alignment: i.isEven
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(
                                  'Mesaj $i',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                            menu: const Icon(
                              Icons.more_vert,
                              color: Colors.white54,
                            ),
                          )
                        : LobbyFriendsScene(
                            friends: friends,
                            avatarBuilder: avatar,
                            statusText: (f) => f['is_online'] == true
                                ? 'Çevrimiçi'
                                : '10 sa önce görüldü',
                            onProfile: (f) => calls.add('profile:${f['id']}'),
                            onMessage: (f) => calls.add('message:${f['id']}'),
                            onSpectate: (f) => calls.add('spectate:${f['id']}'),
                            onClose: close,
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
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
      for (final mode in ['friends', 'messages', 'keyboard']) {
        testWidgets('$mode $size text $scale is a bounded right panel', (
          tester,
        ) async {
          final keyboard = mode == 'keyboard' ? 216.0 : 0.0;
          await scene(
            tester,
            size,
            scale,
            [],
            messages: mode != 'friends',
            keyboard: keyboard,
          );
          final rect = tester.getRect(
            find.byKey(const ValueKey('lobby-social-panel')),
          );
          expect(rect.right, lessThanOrEqualTo(size.width - 24));
          // Container bounds include its eight-pixel outer margin.
          expect(rect.width, lessThanOrEqualTo(mode == 'friends' ? 768 : 508));
          expect(rect.left, greaterThan(44));
          expect(rect.bottom, lessThanOrEqualTo(size.height - keyboard));
          expect(
            find.byKey(const ValueKey('lobby-social-close')).hitTestable(),
            findsOneWidget,
          );
          if (mode != 'friends') {
            expect(
              find.byKey(const ValueKey('social-message-input')).hitTestable(),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('social-message-send')).hitTestable(),
              findsOneWidget,
            );
          }
          if (mode == 'friends') {
            final first = tester.getRect(find.byKey(const ValueKey('social-friend-0')));
            final second = tester.getRect(find.byKey(const ValueKey('social-friend-1')));
            expect(first.top, second.top);
            expect(second.left, greaterThan(first.right));
          }
          expect(find.byType(BackdropFilter), findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
  testWidgets(
    'friend profile, message and spectate callbacks remain independent',
    (tester) async {
      final calls = <String>[];
      await scene(tester, sizes[2], 1, calls);
      expect(find.text('Seviye 12.5 · 1.5 M Coin'), findsWidgets);
      await tester.tap(find.text('Oyuncu 0'));
      await tester.tap(find.byTooltip('Masayı izle'));
      await tester.tap(find.byTooltip('Mesaj yaz').first);
      expect(calls, ['profile:0', 'spectate:0', 'message:0']);
    },
  );
  testWidgets(
    'keyboard friend picker, composer and one-tap dismissal retain callbacks',
    (tester) async {
      final calls = <String>[];
      await scene(tester, sizes[2], 1, calls, messages: true, keyboard: 216);
      await tester.tap(find.byTooltip('Arkadaş seç'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Oyuncu 1  (3 yeni)'));
      await tester.pumpAndSettle();
      expect(calls, ['select:1']);
      await tester.showKeyboard(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Selam');
      await tester.tap(find.byKey(const ValueKey('social-message-send')));
      await tester.tapAt(const Offset(85, 70));
      await tester.pump();
      expect(calls, ['select:1', 'send:Selam', 'close']);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(find.byKey(const ValueKey('lobby-social-panel')), findsNothing);
    },
  );
  testWidgets('empty friends do not enable message sending', (tester) async {
    await scene(tester, sizes[2], 1, [], messages: true, empty: true);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('social-message-send')))
          .onPressed,
      isNull,
    );
  });
  testWidgets('unread sender is first and has a visible avatar badge', (tester) async {
    final calls = <String>[];
    await scene(tester, sizes[2], 1, calls, messages: true);
    final unread = find.byKey(const ValueKey('message-contact-1'));
    final read = find.byKey(const ValueKey('message-contact-0'));
    expect(tester.getTopLeft(unread).dx, lessThan(tester.getTopLeft(read).dx));
    expect(find.byKey(const ValueKey('message-unread-1')), findsOneWidget);
    await tester.tap(unread);
    await tester.pump();
    expect(calls, ['select:1']);
  });
  for (final mode in ['friends', 'messages', 'keyboard']) {
    testWidgets('social golden $mode', (tester) async {
      await scene(
        tester,
        sizes[2],
        1,
        [],
        messages: mode != 'friends',
        keyboard: mode == 'keyboard' ? 216 : 0,
      );
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/lobby_social_$mode.png'),
      );
    });
  }
}
