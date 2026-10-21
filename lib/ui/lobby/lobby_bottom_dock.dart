import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'lobby_metal_surface.dart';

class LobbyBottomDock extends StatelessWidget {
  final Widget left;
  final Widget center;
  final Widget right;

  const LobbyBottomDock({
    super.key,
    required this.left,
    required this.center,
    required this.right,
  });

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: const EdgeInsets.only(bottom: 4),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: SizedBox(
        height: 78,
        child: LayoutBuilder(
          builder: (context, bounds) {
            final sides = (bounds.maxWidth - 96).clamp(0.0, bounds.maxWidth);
            return Stack(
              alignment: Alignment.bottomCenter,
              children: [
                const Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _GameRail()),
                  ),
                ),
                Positioned(
                  left: 8,
                  bottom: 0,
                  width: sides * .5,
                  height: 60,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: left,
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 0,
                  width: sides * .5,
                  height: 60,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: right,
                    ),
                  ),
                ),
                Positioned(top: 3, child: center),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class LobbyDockAction extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Widget? child;
  final LobbyDockEmblemKind? emblem;
  final VoidCallback onTap;
  const LobbyDockAction({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.child,
    this.emblem,
  });
  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 48,
            height: 52,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: Center(
                    child:
                        child ??
                        (emblem != null
                            ? LobbyDockEmblem(kind: emblem!)
                            : Icon(
                                icon,
                                size: 23,
                                color: const Color(0xFFE6C990),
                              )),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 12,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Color(0xFFBDCCBD),
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: .2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

enum LobbyDockEmblemKind { store, invite, ranking, social, messages, menu }

class LobbyDockEmblem extends StatelessWidget {
  final LobbyDockEmblemKind kind;
  final bool active;
  const LobbyDockEmblem({super.key, required this.kind, this.active = false});

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: const Size(32, 32),
      painter: _DockEmblemPainter(kind, active),
    ),
  );
}

class _DockEmblemPainter extends CustomPainter {
  final LobbyDockEmblemKind kind;
  final bool active;
  const _DockEmblemPainter(this.kind, this.active);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 32, size.height / 32);
    final symbol = Path();
    switch (kind) {
      case LobbyDockEmblemKind.invite:
        symbol.moveTo(5, 14);
        symbol.lineTo(27, 5);
        symbol.lineTo(20, 27);
        symbol.lineTo(15, 18);
        symbol.close();
        symbol.moveTo(15, 18);
        symbol.lineTo(27, 5);
        symbol.moveTo(15, 18);
        symbol.lineTo(12, 25);
        symbol.lineTo(12, 17);
        break;
      case LobbyDockEmblemKind.menu:
        for (final y in [8.0, 16.0, 24.0]) {
          symbol.moveTo(6, y);
          symbol.lineTo(22, y);
          symbol.moveTo(25, y - 2);
          symbol.lineTo(27, y);
          symbol.lineTo(25, y + 2);
          symbol.lineTo(23, y);
          symbol.close();
        }
        break;
      case LobbyDockEmblemKind.store:
        // Treasure chest with a domed lid, bands and a central clasp.
        symbol.addRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(7, 12, 18, 12),
            const Radius.circular(2),
          ),
        );
        symbol.moveTo(7, 12);
        symbol.cubicTo(7, 5, 25, 5, 25, 12);
        break;
      case LobbyDockEmblemKind.ranking:
        symbol.moveTo(10, 7);
        symbol.lineTo(22, 7);
        symbol.lineTo(21, 15);
        symbol.quadraticBezierTo(16, 22, 11, 15);
        symbol.close();
        symbol.moveTo(10, 9);
        symbol.lineTo(6, 9);
        symbol.quadraticBezierTo(6, 17, 12, 16);
        symbol.moveTo(22, 9);
        symbol.lineTo(26, 9);
        symbol.quadraticBezierTo(26, 17, 20, 16);
        symbol.moveTo(16, 19);
        symbol.lineTo(16, 24);
        symbol.moveTo(11, 25);
        symbol.lineTo(21, 25);
        break;
      case LobbyDockEmblemKind.social:
        symbol.addOval(const Rect.fromLTWH(12, 7, 8, 8));
        symbol.addOval(const Rect.fromLTWH(5, 11, 5, 5));
        symbol.addOval(const Rect.fromLTWH(22, 11, 5, 5));
        symbol.moveTo(9, 25);
        symbol.cubicTo(8, 14, 24, 14, 23, 25);
        symbol.close();
        symbol.moveTo(5, 24);
        symbol.lineTo(4, 24);
        symbol.quadraticBezierTo(3, 18, 8, 18);
        symbol.moveTo(27, 24);
        symbol.lineTo(28, 24);
        symbol.quadraticBezierTo(29, 18, 24, 18);
        break;
      case LobbyDockEmblemKind.messages:
        symbol.addRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(6, 9, 20, 15),
            const Radius.circular(2),
          ),
        );
        symbol.moveTo(7, 10);
        symbol.lineTo(16, 17);
        symbol.lineTo(25, 10);
        symbol.moveTo(7, 23);
        symbol.lineTo(12, 18);
        symbol.moveTo(25, 23);
        symbol.lineTo(20, 18);
        break;
    }
    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.save();
    canvas.translate(0, 1);
    canvas.drawPath(symbol, ink..color = const Color(0xCC061D14));
    canvas.restore();
    canvas.drawPath(
      symbol,
      ink
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFEAC0), Color(0xFFD0A354)],
        ).createShader(const Rect.fromLTWH(5, 6, 22, 20)),
    );
    if (kind == LobbyDockEmblemKind.store) {
      final detail = Paint()
        ..color = const Color(0xFFEED29A)
        ..strokeWidth = 1;
      canvas.drawLine(const Offset(8, 15), const Offset(24, 15), detail);
      canvas.drawLine(const Offset(11, 12), const Offset(11, 23), detail);
      canvas.drawLine(const Offset(21, 12), const Offset(21, 23), detail);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(14, 14, 4, 5),
          const Radius.circular(1),
        ),
        detail,
      );
    }
    if (active) {
      canvas.drawLine(
        const Offset(10, 30),
        const Offset(22, 30),
        Paint()
          ..color = const Color(0xFFFFE6AB)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DockEmblemPainter oldDelegate) =>
      kind != oldDelegate.kind || active != oldDelegate.active;
}

