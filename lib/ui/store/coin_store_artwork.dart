import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Static compositions made from the original high resolution gold engraving.
/// No animation, blur or network assets. All tiers share the same coin material.
class CoinStoreArtwork extends StatefulWidget {
  const CoinStoreArtwork({super.key, required this.tier});
  final int tier;
  @override
  State<CoinStoreArtwork> createState() => _CoinStoreArtworkState();
}

class _CoinStoreArtworkState extends State<CoinStoreArtwork> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageInfo? _info;
  String? _path;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(CoinStoreArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tier != widget.tier) _resolve();
  }

  void _resolve() {
    final path = widget.tier == 3
        ? 'assets/images/coins/coins_huge.png'
        : 'assets/images/coins/coins_small.png';
    if (_path == path) return;
    if (_listener != null) _stream?.removeListener(_listener!);
    _info?.dispose();
    _info = null;
    _path = path;
    _stream = AssetImage(path).resolve(createLocalImageConfiguration(context));
    _listener = ImageStreamListener((info, _) {
      if (!mounted) {
        info.dispose();
        return;
      }
      setState(() {
        _info?.dispose();
        _info = info;
      });
    });
    _stream!.addListener(_listener!);
  }

  @override
  void dispose() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _info?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _GoldComposition(widget.tier, _info?.image),
      child: const SizedBox.expand(),
    ),
  );
}

class _GoldComposition extends CustomPainter {
  const _GoldComposition(this.tier, this.image);
  final int tier;
  final ui.Image? image;

  // A single engraved coin, not the original stack or its background.
  void coin(
    Canvas canvas,
    double x,
    double y,
    double width, {
    double angle = 0,
  }) {
    final material = image;
    if (material == null) return;
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(angle);
    final h = width * .42;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(2, h * .5),
        width: width * 1.04,
        height: h * .65,
      ),
      Paint()..color = const Color(0x77020000),
    );
    final silhouette = Path()
      ..moveTo(-width / 2, -h * .13)
      ..cubicTo(-width / 2, -h * .65, width / 2, -h * .65, width / 2, -h * .13)
      ..lineTo(width / 2, h * .16)
      ..cubicTo(width / 2, h * .67, -width / 2, h * .67, -width / 2, h * .16)
      ..close();
    canvas.clipPath(silhouette);
    canvas.drawImageRect(
      material,
      const Rect.fromLTWH(285, 346, 242, 99),
      Rect.fromCenter(center: Offset.zero, width: width, height: h),
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();
  }

  void tower(Canvas canvas, double x, double ground, int count, double width) {
    for (var i = 0; i < count; i++) {
      coin(
        canvas,
        x + math.sin(i * 2.1) * 1.6,
        ground - i * width * .13,
        width,
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || image == null) return;
    final scale = math.min(size.width / 240, size.height / 205);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    final glow = const Rect.fromLTWH(-114, -96, 228, 190);
    canvas.drawOval(
      glow,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x38D8A345), Color(0x0DC99D48), Color(0x00D8A345)],
          stops: [0, .55, 1],
        ).createShader(glow),
    );
    canvas.drawOval(
      const Rect.fromLTWH(-99, 49, 198, 32),
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xAA000000), Color(0x00000000)],
        ).createShader(const Rect.fromLTWH(-99, 49, 198, 32)),
    );

    if (tier == 0) {
      coin(canvas, -29, 27, 106, angle: -.10);
      coin(canvas, 24, 43, 110, angle: .11);
      coin(canvas, 5, -3, 112, angle: -.23);
    } else if (tier == 1) {
      tower(canvas, -57, 40, 5, 76);
      tower(canvas, 38, 41, 8, 84);
      tower(canvas, -12, 65, 4, 83);
      coin(canvas, 76, 67, 64, angle: -.28);
    } else if (tier == 2) {
      final random = math.Random(81);
      // Back to front: the mound has a wide base and a raised, irregular crest.
      for (var row = 0; row < 5; row++) {
        final count = 3 + row;
        for (var i = 0; i < count; i++) {
          final x = (i - (count - 1) / 2) * 25;
          final y = -30 + row * 24.0;
          tower(
            canvas,
            x,
            y,
            2 + random.nextInt(3),
            51 + random.nextDouble() * 9,
          );
        }
      }
      coin(canvas, -60, 74, 73, angle: -.31);
      coin(canvas, 52, 81, 78, angle: .24);
      coin(canvas, -1, 85, 67, angle: -.15);
    } else {
      // Keep the detailed carved wood, brass fittings and overflowing gold.
      // Clip away the source's black outer margin using the chest silhouette.
      canvas.save();
      canvas.scale(.27);
      canvas.translate(-512, -465);
      final chest = Path()
        ..moveTo(205, 450)
        ..lineTo(235, 269)
        ..quadraticBezierTo(245, 224, 320, 232)
        ..lineTo(685, 250)
        ..quadraticBezierTo(747, 250, 765, 292)
        ..lineTo(742, 396)
        ..lineTo(784, 453)
        ..lineTo(777, 598)
        ..lineTo(908, 658)
        ..lineTo(930, 717)
        ..lineTo(830, 770)
        ..lineTo(214, 768)
        ..lineTo(86, 722)
        ..lineTo(105, 649)
        ..lineTo(223, 605)
        ..lineTo(205, 450)
        ..close()
        ..addOval(const Rect.fromLTWH(188, 141, 58, 72))
        ..addOval(const Rect.fromLTWH(692, 191, 50, 55))
        ..addOval(const Rect.fromLTWH(816, 259, 63, 43));
      canvas.clipPath(chest);
      canvas.drawImage(
        image!,
        Offset.zero,
        Paint()..filterQuality = FilterQuality.high,
      );
      canvas.restore();
    }

    // A few fixed pinpoints tie all four compositions to the same key light.
    for (final point in [const Offset(-73, -48), const Offset(66, -22)]) {
      final p = Paint()
        ..color = const Color(0xFFF9E8B9)
        ..strokeWidth = .8;
      canvas.drawLine(
        point - const Offset(3, 0),
        point + const Offset(3, 0),
        p,
      );
      canvas.drawLine(
        point - const Offset(0, 5),
        point + const Offset(0, 5),
        p,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GoldComposition oldDelegate) =>
      oldDelegate.tier != tier || oldDelegate.image != image;
}
