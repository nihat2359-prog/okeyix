import 'package:okeyix/engine/models/tile.dart';

class OkeySolver {
  static List<List<TileModel>> solve(List<TileModel> tiles) {
    final results = <List<TileModel>>[];

    // 1️⃣ SERİLER
    for (final color in TileColor.values) {
      final sameColor =
          tiles.where((t) => !t.isJoker && t.color == color).toList()
            ..sort((a, b) => a.value.compareTo(b.value));

      for (int i = 0; i < sameColor.length - 2; i++) {
        final group = <TileModel>[sameColor[i]];

        int current = sameColor[i].value;

        for (int j = i + 1; j < sameColor.length; j++) {
          if (sameColor[j].value == current + 1) {
            group.add(sameColor[j]);
            current++;
          } else if (sameColor[j].value > current + 1) {
            break;
          }
        }

        if (group.length >= 3) {
          results.add(List.from(group));
        }
      }
    }

    // 2️⃣ GRUPLAR (aynı sayı farklı renk)
    for (int number = 1; number <= 13; number++) {
      final sameNumber = tiles
          .where((t) => !t.isJoker && t.value == number)
          .toList();

      if (sameNumber.length >= 3) {
        results.add(List.from(sameNumber.take(4)));
      }
    }

    return results;
  }

  static List<List<TileModel>> selectBest(
    List<List<TileModel>> candidates,
    List<TileModel> tiles,
  ) {
    final used = <TileModel>{};
    final result = <List<TileModel>>[];

    candidates.sort((a, b) => b.length.compareTo(a.length));

    for (final combo in candidates) {
      if (combo.any((t) => used.contains(t))) continue;

      result.add(combo);
      used.addAll(combo);
    }

    return result;
  }

  static List<TileModel?> buildLayout(
    List<List<TileModel>> combos,
    List<TileModel> allTiles,
  ) {
    final layout = List<TileModel?>.filled(26, null);

    int bottom = 13; // 🔥 perler ALT sıraya
    final used = <TileModel>{};

    // 1️⃣ Önce kombinasyonları ALT sıraya koy
    for (final combo in combos) {
      if (bottom + combo.length > 26) break;

      for (final t in combo) {
        layout[bottom++] = t;
        used.add(t);
      }

      bottom++; // araya boşluk
    }

    // 2️⃣ Kalan taşları ÜST sıraya koy
    int top = 0;

    for (final t in allTiles) {
      if (!used.contains(t)) {
        if (top > 12) break;
        layout[top++] = t;
      }
    }

    return layout;
  }
}
