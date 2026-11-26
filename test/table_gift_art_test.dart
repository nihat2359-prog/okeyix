import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/table_gift_art.dart';

void main() {
  testWidgets('approved tea asset fits catalog and table sizes', (
    tester,
  ) async {
    for (final size in [36.0, 48.0, 84.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: TableGiftArt(giftId: 'cay', width: size, height: size),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final image = tester.widget<Image>(find.byType(Image));
      expect(
        (image.image as AssetImage).assetName,
        'assets/images/hediyeler/cay.png',
      );
      expect(tester.getSize(find.byType(Image)), Size.square(size));
      expect(tester.takeException(), isNull);
    }
  });
}
