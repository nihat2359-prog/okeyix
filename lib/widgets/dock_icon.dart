import 'package:flutter/material.dart';

class AaaDockIcon extends StatefulWidget {
  final IconData? icon;
  final VoidCallback onTap;
  final Widget? child;
  const AaaDockIcon({super.key, this.icon, required this.onTap, this.child});

  @override
  State<AaaDockIcon> createState() => _AaaDockIconState();
}

class _AaaDockIconState extends State<AaaDockIcon>
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
        scale: _pressed ? 0.9 : 1,
        duration: const Duration(milliseconds: 120),

        child: AnimatedBuilder(
          animation: _glowController,
          builder: (context, child) {
            final glow = 0.2 + (_glowController.value * 0.25);

            return Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,

                /// 🔥 SOFT GLOW (MERKEZDEN DAHA ZAYIF)
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE7C66A).withOpacity(glow),
                    blurRadius: 14,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.8),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),

              child: Stack(
                alignment: Alignment.center,
                children: [
                  /// 🔥 CHIP BASE
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F2A1E), Color(0xFF071A12)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: const Color(0xFFE7C66A),
                        width: 2,
                      ),
                    ),
                  ),

                  /// 🔥 INNER SHADOW
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.5),
                        ],
                        stops: const [0.7, 1],
                      ),
                    ),
                  ),

                  /// 🔥 LIGHT RING
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                  ),

                  /// 🔥 TOP HIGHLIGHT
                  Positioned(
                    top: 6,
                    child: Container(
                      width: 22,
                      height: 8,
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
                  widget.child ??
                      Icon(
                        widget.icon,
                        size: 20,
                        color: const Color(0xFFE7C66A),
                      ),

                  /// 🔥 ICON
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class StoreBagIcon extends StatelessWidget {
  const StoreBagIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 26,
      height: 26,
      child: Stack(
        alignment: Alignment.center,
        children: [
          /// 🔥 BAG BODY
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFFFE7A8),
                  Color(0xFFE7C66A),
                  Color(0xFFB9932F),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          /// 🔥 BAG NECK
          Positioned(
            top: 2,
            child: Container(
              width: 10,
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: const Color(0xFF8F6215),
              ),
            ),
          ),

          /// 🔥 COIN STACK (önünde küçük)
          Positioned(
            bottom: 2,
            right: 2,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFE7A8), Color(0xFFE7C66A)],
                ),
              ),
            ),
          ),

          /// 🔥 SPARKLE
          Positioned(
            top: 2,
            right: 2,
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.9),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withOpacity(0.9),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ShimmerIcon extends StatefulWidget {
  final Widget child;

  const ShimmerIcon({super.key, required this.child});

  @override
  State<ShimmerIcon> createState() => _ShimmerIconState();
}

class _ShimmerIconState extends State<ShimmerIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(-1 + _controller.value * 2, 0),
              end: Alignment(1 + _controller.value * 2, 0),
              colors: [
                Colors.transparent,
                Colors.white.withOpacity(0.6),
                Colors.transparent,
              ],
              stops: const [0.4, 0.5, 0.6],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: widget.child,
        );
      },
    );
  }
}

class Pulse extends StatefulWidget {
  final Widget child;

  const Pulse({super.key, required this.child});

  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        final scale = 1 + (_controller.value * 0.06);
        return Transform.scale(scale: scale, child: widget.child);
      },
    );
  }
}
