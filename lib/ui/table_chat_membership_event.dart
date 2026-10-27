import 'package:flutter/material.dart';

/// Identity is captured by the server when membership changes, including leave.
class TableChatMembershipEvent extends StatelessWidget {
  const TableChatMembershipEvent({super.key, required this.event});
  final Map<String, dynamic> event;

  static bool matches(Map<String, dynamic> message) =>
      message['membership_event'] is Map &&
      const ['join', 'leave'].contains(message['membership_event']['action']);

  @override
  Widget build(BuildContext context) {
    final joined = event['action'] == 'join';
    final spectator = event['role'] == 'spectator';
    final name = event['username']?.toString() ?? 'Oyuncu';
    final path = event['avatar_url']?.toString() ?? '';
    final color = joined ? const Color(0xFF83C99A) : const Color(0xFFE08C88);
    final label = spectator
        ? (joined ? 'izlemeye başladı' : 'izlemekten ayrıldı')
        : (joined ? 'masaya katıldı' : 'masadan ayrıldı');
    final fallback = Icon(Icons.person_outline, size: 18, color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 3),
      child: Row(children: [
        ClipOval(child: SizedBox(width: 28, height: 28,
          child: path.isEmpty ? fallback : path.startsWith('http')
              ? Image.network(path, fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => fallback)
              : Image.asset(path, fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => fallback))),
        const SizedBox(width: 7),
        Expanded(child: Text('$name $label',
          style: TextStyle(color: color, fontSize: 11, height: 1.35))),
      ]),
    );
  }
}
