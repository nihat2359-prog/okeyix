import '../models/tile.dart';

class SmartRackOrganizer {
  static List<TileModel> organize(List<TileModel> tiles) {
    final remaining = List<TileModel>.from(tiles);
    final result = <TileModel>[];

    // Jokerleri ayır
    final jokers = remaining.where((t) => t.isJoker).toList();
    remaining.removeWhere((t) => t.isJoker);

    // 1️⃣ Seri (aynı renk ardışık)
    for (final color in TileColor.values) {
      final colorTiles = remaining.where((t) => t.color == color).toList()
        ..sort((a, b) => a.value.compareTo(b.value));

      for (int i = 0; i < colorTiles.length - 2; i++) {
        final a = colorTiles[i];
        final b = colorTiles[i + 1];
        final c = colorTiles[i + 2];

        if (b.value == a.value + 1 && c.value == b.value + 1) {
          result.addAll([a, b, c]);
          remaining.remove(a);
          remaining.remove(b);
          remaining.remove(c);
        }
      }
    }

    // 2️⃣ Set (aynı sayı farklı renk)
    for (int value = 1; value <= 13; value++) {
      final sameValue = remaining.where((t) => t.value == value).toList();

      if (sameValue.length >= 3) {
        result.addAll(sameValue.take(3));
        remaining.removeWhere((t) => t.value == value);
      }
    }

    // 3️⃣ Joker ile eksik tamamla (basit versiyon)
    if (jokers.isNotEmpty && remaining.length >= 2) {
      final a = remaining[0];
      final b = remaining[1];

      result.addAll([a, b, jokers.first]);
      remaining.remove(a);
      remaining.remove(b);
      jokers.removeAt(0);
    }

    // 4️⃣ Kalanları sırala
    remaining.sort((a, b) {
      if (a.color.index != b.color.index) {
        return a.color.index.compareTo(b.color.index);
      }
      return a.value.compareTo(b.value);
    });

    result.addAll(remaining);
    result.addAll(jokers);

    return result;
  }
}
