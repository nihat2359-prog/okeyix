import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/table_chat_panel.dart';

Future<void> scene(
  WidgetTester tester,
  Size size,
  double keyboard,
  double scale,
  List<String> calls,
) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final input = TextEditingController();
  final scroll = ScrollController();
  addTearDown(input.dispose);
  addTearDown(scroll.dispose);
  var open = true;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Montserrat'),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          padding: const EdgeInsets.fromLTRB(44, 12, 24, 0),
          viewInsets: EdgeInsets.only(bottom: keyboard),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          body: SafeArea(
            child: StatefulBuilder(
              builder: (context, update) => Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      key: const ValueKey('game'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => calls.add('game-tap'),
                      onPanStart: (_) => calls.add('game-drag'),
                      child: const ColoredBox(color: Color(0xFF10251F)),
                    ),
                  ),
                  if (open)
                    TableChatPanel(
                      controller: input,
                      scrollController: scroll,
                      messageCount: 30,
                      messageBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.all(5),
                        child: Text(
                          i.isEven ? 'Oyuncu: mesaj $i' : 'İzleyici: mesaj $i',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      onClose: () {
                        calls.add('close');
                        update(() => open = false);
                      },
                      onSend: () => calls.add('send:${input.text}'),
                      onQuickMessage: (message) => calls.add(message),
                      onEmoji: () => calls.add('emoji'),
                      microphone: IconButton(
                        tooltip: 'Mikrofon',
                        onPressed: () => calls.add('mic'),
                        icon: const Icon(Icons.mic),
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
  await tester.pump();
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
  for (final keyboard in [0.0, 216.0]) {
    testWidgets('chat appearance keyboard $keyboard', (tester) async {
      await scene(tester, const Size(844, 390), keyboard, 1, []);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          'goldens/table_chat_${keyboard == 0 ? 'closed_keyboard' : 'open_keyboard'}.png',
        ),
      );
    });
  }

  testWidgets('outside drag is swallowed without starting a game gesture', (
    tester,
  ) async {
    final calls = <String>[];
    await scene(tester, const Size(844, 390), 0, 1, calls);
    await tester.dragFrom(const Offset(90, 70), const Offset(80, 30));
    await tester.pump();
    expect(calls.where((call) => call.startsWith('game')), isEmpty);
  });
  for (final size in [
    const Size(568, 320),
    const Size(640, 360),
    const Size(844, 390),
    const Size(932, 430),
    const Size(1024, 600),
  ]) {
    for (final keyboard in [0.0, 216.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'landscape $size keyboard $keyboard text $scale keeps input send close visible',
          (tester) async {
            final calls = <String>[];
            await scene(tester, size, keyboard, scale, calls);
            for (final key in [
              'table-chat-input',
              'table-chat-send',
              'table-chat-close',
            ]) {
              final target = find.byKey(ValueKey(key));
              expect(target.hitTestable(), findsOneWidget);
              expect(
                tester.getRect(target).bottom,
                lessThanOrEqualTo(size.height - keyboard),
              );
            }
            expect(find.byType(BackdropFilter), findsNothing);
            expect(
              tester
                  .getSize(find.byKey(const ValueKey('table-chat-panel')))
                  .width,
              lessThan(size.width * .65),
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final message in TableChatPanel.quickMessages) {
    testWidgets('quick $message sends once and closes', (tester) async {
      final calls = <String>[];
      await scene(tester, const Size(844, 390), 0, 1, calls);
      await tester.ensureVisible(find.text(message));
      await tester.pumpAndSettle();
      await tester.tap(find.text(message));
      await tester.pump();
      expect(calls, ['close', message]);
      expect(find.byType(TableChatPanel), findsNothing);
    });
  }

  for (final outside in [true, false]) {
    testWidgets(
      'one tap closes chat and keyboard, outside=$outside, without moving a tile',
      (tester) async {
        final calls = <String>[];
        await scene(tester, const Size(844, 390), 216, 1, calls);
        await tester.showKeyboard(find.byType(TextField));
        await tester.enterText(find.byType(TextField), 'Merhaba');
        await tester.tap(find.byKey(const ValueKey('table-chat-send')));
        expect(calls, ['send:Merhaba']);
        if (outside) {
          await tester.tapAt(const Offset(90, 60));
        } else {
          await tester.tap(find.byKey(const ValueKey('table-chat-close')));
        }
        await tester.pump();
        expect(find.byType(TableChatPanel), findsNothing);
        expect(tester.testTextInput.isVisible, isFalse);
        expect(calls, ['send:Merhaba', 'close']);
        await tester.tapAt(const Offset(90, 60));
        expect(calls.last, 'game-tap');
      },
    );
  }

  testWidgets('messages scroll and emoji/microphone callbacks stay available', (
    tester,
  ) async {
    final calls = <String>[];
    await scene(tester, const Size(844, 390), 0, 1, calls);
    await tester.drag(
      find.byKey(const ValueKey('table-chat-messages')),
      const Offset(0, -1000),
    );
    await tester.pumpAndSettle();
    expect(find.text('İzleyici: mesaj 29'), findsOneWidget);
    await tester.tap(find.byTooltip('Emoji'));
    await tester.tap(find.byTooltip('Mikrofon'));
    expect(calls, ['emoji', 'mic']);
  });
}
