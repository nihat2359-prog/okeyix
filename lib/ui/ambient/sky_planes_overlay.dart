import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class SkyPlanesOverlay extends StatefulWidget {
  final double skyHeightFactor;
  final int planeCount;
  final double horizontalInset;

  const SkyPlanesOverlay({
    super.key,
    this.skyHeightFactor = 0.36,
    this.planeCount = 4,
    this.horizontalInset = 0,
  });

  @override
  State<SkyPlanesOverlay> createState() => _SkyPlanesOverlayState();
}

class _SkyPlanesOverlayState extends State<SkyPlanesOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _elapsedSeconds = 0;
  int _lastFrameMicros = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      if (!mounted) return;
      final micros = elapsed.inMicroseconds;
      // 30 FPS cap: ambient efekt için yeterli, CPU/GPU yükünü düşürür.
      if (micros - _lastFrameMicros < 33333) return;
      _lastFrameMicros = micros;
      setState(() {
        _elapsedSeconds = micros / 1000000.0;
      });
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true,
      child: RepaintBoundary(
        child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final skyHeight = constraints.maxHeight * widget.skyHeightFactor;
          final count = widget.planeCount.clamp(2, 8);
          final inset = widget.horizontalInset.clamp(0, width / 3);
          final trackLeft = inset;
          final trackRight = width - inset;
          final trackWidth = (trackRight - trackLeft).clamp(1.0, width);

          return SizedBox.expand(
            child: Stack(
              children: List.generate(count, (i) {
                final lane = i / math.max(1, count - 1);
                // 2 hat kullanırken alt hattı fazla aşağı düşürme.
                final laneFactor = count == 2
                    ? (i == 0 ? 0.10 : 0.34)
                    : (0.09 + (lane * 0.52));
                final laneY = laneFactor * skyHeight;
                final depth = 0.75 + (lane * 0.5);
                final dir = i.isEven ? 1.0 : -1.0;
                final speed = 0.045 + (i * 0.010); // çok daha yavaş, uzaktan süzülme
                final phase = ((_elapsedSeconds * speed) + (i * 0.19)) % 1.0;
                final x = dir > 0
                    ? (trackLeft + trackWidth * phase)
                    : (trackRight - trackWidth * phase);
                final wobble = math.sin((_elapsedSeconds * 0.7 * math.pi) + i) * 3.0;

                final planeSize = 14.5 * depth;
                final glowSize = 34.0 * depth;
                final opacity = (0.30 + (0.16 * depth)).clamp(0.26, 0.55);
                final blink =
                    (0.40 +
                            0.60 *
                                ((math.sin((_elapsedSeconds * 3.2) + (i * 1.7)) + 1) / 2))
                        .clamp(0.0, 1.0);
                final trailOffset = (planeSize * 0.52) * (dir > 0 ? -1 : 1);

                return Positioned(
                  left: x,
                  top: laneY + wobble,
                  child: Opacity(
                    opacity: opacity,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Transform.rotate(
                          angle: dir > 0 ? (math.pi / 2) : (-math.pi / 2),
                          child: Icon(
                            Icons.airplanemode_active_rounded,
                            size: planeSize,
                            color: const Color(0xFFF0F5FF),
                          ),
                        ),
                        Positioned(
                          left: (glowSize * 0.5) + trailOffset - (planeSize * 0.68),
                          top: (glowSize * 0.5) - (planeSize * 0.08),
                          child: Opacity(
                            opacity: 0.22 * blink,
                            child: Container(
                              width: planeSize * 0.46,
                              height: planeSize * 0.16,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                gradient: LinearGradient(
                                  begin: dir > 0
                                      ? Alignment.centerLeft
                                      : Alignment.centerRight,
                                  end: dir > 0
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  colors: const [
                                    Color(0x00FFD27A),
                                    Color(0x99FFD27A),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: (glowSize * 0.5) + trailOffset - (planeSize * 0.14),
                          top: (glowSize * 0.5) - (planeSize * 0.14),
                          child: Opacity(
                            opacity: 0.52 * blink,
                            child: Container(
                              width: planeSize * 0.38,
                              height: planeSize * 0.38,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [Color(0xFFFFD27A), Color(0xFFFF5648)],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFFF7A59).withOpacity(
                                      0.55 * blink,
                                    ),
                                    blurRadius: 6,
                                    spreadRadius: 0.4,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          );
        },
      ),
      ),
    );
  }
}
