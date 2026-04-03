import 'okey_tile.dart';

enum MeldType { set, run }

class Meld {
  final MeldType type;
  final List<OkeyTile> tiles;

  Meld(this.type, this.tiles);

  int get score => tiles.length;
}
