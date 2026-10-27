import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/game_waiting_panel.dart';

void main() {
  for (final size in [const Size(568, 320), const Size(932, 430)]) {
    for (final count in [-1, 5, 0]) {
      testWidgets('waiting panel $size state $count fits large landscape text', (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(MaterialApp(home: MediaQuery(
          data: MediaQueryData(size: size, textScaler: TextScaler.linear(2),
            padding: const EdgeInsets.fromLTRB(44, 12, 24, 21)),
          child: Scaffold(body: GameWaitingPanel(
            players: count < 0 ? 1 : 2, capacity: 2, countdown: count < 0 ? 0 : count)),
        )));
        expect(tester.takeException(), isNull);
        final panel = tester.getRect(find.byType(DecoratedBox).last);
        expect(panel.width, closeTo((size.width * .30).clamp(196.0, 224.0), .01));
        if (count == 5) {
          expect(find.text('5'), findsOneWidget);
          expect(tester.widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator)).value, 1);
        }
        expect(tester.binding.transientCallbackCount, 0);
      });
    }
  }
}
