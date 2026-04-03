import 'package:okeyix/engine/models/tile.dart';

class OkeyTile {
  final int number; // 1-13
  final TileColor color;
  final bool isJoker;

  OkeyTile({required this.number, required this.color, this.isJoker = false});

  String get id => "$number-$color-${isJoker ? 1 : 0}";
}
