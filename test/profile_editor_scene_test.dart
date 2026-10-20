import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/profile_editor_scene.dart';
import 'package:okeyix/ui/profile_setup_dialog.dart';

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
  TextEditingController controller,
  List<String> calls, {
  double scale = 1,
  bool keyboard = false,
  bool saving = false,
  bool force = false,
  bool page = false,
  String? error,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Montserrat'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: const EdgeInsets.fromLTRB(44, 12, 24, 21),
          viewPadding: const EdgeInsets.fromLTRB(44, 12, 24, 21),
          viewInsets: EdgeInsets.only(bottom: keyboard ? 140 : 0),
          textScaler: TextScaler.linear(scale),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: RepaintBoundary(
          key: const ValueKey('profile-capture'),
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  'assets/images/lobby/lobby.png',
                  fit: BoxFit.cover,
                ),
              ),
              const Positioned.fill(
                child: ColoredBox(color: Color(0x77050A12)),
              ),
              ProfileEditorScene(
                avatar: Image.asset(
                  'assets/images/avatars/avatar1.png',
                  fit: BoxFit.cover,
                ),
                username: controller,
                renameInfo: 'İlk isim değişikliği ücretsiz. Sonrası 1000 coin.',
                costInfo: 'Bu kayıt için coin harcanmayacak.',
                onAvatar: () => calls.add('avatar'),
                onPhoto: () => calls.add('photo'),
                onSave: () => calls.add('save'),
                onClose: () => calls.add('close'),
                saving: saving,
                forceComplete: force,
                asPage: page,
                error: error,
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
      testWidgets(
        'landscape profile $size scale $scale controls and callbacks',
        (tester) async {
          final controller = TextEditingController(text: 'Oyuncu_UzunIsim');
          addTearDown(controller.dispose);
          final calls = <String>[];
          await scene(tester, size, controller, calls, scale: scale);
          for (final item in {
            'Avatar Seç': 'avatar',
            'Fotoğraf': 'photo',
            'Kaydet': 'save',
          }.entries) {
            final finder = find.byKey(ValueKey('profile-${item.key}'));
            final rect = tester.getRect(finder);
            expect(rect.top, greaterThanOrEqualTo(12));
            expect(rect.bottom, lessThanOrEqualTo(size.height - 21));
            await tester.tap(finder);
            expect(calls, contains(item.value));
          }
          await tester.enterText(
            find.byKey(const ValueKey('profile-username')),
            'YeniOyuncu',
          );
          expect(controller.text, 'YeniOyuncu');
          await tester.tap(find.byKey(const ValueKey('profile-close')));
          expect(calls, contains('close'));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'keyboard keeps save visible; busy and forced setup retain controls',
    (tester) async {
      final controller = TextEditingController(text: 'Deniz');
      addTearDown(controller.dispose);
      final calls = <String>[];
      await scene(
        tester,
        sizes.first,
        controller,
        calls,
        scale: 2,
        keyboard: true,
        error: 'Bu kullanıcı adı kullanılıyor.',
      );
      final button = tester.getRect(
        find.byKey(const ValueKey('profile-Kaydet')),
      );
      expect(button.bottom, lessThanOrEqualTo(360 - 140));
      await tester.tap(find.byKey(const ValueKey('profile-Kaydet')));
      expect(calls, contains('save'));
      expect(tester.takeException(), isNull);
      calls.clear();
      await scene(tester, sizes.first, controller, calls, saving: true);
      await tester.tap(find.byKey(const ValueKey('profile-Kaydediliyor...')));
      expect(calls, isEmpty);
      await scene(
        tester,
        sizes.first,
        controller,
        calls,
        force: true,
        page: true,
        scale: 2,
      );
      expect(find.byKey(const ValueKey('profile-close')), findsNothing);
      expect(find.byKey(const ValueKey('profile-Fotoğraf')), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byKey(const ValueKey('profile-Avatar Seç')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('real profile retains rename costs and local validation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProfileSetupDialog(
            forceComplete: false,
            initialUsername: 'Deniz',
            initialAvatarRef: 'assets/images/avatars/avatar1.png',
            currentUserId: 'test',
            currentCoins: 5000,
            renameCoinCost: 1000,
            freeRenameUsed: true,
            ownedPremiumAvatarRefs: {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bu kayıt için coin harcanmayacak.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'YeniDeniz');
    await tester.pumpAndSettle();
    expect(find.text('Toplam maliyet: 1000 coin'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.byKey(const ValueKey('profile-Kaydet')));
    await tester.pumpAndSettle();
    expect(find.text('Kullanıcı adı zorunlu.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [sizes.first, sizes[3]]) {
    testWidgets('profile golden $size', (tester) async {
      final controller = TextEditingController(text: 'Deniz');
      addTearDown(controller.dispose);
      await scene(tester, size, controller, []);
      await expectLater(
        find.byKey(const ValueKey('profile-capture')),
        matchesGoldenFile(
          'goldens/profile_${size.width.toInt()}x${size.height.toInt()}.png',
        ),
      );
    });
  }
}
