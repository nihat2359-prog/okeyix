import 'package:flutter/material.dart';
import 'dart:math' as math;

// Create button outer-arc fine tuning (single place to tweak).
class _CreateButtonOuterArcStyle {
  static const Color color = Color(0xB3D9B97A);
  static const double strokeWidth = 1.4;
  static const double inset = -0.1;
  static const double startAngle = -0.40; // radians
  static const double sweepAngle = -2.35; // radians (shorter than half circle)
}

class CreateButton extends StatefulWidget {
  final VoidCallback onTap;

  const CreateButton({super.key, required this.onTap});

  @override
  State<CreateButton> createState() => _CreateButtonState();
}

class _CreateButtonState extends State<CreateButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,

      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1,
        duration: const Duration(milliseconds: 120),

        child: AnimatedBuilder(
          animation: _glowController,
          builder: (context, child) {
            final glow = 0.4 + (_glowController.value * 0.4);

            return Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE7C66A).withOpacity(glow),
                    blurRadius: 20,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.8),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  /// CHIP BASE (no full border)
                  Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFF22272E), Color(0xFF12171D)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),

                  /// Top-only border arc (no border on lower half).
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _TopArcBorderPainter(
                          color: _CreateButtonOuterArcStyle.color,
                          strokeWidth: _CreateButtonOuterArcStyle.strokeWidth,
                          inset: _CreateButtonOuterArcStyle.inset,
                          startAngle: _CreateButtonOuterArcStyle.startAngle,
                          sweepAngle: _CreateButtonOuterArcStyle.sweepAngle,
                        ),
                      ),
                    ),
                  ),

                  /// INNER SHADOW
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.45),
                        ],
                        stops: const [0.7, 1],
                      ),
                    ),
                  ),

                  /// LIGHT RING (keep full ring around plus area)
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                    ),
                  ),

                  /// TOP HIGHLIGHT
                  Positioned(
                    top: 10,
                    child: Container(
                      width: 40,
                      height: 14,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withOpacity(0.25),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),

                  /// ICON
                  Transform.translate(
                    offset: Offset(
                      0,
                      math.sin(_glowController.value * 2 * math.pi) * 1.5,
                    ),
                    child: Transform.scale(
                      scale:
                          1 +
                          (math.sin(_glowController.value * 2 * math.pi) *
                              0.05),
                      child: const AaaPlus(),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class AaaPlus extends StatelessWidget {
  const AaaPlus({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: Stack(
        alignment: Alignment.center,
        children: [
          /// 🔥 DIŞ GLOW
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE7C66A).withOpacity(0.6),
                  blurRadius: 10,
                ),
              ],
            ),
          ),

          /// 🔥 DİKEY BAR
          Container(
            width: 6,
            height: 26,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFFFE7A8),
                  Color(0xFFE7C66A),
                  Color(0xFFB9932F),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),

          /// 🔥 YATAY BAR
          Container(
            width: 26,
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFFFE7A8),
                  Color(0xFFE7C66A),
                  Color(0xFFB9932F),
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopArcBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double inset;
  final double startAngle;
  final double sweepAngle;

  const _TopArcBorderPainter({
    required this.color,
    required this.strokeWidth,
    this.inset = 0.0,
    this.startAngle = 0.0,
    this.sweepAngle = -math.pi,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color
      ..isAntiAlias = true
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromLTWH(
      inset + strokeWidth / 2,
      inset + strokeWidth / 2,
      size.width - ((inset + strokeWidth / 2) * 2),
      size.height - ((inset + strokeWidth / 2) * 2),
    );

    canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
  }

  @override
  bool shouldRepaint(covariant _TopArcBorderPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.inset != inset ||
        oldDelegate.startAngle != startAngle ||
        oldDelegate.sweepAngle != sweepAngle;
  }
}
