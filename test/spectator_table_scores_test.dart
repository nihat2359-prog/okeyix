import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:okeyix/game/spectator_game.dart';
import 'package:okeyix/ui/spectator_table_scores.dart';

class _Client extends Fake implements SupabaseClient {}

void main() {
  test('Flame background is transparent outside and inside its viewport', () {
    final game = SpectatorGame(tableId: 'test', realtimeClient: _Client());
    expect(game.backgroundColor(), const Color(0x00000000));
  });
  for (final size in [const Size(568, 320), const Size(844, 390)]) {
    testWidgets('two compact player rows and full-screen lobby at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: const TextScaler.linear(1.3),
            ),
            child: const Scaffold(
              body: Stack(
                children: [
                  Positioned.fill(child: SpectatorBackdrop()),
                  Positioned(
                    top: 62,
                    left: 14,
                    child: SpectatorTableScores(
                      players: [
                        {
                          'username': 'Uzun Oyuncu İsmi',
                          'wins': 12,
                          'losses': 3,
                        },
                        {'username': 'Rakip', 'wins': 3, 'losses': 12},
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('Galibiyet'), findsNWidgets(2));
      expect(find.text('Mağlubiyet'), findsNWidgets(2));
      final panel = tester.getRect(find.byType(SpectatorTableScores));
      expect(panel.width, lessThanOrEqualTo(260));
      expect(panel.top, 62);
      expect(panel.bottom, lessThan(130));
      final backdrop = tester.getRect(find.byType(SpectatorBackdrop));
      expect(backdrop, Offset.zero & size);
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.fill);
      expect(
        (image.image as AssetImage).assetName,
        'assets/images/lobby/lobby.png',
      );
      expect(tester.takeException(), isNull);
    });
  }
}
