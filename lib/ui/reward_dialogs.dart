import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:okeyix/core/format.dart';

class WelcomeRewardDialog extends StatefulWidget {
  final int amount;
  const WelcomeRewardDialog({super.key, required this.amount});

  @override
  State<WelcomeRewardDialog> createState() => _WelcomeRewardDialogState();
}

class _WelcomeRewardDialogState extends State<WelcomeRewardDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > size.height;
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(
          horizontal: isLandscape ? 120 : 26,
          vertical: isLandscape ? 10 : 18,
        ),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: isLandscape ? 560 : 640,
          ),
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF203A30), Color(0xFF101A16)],
            ),
            border: Border.all(color: const Color(0xFFE7C66A), width: 1.2),
            boxShadow: const [
              BoxShadow(
                color: Color(0xAA000000),
                blurRadius: 26,
                offset: Offset(0, 12),
              ),
              BoxShadow(
                color: Color(0x66E7C66A),
                blurRadius: 22,
                spreadRadius: -5,
              ),
            ],
          ),
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              return Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: RadialGradient(
                          center: const Alignment(0, -0.45),
                          radius: 0.92,
                          colors: [
                            const Color(0x66FFE7A3).withOpacity(0.38),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  ...List.generate(26, (i) {
                    final t = (_ctrl.value + i * 0.051) % 1;
                    final drift = math.sin((t * math.pi * 2) + i) * 14;
                    final x = 14 + (i * 12) % 280 + drift;
                    final y = 250 - (t * 220);
                    final op = (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0);
                    final iconSize = 8.0 + (i % 3);
                    return Positioned(
                      left: x,
                      top: y,
                      child: Opacity(
                        opacity: op * 0.8,
                        child: Icon(
                          i % 4 == 0
                              ? Icons.auto_awesome_rounded
                              : Icons.monetization_on_rounded,
                          size: iconSize,
                          color: i % 4 == 0
                              ? const Color(0xFFFFE9B3)
                              : const Color(0xFFE7C66A),
                        ),
                      ),
                    );
                  }),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.monetization_on_rounded,
                        color: Color(0xFFEFD28A),
                        size: 50,
                      ),
                      const SizedBox(height: 7),
                      const Text(
                        'Hos Geldin!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Hesabina hos geldin coini yuklendi.\nHemen masaya gecebilirsin.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFD9EBDD),
                          fontSize: 13,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: const Color(0x27284534),
                          border: Border.all(color: const Color(0x88E7C66A)),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'Hediye Coin',
                              style: TextStyle(
                                color: Color(0xFFCFE3D7),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '+ ${Format.coin(widget.amount)}',
                              style: const TextStyle(
                                color: Color(0xFFEFD28A),
                                fontSize: 27,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE7C66A),
                            foregroundColor: const Color(0xFF2A1A04),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Harika, Basla',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class DailyBonusDialog extends StatefulWidget {
  final int amount;
  final VoidCallback onClaim;
  const DailyBonusDialog({
    super.key,
    required this.amount,
    required this.onClaim,
  });

  @override
  State<DailyBonusDialog> createState() => _DailyBonusDialogState();
}

class _DailyBonusDialogState extends State<DailyBonusDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > size.height;
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(
          horizontal: isLandscape ? 140 : 30,
          vertical: isLandscape ? 12 : 18,
        ),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: isLandscape ? 500 : 620,
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF21372F), Color(0xFF101B17)],
            ),
            border: Border.all(color: const Color(0xFFE7C66A), width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0xAA000000),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              return Stack(
                children: [
                  ...List.generate(24, (i) {
                    final t = (_ctrl.value + i * 0.047) % 1;
                    final drift = math.sin((t * math.pi * 2) + i) * 13;
                    final x = 10 + (i * 11) % 270 + drift;
                    final y = 232 - (t * 205);
                    final op = (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0);
                    final s = 7.0 + (i % 3);
                    return Positioned(
                      left: x,
                      top: y,
                      child: Opacity(
                        opacity: op * 0.78,
                        child: Icon(
                          i % 4 == 0
                              ? Icons.auto_awesome_rounded
                              : Icons.monetization_on_rounded,
                          size: s,
                          color: i % 4 == 0
                              ? const Color(0xFFFFE9B3)
                              : const Color(0xFFE7C66A),
                        ),
                      ),
                    );
                  }),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.card_giftcard_rounded,
                        color: Color(0xFFE7C66A),
                        size: 40,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Gunluk Bonus',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Bugunun bonus coinini al ve oyuna devam et.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFD0D8EE),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: const Color(0x1EF2C14E),
                          border: Border.all(color: const Color(0x66E7C66A)),
                        ),
                        child: Text(
                          '+ ${Format.coin(widget.amount)}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFEFD28A),
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: widget.onClaim,
                          icon: const Icon(Icons.redeem_rounded),
                          label: const Text('Al'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2B7B55),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
