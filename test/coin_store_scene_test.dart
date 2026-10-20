import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/store/coin_store_scene.dart';
import 'package:okeyix/ui/store/coin_store_artwork.dart';

const ids = [
  'coin_pack_baslangic',
  'coin_pack_standart',
  'coin_pack_elit',
  'coin_pack_mega',
];
const amounts = [80000, 200000, 600000, 2000000];
const labels = ['BAŞLANGIÇ', 'STANDART', 'ELİT', 'MEGA'];
// Fixture prices only; the app always passes ProductDetails.price.
const prices = ['₺39,99', '₺79,99', '₺159,99', '₺349,99'];

Future<void> store(
  WidgetTester tester,
  Size size,
  double scale,
  List<String> calls, {
  bool unavailable = false,
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
          textScaler: TextScaler.linear(scale),
        ),
        child: child!,
      ),
      home: CoinStoreScene(
        balance: 1234567,
        onClose: () => calls.add('close'),
        offers: [
          for (var i = 0; i < 4; i++)
            CoinStoreOffer(
              id: ids[i],
              title: labels[i],
              coins: amounts[i],
              price: unavailable ? '...' : prices[i],
              onBuy: unavailable ? null : () => calls.add(ids[i]),
            ),
        ],
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
    const Size(568, 320),
    const Size(640, 360),
    const Size(844, 390),
    const Size(932, 430),
    const Size(1024, 600),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'store $size text $scale has four full packages and purchase actions',
        (tester) async {
          final calls = <String>[];
          await store(tester, size, scale, calls);
          double? previousTop;
          double right = 44;
          for (var i = 0; i < ids.length; i++) {
            final card = tester.getRect(
              find.byKey(ValueKey('store-offer-${ids[i]}')),
            );
            expect(card.left, greaterThanOrEqualTo(right));
            expect(card.right, lessThanOrEqualTo(size.width - 24));
            expect(card.bottom, lessThanOrEqualTo(size.height - 21));
            if (previousTop != null) expect(card.top, previousTop);
            previousTop = card.top;
            right = card.right;
            expect(find.text(labels[i]), findsOneWidget);
            expect(find.text(prices[i]), findsOneWidget);
            final buy = find.byKey(ValueKey('store-buy-${ids[i]}'));
            expect(buy.hitTestable(), findsOneWidget);
            await tester.tap(buy);
          }
          expect(calls, ids);
          await tester.tap(find.byKey(const ValueKey('store-close')));
          expect(calls.last, 'close');
          expect(find.text('EN İYİ FİYAT'), findsOneWidget);
          expect(
            tester
                .widgetList<CoinStoreArtwork>(find.byType(CoinStoreArtwork))
                .map((a) => a.tier),
            [0, 1, 2, 3],
          );
          expect(find.byType(BackdropFilter), findsNothing);
          await tester.pumpAndSettle();
          expect(tester.binding.transientCallbackCount, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('unavailable products cannot purchase', (tester) async {
    final calls = <String>[];
    await store(tester, const Size(640, 360), 1, calls, unavailable: true);
    for (final id in ids) {
      expect(
        tester
            .widget<TextButton>(find.byKey(ValueKey('store-buy-$id')))
            .onPressed,
        isNull,
      );
    }
    expect(calls, isEmpty);
  });
  for (final size in [const Size(640, 360), const Size(932, 430)]) {
    testWidgets('store golden $size', (tester) async {
      await store(tester, size, 1, []);
      await expectLater(
        find.byType(CoinStoreScene),
        matchesGoldenFile(
          'goldens/coin_store_${size.width.toInt()}x${size.height.toInt()}.png',
        ),
      );
    });
  }
}
