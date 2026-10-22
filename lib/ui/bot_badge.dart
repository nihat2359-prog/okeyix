import 'package:flutter/material.dart';

/// Uses the server's is_bot flag; never infer bot identity from a username.
class BotBadge extends StatelessWidget {
  const BotBadge({super.key});
  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Bot oyuncu',
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(color: const Color(0x332FAAB0),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0x667FB9B8), width: .6)),
      child: const Text('BOT', style: TextStyle(fontSize: 8,
        fontWeight: FontWeight.w800, letterSpacing: .4, color: Color(0xFFB2DCDB))),
    ),
  );
}
