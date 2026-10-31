import 'package:flutter/material.dart';
import 'game_world.dart';

class PistiCareerBoard extends StatelessWidget {
  const PistiCareerBoard({
    super.key,
    required this.leaders,
    required this.matches,
    required this.career,
    this.otherPlayer = false,
  });
  final List leaders, matches;
  final Map? career;
  final bool otherPlayer;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: GameTray(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.emoji_events_outlined, color: worldGold, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'PİŞTİ SIRALAMASI',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              const Divider(color: Color(0x447C7057), height: 22),
              Expanded(
                child: leaders.isEmpty
                    ? const GameEmptyState(
                        title: 'Zirvede yerin hazır',
                        message: 'Tamamlanan maçlarla sıralama oluşur.',
                      )
                    : ListView.separated(
                        itemCount: leaders.length,
                        separatorBuilder: (_, _) =>
                            const Divider(color: Color(0x227C7057)),
                        itemBuilder: (_, i) {
                          final p = leaders[i];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFF354534),
                              foregroundColor: worldGold,
                              child: Text('${i + 1}'),
                            ),
                            title: Text(
                              '${p['users']?['username'] ?? 'Oyuncu'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              '${p['wins']} galibiyet · ${p['pistis']} Pişti',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFFB9C5BC),
                              ),
                            ),
                            trailing: Text(
                              '${p['rating']}',
                              style: const TextStyle(
                                color: worldGold,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: GameTray(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                otherPlayer ? 'OYUNCUNUN KARİYERİ' : 'BENİM PİŞTİ KARİYERİM',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 18,
                runSpacing: 8,
                children: [
                  _stat('${career?['rating'] ?? 1000}', 'RATING'),
                  _stat('${career?['wins'] ?? 0}', 'GALİBİYET'),
                  _stat('${career?['matches'] ?? 0}', 'MAÇ'),
                  _stat('${career?['pistis'] ?? 0}', 'PİŞTİ'),
                ],
              ),
              const Divider(color: Color(0x447C7057), height: 22),
              Expanded(
                child: matches.isEmpty
                    ? const GameEmptyState(
                        title: 'Hikâyen ilk elde başlar',
                        message: 'Bitirdiğin maçlar burada yerini alacak.',
                        icon: Icons.history_rounded,
                      )
                    : ListView.separated(
                        itemCount: matches.length,
                        separatorBuilder: (_, _) =>
                            const Divider(color: Color(0x227C7057)),
                        itemBuilder: (_, i) {
                          final m = matches[i];
                          final date = DateTime.tryParse(
                            '${m['created_at']}',
                          )?.toLocal();
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.style_outlined,
                              color: worldGold,
                            ),
                            title: Text(
                              (m['scores'] as List).join('  –  '),
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              '${m['entry_coin']} Coin · ${date == null ? '' : '${date.day}.${date.month}.${date.year}'}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFFB9C5BC),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
  Widget _stat(String value, String label) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(
          color: worldGold,
          fontSize: 23,
          fontWeight: FontWeight.w700,
        ),
      ),
      Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          color: Color(0xFFB9C5BC),
          letterSpacing: 1,
        ),
      ),
    ],
  );
}
