import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/lobby/lobby_utility_scenes.dart';

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
  bool support,
  List<String> calls, {
  double scale = 1,
  bool keyboard = false,
  bool busy = false,
  String? error,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final controller = TextEditingController();
  addTearDown(controller.dispose);
  var category = 'talep';
  var sound = true, vibration = false, colorBlind = false, invites = true;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Montserrat'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: EdgeInsets.fromLTRB(44, 12, 24, keyboard ? 0 : 21),
          viewPadding: const EdgeInsets.fromLTRB(44, 12, 24, 21),
          viewInsets: EdgeInsets.only(bottom: keyboard ? 140 : 0),
          textScaler: TextScaler.linear(scale),
        ),
        child: child!,
      ),
      home: Scaffold(
        resizeToAvoidBottomInset: false,
        body: RepaintBoundary(
          key: const ValueKey('utility-capture'),
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  'assets/images/lobby/lobby.png',
                  fit: BoxFit.cover,
                ),
              ),
              const Positioned.fill(
                child: ColoredBox(color: Color(0x88050A12)),
              ),
              StatefulBuilder(
                builder: (context, update) => support
                    ? GameSupportScene(
                        message: controller,
                        category: category,
                        sending: busy,
                        error: error,
                        onCategory: (value) {
                          calls.add(value);
                          update(() => category = value);
                        },
                        onSend: () => calls.add('send:${controller.text}'),
                        onClose: () => calls.add('close'),
                      )
                    : GameSettingsScene(
                        sound: sound,
                        vibration: vibration,
                        colorBlind: colorBlind,
                        invites: invites,
                        onSound: (value) {
                          calls.add('sound:$value');
                          update(() => sound = value);
                        },
                        onVibration: (value) {
                          calls.add('vibration:$value');
                          update(() => vibration = value);
                        },
                        onColorBlind: (value) {
                          calls.add('color:$value');
                          update(() => colorBlind = value);
                        },
                        onInvites: (value) {
                          calls.add('invites:$value');
                          update(() => invites = value);
                        },
                        onClose: () => calls.add('close'),
                        onDelete: () => calls.add('delete'),
                      ),
              ),
            ],
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
      for (final support in [true, false]) {
        testWidgets('${support ? 'support' : 'settings'} $size scale $scale', (
          tester,
        ) async {
          final calls = <String>[];
          await scene(tester, size, support, calls, scale: scale);
          if (support) {
            await tester.tap(find.byKey(const ValueKey('support-sikayet')));
            expect(calls, contains('sikayet'));
            await tester.tap(find.byKey(const ValueKey('support-hata')));
            expect(calls, contains('hata'));
            await tester.enterText(
              find.byKey(const ValueKey('support-message')),
              'Oyun hakkında destek istiyorum.',
            );
            final button = tester.getRect(
              find.byKey(const ValueKey('utility-Gönder')),
            );
            expect(button.bottom, lessThanOrEqualTo(size.height - 21));
            expect(button.right, lessThanOrEqualTo(size.width - 24));
            await tester.tap(find.byKey(const ValueKey('utility-Gönder')));
            expect(calls, contains('send:Oyun hakkında destek istiyorum.'));
            await tester.tap(find.byKey(const ValueKey('utility-Vazgeç')));
          } else {
            for (final entry in {
              'Ses': 'sound:false',
              'Titreşim': 'vibration:true',
              'Renk Körü Modu': 'color:true',
              'Oyun Davetleri': 'invites:false',
            }.entries) {
              final target = find.byKey(ValueKey('setting-${entry.key}'));
              await tester.ensureVisible(target);
              await tester.tap(target);
              await tester.pumpAndSettle();
              expect(calls, contains(entry.value));
            }
            await tester.tap(find.byKey(const ValueKey('utility-Hesabı Sil')));
            expect(calls, contains('delete'));
          }
          await tester.tap(find.byKey(const ValueKey('utility-close')));
          expect(calls, contains('close'));
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('support keyboard and pending request preserve fixed actions', (
    tester,
  ) async {
    final calls = <String>[];
    await scene(
      tester,
      sizes.first,
      true,
      calls,
      keyboard: true,
      scale: 2,
      error: 'Lütfen en az 8 karakter açıklama yaz.',
    );
    final button = tester.getRect(find.byKey(const ValueKey('utility-Gönder')));
    expect(button.bottom, lessThanOrEqualTo(360 - 140));
    final messageFinder = find.byKey(const ValueKey('support-message'));
    expect(tester.getSize(messageFinder).height, greaterThanOrEqualTo(64));
    await tester.enterText(messageFinder, 'Destek test mesajı 12345');
    await tester.tap(find.byKey(const ValueKey('support-hide-keyboard')));
    await tester.pump();
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isFalse);
    expect(editable.controller.text, 'Destek test mesajı 12345');
    expect(calls, isEmpty);
    await tester.tap(find.byKey(const ValueKey('utility-Gönder')));
    expect(calls, contains('send:Destek test mesajı 12345'));
    expect(tester.takeException(), isNull);
    calls.clear();
    await scene(tester, sizes.first, true, calls, busy: true);
    await tester.tap(find.byKey(const ValueKey('utility-Gönderiliyor…')));
    await tester.tap(find.byKey(const ValueKey('utility-Vazgeç')));
    await tester.tap(find.byKey(const ValueKey('support-hata')));
    expect(calls, isEmpty);
    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.enabled, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final support in [true, false]) {
    testWidgets('${support ? 'support' : 'settings'} golden', (tester) async {
      await scene(tester, sizes.first, support, []);
      await expectLater(
        find.byKey(const ValueKey('utility-capture')),
        matchesGoldenFile(
          'goldens/${support ? 'support' : 'settings'}_640x360.png',
        ),
      );
    });
  }
}
