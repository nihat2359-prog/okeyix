import '../../engine/models/tile.dart';
import '../rack/tile_component.dart';

TileColorType mapTileColor(TileColor color) {
  switch (color) {
    case TileColor.red:
      return TileColorType.red;
    case TileColor.blue:
      return TileColorType.blue;
    case TileColor.black:
      return TileColorType.black;
    case TileColor.yellow:
      return TileColorType.yellow;
  }
}
