import 'package:flutter/material.dart';
import '../core/format.dart';
import 'bot_badge.dart';

class SpectatorTableScores extends StatelessWidget {
  final List<Map<String, dynamic>> players;
  const SpectatorTableScores({super.key, required this.players});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: (MediaQuery.sizeOf(context).width * .30).clamp(150, 210),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xB8101A20), borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0x447E745A)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Row(children: [
          Icon(Icons.emoji_events_outlined, size: 13, color: Color(0xFFE4C88D)),
          SizedBox(width: 6),
          Text('GALİBİYET', style: TextStyle(color: Color(0xFFBDC5C6), fontSize: 9, letterSpacing: 1.2)),
        ]),
        const SizedBox(height: 5),
        for (final p in players.take(2))
          Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [
            Expanded(child: Text(p['username']?.toString() ?? 'Oyuncu', maxLines: 1,
              overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFE7ECE9), fontSize: 11))),
            const SizedBox(width: 8),
            Text(p['wins'] is num ? '${p['wins']}' : '—',
              style: const TextStyle(color: Color(0xFFE4C88D), fontSize: 17, fontWeight: FontWeight.w800)),
          ])),
      ]),
    ),
  );
}

class SpectatorPlayerCard extends StatelessWidget {
  final String username;
  final int? coins;
  final Widget avatar;
  final bool active;
  final bool isBot;
  final double progress;
  final VoidCallback? onTap;
  const SpectatorPlayerCard({super.key, required this.username, required this.coins,
    required this.avatar, required this.active, required this.progress,
    this.onTap, this.isBot = false});

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque, onTap: onTap,
    child: Container(
      width: 210, height: 68,
      padding: const EdgeInsets.fromLTRB(7, 5, 25, 5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xED19262C), Color(0xD90D151B)]),
        borderRadius: BorderRadius.circular(35),
        border: Border.all(color: active ? const Color(0xFFA9C99C) : const Color(0x667D7664)),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: Row(children: [
        SizedBox(width: 56, height: 56, child: Stack(alignment: Alignment.center, children: [
          if (active) Positioned.fill(child: CircularProgressIndicator(value: progress,
            strokeWidth: 2, color: const Color(0xFFE4C88D), backgroundColor: Colors.white12)),
          SizedBox(width: 48, height: 48, child: ClipOval(child: avatar)),
        ])),
        const SizedBox(width: 9),
        Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Expanded(child: Text(username, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFF1F1E9)))),
              if (isBot) ...[const SizedBox(width: 4), const BotBadge()]]),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.monetization_on_outlined, size: 13, color: Color(0xFFE4C88D)),
              const SizedBox(width: 4),
              Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(coins == null ? '—' : Format.balance(coins!), maxLines: 1,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFE4C88D))))),
            ]),
          ])),
      ]),
    ),
  );
}
/// Outside the game's fixed 16:9 viewport, so wide phones have no black side bars.
class SpectatorBackdrop extends StatelessWidget {
  const SpectatorBackdrop({super.key});
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/images/lobby/lobby.png',
    fit: BoxFit.fill,
    width: double.infinity,
    height: double.infinity,
  );
}