class LobbyDockCreate extends StatefulWidget {
  final VoidCallback onTap;
  const LobbyDockCreate({super.key, required this.onTap});
  @override
  State<LobbyDockCreate> createState() => _LobbyDockCreateState();
}

class _LobbyDockCreateState extends State<LobbyDockCreate> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Masa Aç',
    child: Semantics(
      button: true,
      label: 'Masa Aç',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (value) => setState(() => _pressed = value),
          customBorder: const StadiumBorder(),
          child: SizedBox(
            width: 76,
            height: 74,
            child: Column(
              children: [
                AnimatedScale(
                  scale: _pressed ? .94 : 1,
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 100),
                  child: const RepaintBoundary(
                    child: CustomPaint(
                      size: Size(56, 56),
                      painter: _CreateMedallion(),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const SizedBox(
                  height: 12,
                  child: FittedBox(
                    child: Text(
                      'MASA AÇ',
                      style: TextStyle(
                        color: Color(0xFFEED8AB),
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .8,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Engraved metal rim and enamel face. Static decoration has no ticker.
class _CreateMedallion extends CustomPainter {
  const _CreateMedallion();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final bounds = Offset.zero & size;
    canvas.drawCircle(
      c,
      r - 4,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-.3, -.5),
          colors: [Color(0xC0333A3C), Color(0xD9070B10)],
        ).createShader(bounds),
    );
    canvas.drawCircle(
      c.translate(0, 2),
      r - 3,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = const Color(0xAA030609),
    );
    canvas.drawCircle(
      c,
      r - 3,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFE4CE9A),
            Color(0xFFC99B48),
            Color(0xFF72501F),
            Color(0xFFAF8A49),
          ],
          stops: [0, .4, .76, 1],
        ).createShader(bounds),
    );
    canvas.drawCircle(
      c,
      r - 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .7
        ..color = const Color(0xFFC7AE75),
    );
    canvas.drawCircle(
      c,
      r - 6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFF6C501F),
    );
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r - 7.5),
      math.pi,
      math.pi * .8,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .7
        ..color = const Color(0x55EAD6A5),
    );
    final emblem = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: 6, height: 24),
          const Radius.circular(1.4),
        ),
      )
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: 24, height: 6),
          const Radius.circular(1.4),
        ),
      );
    canvas.save();
    canvas.translate(0, 1.5);
    canvas.drawPath(emblem, Paint()..color = const Color(0xFF080B10));
    canvas.restore();
    canvas.drawPath(
      emblem,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF0C2), Color(0xFFE8C779), Color(0xFFB98A3A)],
        ).createShader(Rect.fromCircle(center: c, radius: 12)),
    );
  }

  @override
  bool shouldRepaint(covariant _CreateMedallion oldDelegate) => false;
}

class _GameRail extends CustomPainter {
  const _GameRail();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(0, 16);
    const LobbyMetalPainter(
      flatBorder: true,
      metal: Color(0xFF8D805F),
      radius: 20,
    ).paint(canvas, Size(size.width, size.height - 16));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GameRail oldDelegate) => false;
}
