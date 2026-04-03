import 'package:flame/components.dart';
import 'rack_config.dart';

class RackSlotGenerator {
  static List<Vector2> generate() {
    final slots = <Vector2>[];

    final leftEdge = RackConfig.rackLeftOffset;

    final bottomY = 900 - RackConfig.rackBottomOffset;

    for (int row = 0; row < RackConfig.rows; row++) {
      for (int col = 0; col < RackConfig.columns; col++) {
        final x =
            leftEdge +
            col * (RackConfig.tileWidth + RackConfig.gap) +
            RackConfig.tileWidth / 2;

        final y =
            bottomY -
            row * (RackConfig.tileHeight + RackConfig.rowGap) -
            RackConfig.tileHeight / 2;

        slots.add(Vector2(x, y));
      }
    }

    return slots;
  }
}
