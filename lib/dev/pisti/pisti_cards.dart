import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'pisti_model.dart';

const pistiInk = Color(0xff1e2940);
const pistiCoral = Color(0xfff47b70);
const pistiPaper = Color(0xfff6f3ec);
const pistiMuted = Color(0xff9ba9c2);

/// Standard pip arrangement. Lower-half pips face the opposite player.
List<Offset> pistiPipPositions(int rank) {
  if (rank == 1) return const [Offset(.5, .5)];
  if (rank == 2) return const [Offset(.5, .21), Offset(.5, .79)];
  if (rank == 3) {
    return const [Offset(.5, .21), Offset(.5, .5), Offset(.5, .79)];
  }
  if (rank < 4 || rank > 10) return const [];
  final rows = rank <= 5
      ? [.21, .79]
      : rank <= 8
      ? [.21, .5, .79]
      : [.21, .405, .595, .79];
  return [
    for (final x in [.31, .69])
      for (final y in rows) Offset(x, y),
    if (rank == 5 || rank == 9) const Offset(.5, .5),
    if (rank == 7) const Offset(.5, .355),
    if (rank == 8) ...[const Offset(.5, .355), const Offset(.5, .645)],
    if (rank == 10) ...[const Offset(.5, .3075), const Offset(.5, .6925)],
  ];
}

