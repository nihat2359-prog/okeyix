import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/table_join_notice.dart';

void main() {
  for (final size in [const Size(568, 320), const Size(844, 390)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('join notice stays at the bottom safe area at $size text $scale', (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var taps = 0;
        await tester.pumpWidget(MaterialApp(home: MediaQuery(
          data: MediaQueryData(size: size,
            viewPadding: const EdgeInsets.fromLTRB(44, 12, 24, 21),
            textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: Stack(fit: StackFit.expand, children: [
            GestureDetector(behavior: HitTestBehavior.opaque,
              onTap: () => taps++, child: const SizedBox.expand()),
            const TableJoinNotice(names: ['Uzun oyuncu ismi denemesi']),
          ])),
        )));
        await tester.pumpAndSettle();
        final notice = find.byKey(const ValueKey('table-join-notice'));
        final rect = tester.getRect(notice);
        expect(rect.center.dy, greaterThan(size.height * .7));
        expect(rect.right, lessThanOrEqualTo(size.width - 24));
        expect(rect.bottom, closeTo(size.height - 21 - 8, .01));
        expect(find.text('Masaya katıldı'), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.tapAt(rect.center);
        expect(taps, 1);
      });
    }
  }
}
