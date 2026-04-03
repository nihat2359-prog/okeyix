import '../models/tile.dart';

class DealResult {
  final List<List<TileModel>> playerHands;
  final List<TileModel> closedPile;
  final TileModel indicatorTile;

  DealResult({
    required this.playerHands,
    required this.closedPile,
    required this.indicatorTile,
  });
}

class DealEngine {
  static DealResult deal({
    required List<TileModel> deck,
    required int playerCount,
  }) {
    final indicator = deck.removeLast();
    final okeyValue = indicator.value == 13 ? 1 : indicator.value + 1;
    final okeyColor = indicator.color;

    for (int i = 0; i < deck.length; i++) {
      final t = deck[i];

      if (t.isFakeJoker) {
        deck[i] = TileModel(
          value: okeyValue,
          color: okeyColor,
          isFakeJoker: true,
        );
      } else if (t.value == okeyValue && t.color == okeyColor) {
        deck[i] = TileModel(value: t.value, color: t.color, isJoker: true);
      }
    }

    final List<List<TileModel>> hands = List.generate(playerCount, (_) => []);
    int index = 0;

    for (int round = 0; round < 14; round++) {
      for (int p = 0; p < playerCount; p++) {
        hands[p].add(deck[index++]);
      }
    }

    hands[0].add(deck[index++]);

    final closedPile = deck.sublist(index);

    return DealResult(
      playerHands: hands,
      closedPile: closedPile,
      indicatorTile: indicator,
    );
  }
}
