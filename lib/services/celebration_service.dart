import 'dart:math';
import 'package:flutter/material.dart';
import '../main.dart';

class CelebrationService {
  static void showConfetti() {
    final overlay = overlayKey.currentState;
    if (overlay == null) return;

    late OverlayEntry entry;

    entry = OverlayEntry(builder: (_) => const _ConfettiOverlay());

    overlay.insert(entry);

    // 🔥 otomatik kaldır
    Future.delayed(const Duration(milliseconds: 1200), () {
      entry.remove();
    });
  }
}

class _ConfettiOverlay extends StatefulWidget {
  const _ConfettiOverlay();

  @override
  State<_ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<_ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;

  final colors = [
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.yellow,
    Colors.purple,
    Colors.orange,
    Colors.cyan,
    Colors.pink,
  ];

  @override
  void initState() {
    super.initState();

    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final v = _c.value;

          final size = MediaQuery.of(context).size;

          return Stack(
            children: List.generate(40, (i) {
              final rand = Random(i);

              final startX = size.width / 2;
              final startY = size.height / 3;

              final dx = (rand.nextDouble() - 0.5) * size.width;
              final dy = rand.nextDouble() * size.height;

              final rotation = rand.nextDouble() * pi;

              final color = colors[i % colors.length];

              return Positioned(
                left: startX,
                top: startY,
                child: Transform.translate(
                  offset: Offset(dx * v, dy * v),
                  child: Transform.rotate(
                    angle: rotation * v * 3, // 🔥 DÖNÜŞ
                    child: Opacity(
                      opacity: (1 - v).clamp(0.0, 1.0),
                      child: Container(
                        width: rand.nextDouble() * 8 + 4,
                        height: rand.nextDouble() * 8 + 4,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(
                            rand.nextBool() ? 0 : 4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
