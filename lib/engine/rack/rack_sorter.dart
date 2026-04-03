import '../models/tile.dart';

class RackSorter {
  static List<TileModel> sort(List<TileModel> tiles) {
    final list = List<TileModel>.from(tiles);

    list.sort((a, b) {
      if (a.isJoker) return 1;
      if (b.isJoker) return -1;

      if (a.color.index != b.color.index) {
        return a.color.index.compareTo(b.color.index);
      }

      return a.value.compareTo(b.value);
    });

    return list;
  }
}
