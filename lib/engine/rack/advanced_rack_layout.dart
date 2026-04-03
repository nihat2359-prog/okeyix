import '../models/tile.dart';

class AdvancedRackLayout {
  static List<TileModel?> layout(List<TileModel> tiles) {
    final working = List<TileModel>.from(tiles);
    final result = List<TileModel?>.filled(26, null);

    int topIndex = 0;
    int bottomIndex = 13;

    // Seri bul
    for (final color in TileColor.values) {
      final sameColor =
          working.where((t) => !t.isJoker && t.color == color).toList()
            ..sort((a, b) => a.value.compareTo(b.value));

      for (int i = 0; i < sameColor.length - 2; i++) {
        final a = sameColor[i];
        final b = sameColor[i + 1];
        final c = sameColor[i + 2];

        if (b.value == a.value + 1 && c.value == b.value + 1) {
          if (topIndex + 2 <= 12) {
            result[topIndex] = a;
            result[topIndex + 1] = b;
            result[topIndex + 2] = c;

            working.remove(a);
            working.remove(b);
            working.remove(c);

            topIndex += 4; // 3 taş + 1 boşluk
          }
        }
      }
    }

    // Kalanları alt sıraya koy
    for (final t in working) {
      if (bottomIndex > 25) break;
      result[bottomIndex++] = t;
    }

    return result;
  }
}
