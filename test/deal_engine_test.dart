import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/engine/deal/deal_engine.dart';
import 'package:okeyix/engine/deck/deck_generator.dart';
import 'package:okeyix/engine/deck/shuffler.dart';

void main() {
  test('deal creates correct hand sizes for 4 players', () {
    final fullDeck = DeckGenerator.generateFullDeck();
    final shuffled = DeckShuffler.shuffle(fullDeck, 42);
    final result = DealEngine.deal(deck: shuffled, playerCount: 4);

    expect(result.playerHands.length, 4);
    expect(result.playerHands[0].length, 15);
    expect(result.playerHands[1].length, 14);
    expect(result.playerHands[2].length, 14);
    expect(result.playerHands[3].length, 14);
  });

  test('deal conserves total tile count', () {
    final fullDeck = DeckGenerator.generateFullDeck();
    final shuffled = DeckShuffler.shuffle(fullDeck, 99);
    final result = DealEngine.deal(deck: shuffled, playerCount: 4);

    final dealtCount = result.playerHands.fold<int>(
      0,
      (sum, hand) => sum + hand.length,
    );

    // 106 full deck = 1 indicator + dealt + remaining closed pile
    expect(1 + dealtCount + result.closedPile.length, 106);
  });
}
