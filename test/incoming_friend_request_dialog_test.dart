import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/incoming_friend_request_dialog.dart';

void main() {
  for (final size in [const Size(568, 320), const Size(844, 390)]) {
    testWidgets('friend request actions fit landscape $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final actions = <String>[];
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: MediaQuery(
        data: MediaQueryData(size: size, textScaler: const TextScaler.linear(1.3)),
        child: IncomingFriendRequestDialog(
          username: 'Uzun oyuncu adı uzun oyuncu adı',
          onAccept: () => actions.add('accept'),
          onReject: () => actions.add('reject'),
          onBlock: () => actions.add('block'),
          onClose: () => actions.add('close'),
        ),
      ))));
      for (final label in ['Kabul et', 'Reddet', 'Engelle']) {
        final rect = tester.getRect(find.text(label));
        expect(rect.bottom, lessThan(size.height));
        expect(rect.left, greaterThanOrEqualTo(0));
        await tester.tap(find.text(label));
      }
      await tester.tap(find.byTooltip('Vazgeç'));
      expect(actions, ['accept', 'reject', 'block', 'close']);
      expect(tester.takeException(), isNull);
    });
  }
}
