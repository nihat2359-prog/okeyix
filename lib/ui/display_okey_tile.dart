import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Shared ivory body, bevel and lettering used by login and lobby tiles.
void paintDisplayOkeyTile(
  Canvas canvas, {
  required String number,
  required Color color,
}) {
  const rect = Rect.fromLTWH(-34, -54, 68, 104);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      rect.shift(const Offset(4, 9)),
      const Radius.circular(8),
    ),
    Paint()
      ..color = const Color(0x99020806)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      rect.shift(const Offset(1, 5)),
      const Radius.circular(7),
    ),
    Paint()..color = const Color(0xCC07110B),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      rect.shift(const Offset(0, 6)),
      const Radius.circular(7),
    ),
    Paint()..color = const Color(0xFF9D814C),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, const Radius.circular(7)),
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFFEC), Color(0xFFDCCCAA)],
      ).createShader(rect),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect.deflate(4), const Radius.circular(4)),
    Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0x998D794F),
  );
  final text = TextPainter(
    text: TextSpan(
      text: number,
      style: TextStyle(
        fontFamily: 'Montserrat',
        fontSize: 46,
        fontWeight: FontWeight.w700,
        letterSpacing: -2,
        color: color,
        shadows: const [
          Shadow(color: Color(0xAAFFFFFF), offset: Offset(0, 1)),
          Shadow(color: Color(0x33000000), offset: Offset(0, -0.6)),
        ],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  text.paint(canvas, Offset(-text.width / 2, -36));
  canvas.drawCircle(const Offset(0, 25), 5, Paint()..color = color);
}

class OpeningOkeyTilesPainter extends CustomPainter {
  const OpeningOkeyTilesPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final unit = math.min(size.width / 310, size.height / 150);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(unit);
    final shadow = Paint()
      ..color = const Color(0x99020906)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawOval(const Rect.fromLTWH(-130, 42, 260, 23), shadow);
    for (var i = 0; i < 3; i++) {
      canvas.save();
      canvas.translate([-69.0, 0.0, 70.0][i], [8.0, -9.0, 10.0][i]);
      canvas.rotate([-.19, .035, .22][i]);
      canvas.scale(1.0, .91);
      canvas.skew(-.035, 0);
      paintDisplayOkeyTile(
        canvas,
        number: i == 2 ? '12' : '13',
        color: const [
          Color(0xFFB62D23),
          Color(0xFF222B26),
          Color(0xFF25528B),
        ][i],
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant OpeningOkeyTilesPainter oldDelegate) => false;
}
