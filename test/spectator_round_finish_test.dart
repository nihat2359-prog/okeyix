import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/engine/models/tile.dart';
import 'package:okeyix/game/rack/tile_component.dart';
import 'package:okeyix/game/spectator_game.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('finish clears both discard piles and blocks moves until playing', () {
    final client = SupabaseClient('https://example.supabase.co', 'test-key');
    final game = SpectatorGame(tableId: 'table', realtimeClient: client);
    TileComponent tile(String id) => TileComponent(
      tile: TileModel(id: id, value: 1, color: TileColor.red),
      position: Vector2.zero(),
    );
    game.discardLeftStack.add(tile('left'));
    game.discardRightStack.add(tile('right'));
    game.finishRound();
    expect(game.discardLeftStack, isEmpty);
    expect(game.discardRightStack, isEmpty);
    // These would access uninitialized table coordinates if not blocked.
    expect(() => game.animateDrawFromDeck(0, {}), returnsNormally);
    expect(() => game.animatePickupFromDiscard(1, {}), returnsNormally);
    game.applyTableState({'status': 'waiting'});
    expect(() => game.animateDrawFromDeck(0, {}), returnsNormally);
    game.applyTableState({'status': 'playing'});
    expect(() => game.animateDrawFromDeck(0, {}), throwsA(isA<Error>()));
  });
}
