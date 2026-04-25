import 'package:flutter/material.dart';

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
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE7C66A).withOpacity(glow),
                    blurRadius: 28,
                    spreadRadius: 3,
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
                  /// CHIP BASE
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF245C45), Color(0xFF0E2A20)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: const Color(0xFFE7C66A),
                        width: 3,
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

                  /// LIGHT RING
                  Container(
                    width: 60,
                    height: 60,
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
                  const AaaPlus(),
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
      width: 30,
      height: 30,
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
