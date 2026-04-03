import '../models/tile.dart';

class SimpleRackLayout {
  static List<TileModel?> arrange(List<TileModel> tiles) {
    final working = List<TileModel>.from(tiles);

    final result = List<TileModel?>.filled(26, null);

    int bottomIndex = 0; // 0–12
    int topIndex = 13; // 13–25

    final Map<int, List<TileModel>> byValue = {};

    for (final t in working) {
      byValue.putIfAbsent(t.value, () => []).add(t);
    }

    // 🔹 PERLER ÜST SIRAYA
    for (final entry in byValue.entries) {
      final group = entry.value;

      final uniqueColors = <TileColor>{};
      final perGroup = <TileModel>[];

      for (final t in group) {
        if (!uniqueColors.contains(t.color)) {
          uniqueColors.add(t.color);
          perGroup.add(t);
        }
      }

      if (perGroup.length >= 3) {
        for (final t in perGroup.take(3)) {
          if (topIndex < 26) {
            result[topIndex++] = t;
            working.remove(t);
          }
        }
        topIndex++; // boşluk bırak
      }
    }

    // 🔹 KALANLAR ALT SIRAYA
    working.sort((a, b) {
      if (a.value == b.value) {
        return a.color.index.compareTo(b.color.index);
      }
      return a.value.compareTo(b.value);
    });

    for (final t in working) {
      if (bottomIndex < 13) {
        result[bottomIndex++] = t;
      }
    }

    return result;
  }
}
