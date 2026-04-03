import 'package:flame/components.dart';
import 'package:flutter/material.dart';

class WaitingComponent extends PositionComponent {
  final String text;

  WaitingComponent({required this.text, required Vector2 position}) {
    this.position = position;
    anchor = Anchor.center;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    final textComponent = TextComponent(
      text: text,
      anchor: Anchor.center,
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 36,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    add(textComponent);
  }
}
