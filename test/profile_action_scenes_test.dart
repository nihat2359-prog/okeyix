import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/profile_action_scenes.dart';
import 'package:okeyix/ui/gift_selector_sheet.dart';
import 'package:okeyix/ui/report_user_sheet.dart';

const gifts = [
  {'type': 'rose', 'name': 'Gül', 'cost': 100, 'emoji': '🌹'},
  {'type': 'cake', 'name': 'Pasta', 'cost': 150, 'emoji': '🎂'},
  {'type': 'heart', 'name': 'Kalp', 'cost': 200, 'emoji': '❤️'},
  {'type': 'star', 'name': 'Yıldız', 'cost': 250, 'emoji': '⭐'},
  {'type': 'diamond', 'name': 'Elmas', 'cost': 500, 'emoji': '💎'},
  {'type': 'fire', 'name': 'Ateş', 'cost': 300, 'emoji': '🔥'},
];

Future<void> frame(
  WidgetTester tester,
  Size size,
  Widget child, {
  double scale = 1,
  double keyboard = 0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Montserrat'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: const EdgeInsets.only(left: 44, right: 24),
          viewPadding: const EdgeInsets.only(left: 44, right: 24),
          viewInsets: EdgeInsets.only(bottom: keyboard),
          textScaler: TextScaler.linear(scale),
        ),
        child: child!,
      ),
      home: Scaffold(
        resizeToAvoidBottomInset: false,
        body: RepaintBoundary(
          key: const ValueKey('profile-action-capture'),
          child: child,
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
  for (final size in [
    const Size(480, 270),
    const Size(568, 320),
    const Size(844, 390),
  ]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('profile gifts fit landscape $size scale $scale', (
        tester,
      ) async {
        var selected = -1, sent = 0, closed = 0;
        await frame(
          tester,
          size,
          StatefulBuilder(
            builder: (context, update) => ProfileGiftScene(
              recipient: 'Çok uzun oyuncu kullanıcı adı',
              gifts: gifts,
              selected: selected,
              sending: false,
              onSelect: (index) => update(() => selected = index),
              onSend: () => sent++,
              onClose: () => closed++,
            ),
          ),
          scale: scale,
        );
        expect(find.byKey(const ValueKey('profile-gift-fire')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('profile-gift-cake')));
        await tester.pumpAndSettle();
        expect(selected, 1);
        expect(find.text('GÖNDER · 150 COIN'), findsOneWidget);
        final action = tester.getRect(find.text('GÖNDER · 150 COIN'));
        expect(action.bottom, lessThan(size.height - 8));
        expect(action.right, lessThan(size.width - 24));
        await tester.tap(find.text('GÖNDER · 150 COIN'));
        expect(sent, 1);
        await tester.tap(find.text('Vazgeç'));
        expect(closed, 1);
        expect(tester.takeException(), isNull);
      });
    }
    for (final keyboard in [0.0, 100.0]) {
      testWidgets('profile report fits $size keyboard $keyboard', (
        tester,
      ) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        var sent = 0;
        await frame(
          tester,
          size,
          ProfileReportScene(
            username: 'ÇokUzunOyuncu',
            controller: controller,
            sending: false,
            onClose: () {},
            onSend: () => sent++,
          ),
          keyboard: keyboard,
          scale: 1.3,
        );
        await tester.enterText(
          find.byKey(const ValueKey('profile-report-message')),
          'Şikâyet açıklaması',
        );
        expect(controller.text, 'Şikâyet açıklaması');
        final button = tester.getRect(find.text('BİLDİRİMİ GÖNDER'));
        expect(button.bottom, lessThanOrEqualTo(size.height - keyboard - 8));
        await tester.tap(find.text('BİLDİRİMİ GÖNDER'));
        expect(sent, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('actual gift sheet keeps all six original types and prices', (
    tester,
  ) async {
    await frame(
      tester,
      const Size(844, 390),
      GiftSelectorSheet(
        receiverId: 'receiver',
        receiverName: 'Oyuncu',
        onGiftSent: () {},
      ),
    );
    for (final gift in gifts) {
      expect(
        find.byKey(ValueKey('profile-gift-${gift['type']}')),
        findsOneWidget,
      );
      expect(find.text('${gift['cost']} coin'), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('profile-gift-diamond')));
    await tester.pumpAndSettle();
    expect(find.text('GÖNDER · 500 COIN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('actual report still rejects empty submission before network', (
    tester,
  ) async {
    await frame(
      tester,
      const Size(568, 320),
      const ReportUserSheet(
        reportedUserId: 'receiver',
        reportedUsername: 'Oyuncu',
      ),
    );
    await tester.tap(find.text('BİLDİRİMİ GÖNDER'));
    await tester.pump();
    expect(find.text('Lütfen açıklama yaz'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
