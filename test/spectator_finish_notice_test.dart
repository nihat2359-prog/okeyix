import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/spectator_finish_notice.dart';

void main() {
  for (final size in [const Size(568, 320), const Size(932, 430)]) {
    testWidgets('spectator result fits notched landscape $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              padding: const EdgeInsets.fromLTRB(59, 0, 44, 21),
              textScaler: TextScaler.linear(2),
            ),
            child: const Scaffold(
              body: SpectatorFinishNotice(
                winnerName: 'Uzun İsimli Kazanan Oyuncu',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ELİN KAZANANI'), findsOneWidget);
      expect(find.text('Uzun İsimli Kazanan Oyuncu'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
