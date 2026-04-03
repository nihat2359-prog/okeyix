import 'dart:math';
import '../models/tile.dart';

class DeckShuffler {
  static List<TileModel> shuffle(List<TileModel> deck, int seed) {
    final random = Random(seed);
    final list = List<TileModel>.from(deck);

    list.shuffle(random);

    return list;
  }
}
