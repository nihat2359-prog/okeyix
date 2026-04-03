import 'dart:math';
import 'package:flutter/material.dart';

class LobbyLoading extends StatefulWidget {
  const LobbyLoading({super.key});

  @override
  State<LobbyLoading> createState() => _LobbyLoadingState();
}

class _LobbyLoadingState extends State<LobbyLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();

    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 56,
        height: 56,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            return CustomPaint(painter: _LoaderPainter(controller.value));
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

class _LoaderPainter extends CustomPainter {
  final double progress;

  _LoaderPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    final paint = Paint()
      ..color = const Color(0xFFE7C06A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final glow = Paint()
      ..color = const Color(0x55E7C06A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final start = progress * 2 * pi;
    const sweep = pi * 1.4;

    canvas.drawArc(rect.deflate(4), start, sweep, false, glow);
    canvas.drawArc(rect.deflate(4), start, sweep, false, paint);
  }

  @override
  bool shouldRepaint(_LoaderPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
