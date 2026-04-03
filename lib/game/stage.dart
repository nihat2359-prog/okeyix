import 'package:flame/components.dart';
import 'okey_game.dart';

class Stage extends Component with HasGameReference<OkeyGame> {
  @override
  Future<void> onLoad() async {
    final image = await game.images.load('table.png');

    final table = SpriteComponent(
      sprite: Sprite(image),
      size: Vector2(1600, 900),
      position: Vector2(800, 450),
      anchor: Anchor.center,
    );

    add(table);
  }
}
