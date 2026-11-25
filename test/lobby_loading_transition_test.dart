import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/lobby/lobby_columns.dart';
import 'package:okeyix/ui/lobby/lobby_shimmer_loaders.dart';

void main() {
  for (final size in [
    const Size(568, 320),
    const Size(640, 360),
    const Size(852, 393),
  ]) {
    testWidgets('shared shimmer keeps the 2-2-1 layout at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final ready = ValueNotifier(false);
      addTearDown(ready.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SafeArea(
              child: ValueListenableBuilder<bool>(
                valueListenable: ready,
                builder: (_, value, _) => LobbyCardsReveal(
                  ready: value,
                  child: const LobbyColumns(
                    leagues: ColoredBox(
                      key: ValueKey('ready-leagues'),
                      color: Colors.green,
                    ),
                    tables: ColoredBox(
                      key: ValueKey('ready-quick-play'),
                      color: Colors.blue,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(LobbyShimmer), findsOneWidget);
      final cards = List.generate(
        5,
        (i) => tester.getRect(find.byKey(ValueKey('league-skeleton-$i'))),
      );
      expect(cards[0].top, cards[1].top);
      expect(cards[2].top, cards[3].top);
      expect(cards[4].width, greaterThan(cards[0].width * 2));
      for (final card in cards) {
        expect(card.bottom, lessThanOrEqualTo(size.height));
        expect(card.height, greaterThan(0));
      }
      expect(find.byType(Scrollable), findsNothing);
      ready.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final leagueFade = find
          .ancestor(
            of: find.byKey(const ValueKey('ready-leagues')),
            matching: find.byType(FadeTransition),
          )
          .first;
      final quickFade = find
          .ancestor(
            of: find.byKey(const ValueKey('ready-quick-play')),
            matching: find.byType(FadeTransition),
          )
          .first;
      expect(tester.widget(leagueFade), same(tester.widget(quickFade)));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(LobbyShimmer), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('cached cards appear immediately without a loading frame', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LobbyCardsReveal(ready: true, child: Text('Cached lobby')),
        ),
      ),
    );
    expect(find.text('Cached lobby'), findsOneWidget);
    expect(find.byType(LobbyShimmer), findsNothing);
    final fade = tester.widget<FadeTransition>(
      find.byType(FadeTransition).first,
    );
    expect(fade.opacity.value, 1);
  });
}
