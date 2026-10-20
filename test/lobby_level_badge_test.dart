import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/lobby/lobby_level_badge.dart';

void main() {
  for (final sample in [
    (23900, 23, .9),
    (24000, 24, 0.0),
    (34000, 34, 0.0),
    (34900, 34, .9),
    (100999, 100, .999),
    (1000000, 1000, 0.0),
  ]) {
    testWidgets(
      'level badge ${sample.$1} has uncapped level and accurate progress',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: LobbyLevelBadge(rating: sample.$1)),
          ),
        );
        expect(find.text('Seviye ${sample.$2}'), findsOneWidget);
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator),
              )
              .value,
          closeTo(sample.$3, .00001),
        );
        final next = sample.$2 + 1;
        expect(
          find.byTooltip('Seviye $next için ${next * 1000 - sample.$1} puan'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