/// Native vector pips and licensed, double-ended SVG court illustrations.
class PistiCardView extends StatelessWidget {
  const PistiCardView({
    super.key,
    this.card,
    this.faceUp = true,
    this.selected = false,
    this.shadow = true,
  });
  final PistiCard? card;
  final bool faceUp, selected, shadow;
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: LayoutBuilder(
      builder: (context, bounds) {
        final court = faceUp && card != null && card!.rank > 10;
        final suit = card == null
            ? ''
            : const ['club', 'diamond', 'heart', 'spade'][card!.suit.index];
        final rank = card == null
            ? ''
            : switch (card!.rank) {
                11 => 'jack',
                12 => 'queen',
                13 => 'king',
                _ => '',
              };
        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _CardPainter(card, faceUp, selected, shadow)),
            if (court)
              Positioned(
                // Keep the illustration clear of both corner rank indices.
                // Its opaque background otherwise clips the Q into a C.
                left: bounds.maxWidth * .24,
                top: bounds.maxHeight * .075,
                width: bounds.maxWidth * .52,
                height: bounds.maxHeight * .85,
                child: ExcludeSemantics(
                  child: SvgPicture.asset(
                    'assets/images/pisti_cards/${suit}_$rank.svg',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

void paintPistiSuit(
  Canvas canvas,
  Offset center,
  double radius,
  PistiSuit suit,
  Color color,
) {
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.scale(radius);
  final paint = Paint()..color = color;
  final path = Path();
  switch (suit) {
    case PistiSuit.diamonds:
      path.moveTo(0, -1.05);
      path.lineTo(.75, 0);
      path.lineTo(0, 1.05);
      path.lineTo(-.75, 0);
      path.close();
    case PistiSuit.hearts:
      path.moveTo(0, .94);
      path.cubicTo(-.32, .53, -1.15, -.12, -.76, -.68);
      path.cubicTo(-.45, -1.08, -.08, -.83, 0, -.55);
      path.cubicTo(.08, -.83, .45, -1.08, .76, -.68);
      path.cubicTo(1.15, -.12, .32, .53, 0, .94);
      path.close();
    case PistiSuit.spades:
      path.moveTo(0, -1.05);
      path.cubicTo(-.28, -.69, -1.09, -.04, -.78, .43);
      path.cubicTo(-.52, .81, -.16, .57, 0, .36);
      path.cubicTo(.16, .57, .52, .81, .78, .43);
      path.cubicTo(1.09, -.04, .28, -.69, 0, -1.05);
      path.close();
      path.moveTo(-.31, 1);
      path.quadraticBezierTo(-.04, .56, 0, .2);
      path.quadraticBezierTo(.04, .56, .31, 1);
      path.close();
    case PistiSuit.clubs:
      canvas.drawCircle(const Offset(0, -.48), .48, paint);
      canvas.drawCircle(const Offset(-.46, .14), .46, paint);
      canvas.drawCircle(const Offset(.46, .14), .46, paint);
      path.moveTo(-.33, 1);
      path.quadraticBezierTo(-.04, .56, 0, .02);
      path.quadraticBezierTo(.04, .56, .33, 1);
      path.close();
  }
  canvas.drawPath(path, paint);
  canvas.restore();
}

void pistiText(
  Canvas canvas,
  String text,
  Offset origin,
  double size,
  Color color, {
  FontWeight weight = FontWeight.w600,
  TextAlign align = TextAlign.left,
  double letterSpacing = 0,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: 'Montserrat',
        fontSize: size,
        color: color,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        height: 1,
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: align,
  )..layout();
  painter.paint(
    canvas,
    origin -
        Offset(
          align == TextAlign.center ? painter.width / 2 : 0,
          painter.height / 2,
        ),
  );
}

class _CardPainter extends CustomPainter {
  const _CardPainter(this.card, this.faceUp, this.selected, this.shadow);
  final PistiCard? card;
  final bool faceUp, selected, shadow;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = size.width * .105;
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    if (shadow) {
      canvas.drawShadow(
        Path()..addRRect(shape),
        const Color(0xbb050a18),
        selected ? 12 : 5,
        true,
      );
    }
    canvas.drawRRect(
      shape,
      Paint()
        ..color = faceUp ? const Color(0xfffdfdfb) : const Color(0xff2d3f60),
    );
    canvas.drawRRect(
      shape.deflate(.6),
      Paint()
        ..color = selected
            ? pistiCoral
            : faceUp
            ? const Color(0xffdeded9)
            : const Color(0xff647897)
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2.2 : .9,
    );
    canvas.save();
    canvas.clipRRect(shape);
    if (!faceUp || card == null) {
      final inset = rect.deflate(size.width * .09);
      canvas.drawRRect(
        RRect.fromRectAndRadius(inset, Radius.circular(radius * .55)),
        Paint()
          ..color = const Color(0xff6e829f)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .65,
      );
      canvas.save();
      canvas.clipRect(inset.deflate(2));
      final lines = Paint()
        ..color = const Color(0x177f97bb)
        ..strokeWidth = .6;
      for (
        double x = -size.height;
        x < size.width + size.height;
        x += size.width * .16
      ) {
        canvas.drawLine(
          Offset(x, 0),
          Offset(x + size.height, size.height),
          lines,
        );
        canvas.drawLine(
          Offset(x, size.height),
          Offset(x + size.height, 0),
          lines,
        );
      }
      canvas.restore();
      canvas.drawCircle(
        rect.center,
        size.width * .24,
        Paint()..color = const Color(0xff2d3f60),
      );
      canvas.drawCircle(
        rect.center,
        size.width * .25,
        Paint()
          ..color = const Color(0xff7d91b2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .8,
      );
      for (var i = 0; i < 3; i++) {
        paintPistiSuit(
          canvas,
          rect.center + Offset((i - 1) * size.width * .13, 0),
          size.width * .065,
          PistiSuit.diamonds,
          i == 1 ? pistiCoral : const Color(0xffb9c8dd),
        );
      }
    } else {
      final c = card!;
      final ink = c.isRed ? const Color(0xffc91d35) : const Color(0xff171b21);
      final cornerX = size.width * .13;
      final cornerY = size.height * .105;
      void corner() {
        pistiText(
          canvas,
          c.label,
          Offset(cornerX, cornerY),
          size.width * (c.rank == 10 ? .18 : .225),
          ink,
          align: TextAlign.center,
        );
        paintPistiSuit(
          canvas,
          Offset(cornerX, size.height * .215),
          size.width * .060,
          c.suit,
          ink,
        );
      }

      corner();
      canvas.save();
      canvas.translate(size.width, size.height);
      canvas.rotate(math.pi);
      corner();
      canvas.restore();
      if (c.rank == 1) {
        paintPistiSuit(canvas, rect.center, size.width * .25, c.suit, ink);
      } else if (c.rank <= 10) {
        for (final position in pistiPipPositions(c.rank)) {
          canvas.save();
          canvas.translate(position.dx * size.width, position.dy * size.height);
          if (position.dy > .5) canvas.rotate(math.pi);
          paintPistiSuit(canvas, Offset.zero, size.width * .098, c.suit, ink);
          canvas.restore();
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CardPainter old) =>
      old.card?.id != card?.id ||
      old.faceUp != faceUp ||
      old.selected != selected ||
      old.shadow != shadow;
}
