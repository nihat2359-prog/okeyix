import "package:okeyix/engine/models/tile.dart";
import 'okey_tile.dart';

class TileAdapter {
  static OkeyTile toSolver(TileModel model) {
    return OkeyTile(
      number: model.value,
      color: model.color,
      isJoker: model.isJoker,
    );
  }

  static TileModel? findOriginal(
    OkeyTile solverTile,
    List<TileModel> originals,
    Set<TileModel> used,
  ) {
    for (var t in originals) {
      if (used.contains(t)) continue;

      if (solverTile.isJoker && t.isJoker) {
        used.add(t);
        return t;
      }

      if (!solverTile.isJoker &&
          t.value == solverTile.number &&
          t.color == solverTile.color) {
        used.add(t);
        return t;
      }
    }
    return null;
  }
}
