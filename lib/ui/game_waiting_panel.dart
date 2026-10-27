import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Presentation only; the game screen owns seating and countdown timing.
class GameWaitingPanel extends StatelessWidget {
  final int players, capacity, countdown;
  const GameWaitingPanel({super.key, required this.players,
    required this.capacity, required this.countdown});

  @override
  Widget build(BuildContext context) {
    final ready = players >= capacity;
    const gold = Color(0xFFE5C586);
    return IgnorePointer(child: SafeArea(child: LayoutBuilder(
      builder: (context, bounds) => Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.only(top: bounds.maxHeight * .23),
          child: SizedBox(
            width: math.min((MediaQuery.sizeOf(context).width * .30).clamp(196.0, 224.0),
              math.max(0, bounds.maxWidth - 32)),
            height: (bounds.maxHeight * .14).clamp(44.0, 56.0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xF5293835), Color(0xF2162124), Color(0xF20C1319)]),
                border: Border.all(color: const Color(0x99BD9B61)),
                boxShadow: const [BoxShadow(color: Color(0x44000000),
                  blurRadius: 10, offset: Offset(0, 4))]),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: FittedBox(fit: BoxFit.scaleDown,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (ready && countdown > 0) ...[
                      SizedBox(width: 38, height: 38,
                        child: Stack(alignment: Alignment.center, children: [
                          Positioned.fill(child: CircularProgressIndicator(
                            value: (countdown / 5).clamp(0.0, 1.0),
                            strokeWidth: 2, color: gold,
                            backgroundColor: const Color(0x335C735F))),
                          Text('$countdown', key: const ValueKey('waiting-countdown'),
                            style: const TextStyle(color: gold, fontSize: 24,
                              fontWeight: FontWeight.w700)),
                        ])),
                      const SizedBox(width: 14),
                    ],
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(ready ? 'MASA HAZIR' : 'OYUNCU BEKLENİYOR · $players/$capacity',
                        style: const TextStyle(color: gold, fontSize: 9,
                          fontWeight: FontWeight.w600, letterSpacing: 1.2)),
                      const SizedBox(height: 4),
                      Text(ready ? (countdown > 0 ? 'Oyun başlıyor' : 'Taşlar hazırlanıyor')
                        : 'Arkadaşını davet et.',
                        style: const TextStyle(color: Color(0xFFF5EFE2),
                          fontSize: 13, fontWeight: FontWeight.w600)),
                    ]),
                  ])),
              ),
            ),
          ),
        ),
      ),
    )));
  }
}
