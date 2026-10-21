import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Dark glass and satin titanium. No scrollwork, neon, or ornamental rim layers.
class LobbyMetalSurface extends StatelessWidget {
  final Widget child;
  final Color metal;
  final bool selected, pattern;
  final double radius;
  final double surfaceOpacity;
  final bool flatBorder;
  final EdgeInsetsGeometry padding;
  const LobbyMetalSurface({
    super.key,
    required this.child,
    this.metal = const Color(0xFFB7A17A),
    this.selected = false,
    this.pattern = false,
    this.radius = 17,
    this.surfaceOpacity = 1,
    this.flatBorder = false,
    this.padding = EdgeInsets.zero,
  });
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: LobbyMetalPainter(
        metal: metal,
        selected: selected,
        pattern: pattern,
        radius: radius,
        surfaceOpacity: surfaceOpacity,
        flatBorder: flatBorder,
      ),
      child: Padding(padding: padding, child: child),
    ),
  );
}

class LobbyMetalPainter extends CustomPainter {
  final Color metal;
  final bool selected, pattern;
  final double radius;
  final double surfaceOpacity;
  final bool flatBorder;
  const LobbyMetalPainter({
    this.metal = const Color(0xFFB7A17A),
    this.selected = false,
    this.pattern = false,
    this.radius = 17,
    this.surfaceOpacity = 1,
    this.flatBorder = false,
  });
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = (Offset.zero & size).deflate(1.4),
        r = math.min(radius, size.height * .29);
    RRect shape(double inset) => RRect.fromRectAndRadius(
      rect.deflate(inset),
      Radius.circular(math.max(2, r - inset)),
    );
    final outer = shape(0), face = shape(2.7);
    if (flatBorder) {
      canvas.drawRRect(outer, Paint()..shader = LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [
          const Color(0xFF252B2D).withValues(alpha: .36 * surfaceOpacity),
          const Color(0xFF060D12).withValues(alpha: .40 * surfaceOpacity),
        ],
      ).createShader(rect));
      canvas.drawRRect(outer, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x99727977));
      return;
    }
    // Stroke-only bevels: no opaque full-size undercoat and no difference clip.
    // This also keeps the centre clear on Flutter Web/CanvasKit.
    canvas.drawRRect(
      outer.shift(const Offset(0, 2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0x30000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    final edge = Color.lerp(
      const Color(0xFF727977),
      metal,
      selected ? .62 : .26,
    )!;
    canvas.drawRRect(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(edge, Colors.white, .24)!,
            const Color(0xFF282D2F),
            edge.withValues(alpha: .5),
          ],
          stops: const [0, .6, 1],
        ).createShader(rect),
    );
    canvas.drawRRect(
      shape(1.4),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .75
        ..color = const Color(0x99070B0E),
    );
    canvas.drawRRect(
      face,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF252B2D).withValues(alpha: .36 * surfaceOpacity),
            const Color(0xFF0D1418).withValues(alpha: .32 * surfaceOpacity),
            const Color(0xFF060D12).withValues(alpha: .40 * surfaceOpacity),
          ],
          stops: [0, .36, 1],
        ).createShader(rect),
    );
    canvas.save();
    canvas.clipRRect(face);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-.85, -1),
          radius: 1.5,
          colors: [Color(0x226F797C), Color(0x00101518)],
          stops: [0, .65],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.85, -.8),
          radius: 1.4,
          colors: [
            metal.withValues(alpha: selected ? .16 : .055),
            Colors.transparent,
          ],
        ).createShader(rect),
    );
    if (pattern) {
      final ink = Paint()
        ..color = const Color(0x078C969C)
        ..strokeWidth = .55;
      for (double x = -size.height; x < size.width; x += 17) {
        canvas.drawLine(
          Offset(x, 0),
          Offset(x + size.height, size.height),
          ink,
        );
        canvas.drawLine(
          Offset(x + size.height, 0),
          Offset(x, size.height),
          ink,
        );
      }
    }
    canvas.restore();
    canvas.drawArc(
      Rect.fromLTWH(3.5, 3.5, r * 2, r * 2),
      math.pi,
      math.pi * .5,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = Color.lerp(metal, Colors.white, .4)!.withValues(alpha: .32),
    );
    canvas.drawRRect(
      face,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            edge.withValues(alpha: selected ? .85 : .40),
            const Color(0xFF0D1216),
            const Color(0xFF252B2D),
          ],
          stops: const [0, .5, 1],
        ).createShader(rect),
    );
    // A broad, localized softbox reflection gives volume without a bright outline.
    canvas.save();
    canvas.clipRRect(outer);
    final reflection = Paint()
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          Color.lerp(
            metal,
            Colors.white,
            .5,
          )!.withValues(alpha: selected ? .85 : .42),
          Colors.transparent,
        ],
        stops: const [0, .19, .66],
      ).createShader(Rect.fromLTWH(0, 0, size.width, 8));
    canvas.drawLine(Offset(r, 2), Offset(size.width - r, 2), reflection);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant LobbyMetalPainter old) =>
      metal != old.metal ||
      selected != old.selected ||
      pattern != old.pattern ||
      surfaceOpacity != old.surfaceOpacity ||
      flatBorder != old.flatBorder ||
      radius != old.radius;
}

class LobbyMotto extends StatelessWidget {
  const LobbyMotto({super.key});
  @override
  Widget build(BuildContext context) => const LobbyMetalSurface(
    flatBorder: true,
    radius: 12,
    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    child: Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          'Adil Dağıtım · Gerçek Rekabet',
          style: TextStyle(
            color: Color(0xFFFFD782),
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: .4,
            shadows: [
              Shadow(color: Colors.black, offset: Offset(0, 2), blurRadius: 2),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Finite press feedback, with no repeating ticker.
class LobbyPlatePress extends StatefulWidget {
  final Widget child;
  const LobbyPlatePress({super.key, required this.child});
  @override
  State<LobbyPlatePress> createState() => _LobbyPlatePressState();
}

class _LobbyPlatePressState extends State<LobbyPlatePress> {
  bool pressed = false;
  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => setState(() => pressed = true),
    onPointerUp: (_) => setState(() => pressed = false),
    onPointerCancel: (_) => setState(() => pressed = false),
    child: AnimatedScale(
      scale: pressed ? 0.975 : 1.0,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 95),
      child: widget.child,
    ),
  );
}
