import '../models/tile.dart';

class DeckGenerator {
  static List<TileModel> generateFullDeck() {
    final List<TileModel> tiles = [];

    for (final color in TileColor.values) {
      for (int set = 0; set < 2; set++) {
        for (int value = 1; value <= 13; value++) {
          tiles.add(TileModel(value: value, color: color));
        }
      }
    }

    // 2 joker
    tiles.add(
      const TileModel(value: 0, color: TileColor.red, isFakeJoker: true),
    );
    tiles.add(
      const TileModel(value: 0, color: TileColor.red, isFakeJoker: true),
    );

    return tiles;
  }
}
