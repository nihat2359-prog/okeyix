import 'package:flame/components.dart';
import 'package:flutter/material.dart';

class SeatComponent extends PositionComponent {
  final int seatIndex;
  final Map<String, dynamic>? player;
  final bool showInvite;

  SeatComponent({
    required this.seatIndex,
    required Vector2 position,
    this.player,
    this.showInvite = false,
  }) {
    this.position = position;
    anchor = Anchor.center;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    final bg = CircleComponent(
      radius: 40,
      paint: Paint()..color = Colors.black54,
      anchor: Anchor.center,
    );

    add(bg);

    if (player != null) {
      final text = TextComponent(
        text: player!["user_id"].toString().substring(0, 6),
        anchor: Anchor.center,
        textRenderer: TextPaint(
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      );

      add(text);
    } else if (showInvite) {
      final inviteText = TextComponent(
        text: "DAVET",
        anchor: Anchor.center,
        textRenderer: TextPaint(
          style: const TextStyle(
            color: Colors.amber,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

      add(inviteText);
    }
  }
}
