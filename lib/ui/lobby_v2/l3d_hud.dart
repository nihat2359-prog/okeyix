import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:okeyix/core/format.dart';
import 'package:okeyix/ui/lobby/lobby_avatar.dart';
import 'l3d_theme.dart';

class L3dProfileChip extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final int rating;
  final VoidCallback onTap;
  const L3dProfileChip({super.key, required this.name, required this.avatarUrl, required this.rating, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final level = Format.ratingLevel(rating);
    final progress = Format.ratingLevelProgress(rating).clamp(0.0, 1.0);
    return Semantics(
      button: true,
      label: 'Profilim, seviye $level',
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Stack(clipBehavior: Clip.none, alignment: Alignment.centerLeft, children: [
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 5, bottom: 5),
              child: L3dGlass(
                radius: 99,
                padding: const EdgeInsets.fromLTRB(28, 0, 14, 0),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w900, height: 1.1, shadows: L3d.shadow)),
                    ),
                    Text('Seviye $level',
                        style: const TextStyle(color: L3d.cyan, fontSize: 9.5, fontWeight: FontWeight.w800, height: 1.2)),
                  ],
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 44,
              height: 44,
              child: CustomPaint(
                painter: _Ring(progress),
                child: Padding(
                  padding: const EdgeInsets.all(4.5),
                  child: LobbyAvatar(premium: true, username: name, avatarUrl: avatarUrl, size: 17.5),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Ring extends CustomPainter {
  final double progress;
  const _Ring(this.progress);
  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final r = s.shortestSide / 2 - 1.5;
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF0A1024));
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white.withValues(alpha: .12));
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(colors: [L3d.cyan, L3d.green, L3d.cyan]).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  @override
  bool shouldRepaint(_Ring old) => old.progress != progress;
}

/// Wallet chip: 3D coin, live balance, green "+" to the store.
class L3dCoinChip extends StatelessWidget {
  final Widget value;
  final VoidCallback onAdd;
  const L3dCoinChip({super.key, required this.value, required this.onAdd});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: Stack(clipBehavior: Clip.none, alignment: Alignment.centerLeft, children: [
      Padding(
        padding: const EdgeInsets.only(left: 14, top: 7, bottom: 7),
        child: L3dGlass(
          radius: 99,
          padding: const EdgeInsets.fromLTRB(22, 0, 3, 0),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            ConstrainedBox(constraints: const BoxConstraints(minWidth: 50), child: value),
            const SizedBox(width: 6),
            L3dSlab(
              key: const ValueKey('v2-coin-add'),
              color: const Color(0xFF1FCB7A),
              onTap: onAdd,
              radius: 8,
              depth: 2.5,
              semanticLabel: 'Coin satın al',
              child: const SizedBox(width: 22, height: 19, child: Icon(Icons.add_rounded, size: 17, color: Colors.white, shadows: L3d.shadow)),
            ),
          ]),
        ),
      ),
      // 3D coin with rim and face.
      Container(
        width: 30,
        height: 30,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFFB7791F),
          boxShadow: [BoxShadow(color: Color(0x99000000), blurRadius: 6, offset: Offset(0, 3))],
        ),
        alignment: Alignment.topCenter,
        child: Container(
          width: 30,
          height: 27,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: Alignment(-.35, -.45),
              colors: [Color(0xFFFFF6CC), Color(0xFFFFCB3D), Color(0xFFE39B1B)],
              stops: [0, .5, 1],
            ),
          ),
          child: const Center(child: Icon(Icons.star_rounded, size: 15, color: Color(0xFFB36A0A))),
        ),
      ),
    ]),
  );
}

/// Floating glass dock with colourful 3D tiles and a central PLAY slab that
/// rises above it.
class L3dDock extends StatelessWidget {
  static const double height = 62;
  final List<Widget> left, right;
  final Widget center;
  const L3dDock({super.key, required this.left, required this.center, required this.right});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Stack(clipBehavior: Clip.none, children: [
      const Positioned(left: 0, right: 0, bottom: 0, height: 50, child: L3dGlass(radius: 20, child: SizedBox.expand())),
      Positioned.fill(
        child: LayoutBuilder(builder: (context, box) {
          // The window can briefly report zero width (e.g. entering
          // immersive mode); never hand out negative sizes.
          final centerW = math.min((box.maxWidth * .30).clamp(160.0, 250.0), box.maxWidth);
          final sideW = math.max(0.0, (box.maxWidth - centerW) / 2);
          Widget side(List<Widget> items, Alignment a) => SizedBox(
            width: sideW,
            child: Padding(
              padding: const EdgeInsets.only(top: 12, left: 8, right: 8, bottom: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: a,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  for (var i = 0; i < items.length; i++) ...[if (i > 0) const SizedBox(width: 12), items[i]],
                ]),
              ),
            ),
          );
          return Row(children: [side(left, Alignment.centerLeft), SizedBox(width: centerW, child: center), side(right, Alignment.centerRight)]);
        }),
      ),
    ]),
  );
}

class L3dPlayButton extends StatelessWidget {
  final String label, caption;
  final bool busy;
  final VoidCallback? onTap;
  const L3dPlayButton({super.key, required this.label, required this.caption, required this.onTap, this.busy = false});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
    child: L3dSlab(
      color: const Color(0xFFFF9F1C),
      onTap: busy ? null : onTap,
      radius: 18,
      depth: 6,
      semanticLabel: label,
      child: SizedBox.expand(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              busy
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                  : const Icon(Icons.play_arrow_rounded, size: 34, color: Colors.white, shadows: L3d.shadow),
              const SizedBox(width: 4),
              Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      height: 1,
                      shadows: [Shadow(color: Color(0xFFB45309), offset: Offset(0, 2)), Shadow(color: Color(0x66000000), blurRadius: 6)],
                    )),
                Text(caption, style: const TextStyle(color: Color(0xFFFFF1D6), fontSize: 9.5, fontWeight: FontWeight.w800, height: 1.3)),
              ]),
            ]),
          ),
        ),
      ),
    ),
  );
}
