import 'okey_tile.dart';
import 'meld.dart';
import "package:okeyix/engine/models/tile.dart";

class MeldFinder {
  static List<Meld> findAll(List<OkeyTile> tiles, int jokerCount) {
    List<Meld> result = [];

    result.addAll(_findSets(tiles, jokerCount));
    result.addAll(_findRuns(tiles, jokerCount));

    return result;
  }

  static List<Meld> _findSets(List<OkeyTile> tiles, int jokerCount) {
    Map<int, List<OkeyTile>> byNumber = {};

    for (var t in tiles) {
      byNumber.putIfAbsent(t.number, () => []).add(t);
    }

    List<Meld> sets = [];

    for (var entry in byNumber.entries) {
      var group = entry.value;

      // 🔹 Aynı sayıda ama renkleri unique yap
      Map<TileColor, OkeyTile> uniqueColors = {};
      for (var t in group) {
        uniqueColors[t.color] = t; // aynı renk varsa overwrite olur
      }

      final uniqueList = uniqueColors.values.toList();

      // 3 farklı renk varsa
      if (uniqueList.length >= 3) {
        sets.add(Meld(MeldType.set, uniqueList.take(3).toList()));
      }

      // 4 farklı renk varsa
      if (uniqueList.length == 4) {
        sets.add(Meld(MeldType.set, uniqueList));
      }

      // 2 farklı renk + joker
      if (uniqueList.length == 2 && jokerCount > 0) {
        sets.add(
          Meld(MeldType.set, [
            ...uniqueList,
            OkeyTile(
              number: entry.key,
              color: TileColor.red, // dummy
              isJoker: true,
            ),
          ]),
        );
      }
    }

    return sets;
  }

  static List<Meld> _findRuns(List<OkeyTile> tiles, int jokerCount) {
    Map<TileColor, List<OkeyTile>> byColor = {};

    for (var t in tiles) {
      byColor.putIfAbsent(t.color, () => []).add(t);
    }

    List<Meld> runs = [];

    for (var entry in byColor.entries) {
      var sorted = entry.value..sort((a, b) => a.number.compareTo(b.number));

      for (int i = 0; i < sorted.length; i++) {
        List<OkeyTile> temp = [sorted[i]];

        for (int j = i + 1; j < sorted.length; j++) {
          if (sorted[j].number == temp.last.number + 1) {
            temp.add(sorted[j]);

            if (temp.length >= 3) {
              runs.add(Meld(MeldType.run, List.from(temp)));
            }
          } else {
            break;
          }
        }
      }
    }

    return runs;
  }
}
