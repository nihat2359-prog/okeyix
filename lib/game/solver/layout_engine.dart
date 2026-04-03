import 'okey_tile.dart';
import 'meld.dart';

class LayoutEngine {
  static List<OkeyTile?> buildLayout(
    List<OkeyTile> allTiles,
    List<Meld> melds,
    int totalSlots,
  ) {
    List<OkeyTile?> slots = List.filled(totalSlots, null);

    int bottomStart = 0; // 0-12
    int topStart = 13; // 13-25

    List<OkeyTile> used = [];

    // 🔹 PER ve RUN'lar ÜST SIRAYA
    for (var meld in melds) {
      for (var t in meld.tiles) {
        if (topStart >= 26) break;
        slots[topStart++] = t;
        used.add(t);
      }
      topStart++; // boşluk
    }

    // 🔹 Boşta kalanlar ALT SIRAYA
    var loose = allTiles.where((t) => !used.contains(t)).toList();

    loose.sort((a, b) {
      if (a.number == b.number) {
        return a.color.index.compareTo(b.color.index);
      }
      return a.number.compareTo(b.number);
    });

    for (var t in loose) {
      if (bottomStart >= 13) break;
      slots[bottomStart++] = t;
    }

    return slots;
  }
}
