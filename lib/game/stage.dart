import 'package:flame/components.dart';
import 'okey_game.dart';

class Stage extends Component with HasGameReference<OkeyGame> {
  @override
  Future<void> onLoad() async {
    final image = await game.images.load('rack.png');

    final rack = SpriteComponent(
      sprite: Sprite(image),
      size: Vector2(1380, 400), // sahneye göre
      position: Vector2(810, 900 - 180), // alt merkez
      anchor: Anchor.center,
    );

    add(rack);
  }
}
