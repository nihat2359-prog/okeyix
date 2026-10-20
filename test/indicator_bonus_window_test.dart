import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/game/okey_game.dart';

void main() {
  for (final startingTurn in [0, 1]) {
    test(
      'indicator remains available before own first draw, starting turn $startingTurn',
      () {
        final game = OkeyGame(tableId: 'local-test', isCreator: false);
        game.debugIndicatorBonusState(turn: startingTurn);
        expect(game.canClaimIndicatorBonus, isTrue);
        // A first discard and the opponent's turn do not consume the right.
        game.currentTurn = 1 - startingTurn;
        expect(game.canClaimIndicatorBonus, isTrue);
        game.currentTurn = startingTurn;
        expect(game.canClaimIndicatorBonus, isTrue);
        game.debugIndicatorBonusState(drawn: true, turn: startingTurn);
        expect(game.canClaimIndicatorBonus, isFalse);
        game.currentTurn = 1 - startingTurn;
        expect(game.canClaimIndicatorBonus, isFalse);
      },
    );
  }
  test('claimed bonus cannot repeat; next round restores the right', () {
    final game = OkeyGame(tableId: 'local-test', isCreator: false);
    game.debugIndicatorBonusState(claimed: true);
    expect(game.canClaimIndicatorBonus, isFalse);
    game.debugIndicatorBonusState();
    expect(game.canClaimIndicatorBonus, isTrue);
    game.debugIndicatorBonusState(playing: false);
    expect(game.canClaimIndicatorBonus, isFalse);
  });
}
