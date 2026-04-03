import 'okey_tile.dart';
import 'meld.dart';
import 'meld_finder.dart';

class SolverEngine {
  final List<OkeyTile> tiles;

  SolverEngine(this.tiles);

  List<Meld> solve() {
    int jokerCount = tiles.where((t) => t.isJoker).length;
    List<OkeyTile> nonJokers = tiles.where((t) => !t.isJoker).toList();

    List<Meld> best = [];
    int bestScore = 0;

    void backtrack(List<OkeyTile> remaining, int jokers, List<Meld> current) {
      final melds = MeldFinder.findAll(remaining, jokers);

      bool progressed = false;

      for (var meld in melds) {
        progressed = true;

        List<OkeyTile> next = List.from(remaining);
        int nextJoker = jokers;

        for (var t in meld.tiles) {
          if (!t.isJoker) {
            next.remove(t);
          } else {
            nextJoker--;
          }
        }

        current.add(meld);
        backtrack(next, nextJoker, current);
        current.removeLast();
      }

      if (!progressed) {
        int score = current.fold(0, (sum, m) => sum + m.score);

        if (score > bestScore) {
          bestScore = score;
          best = List.from(current);
        }
      }
    }

    backtrack(nonJokers, jokerCount, []);

    return best;
  }
}
