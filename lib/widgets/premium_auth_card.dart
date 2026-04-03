import 'dart:ui';
import 'package:flutter/material.dart';

class PremiumAuthCard extends StatelessWidget {
  final Widget child;

  const PremiumAuthCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(42),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 35, sigmaY: 35),
        child: Container(
          width: 440,
          padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 50),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(42),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xBF000000), Color(0xA6000000)],
            ),
            border: Border.all(color: const Color(0xFFD4AF37), width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x55D4AF37),
                blurRadius: 60,
                spreadRadius: 8,
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
