import 'package:flutter/material.dart';
import 'package:okeyix/core/format.dart';

class GameRulesScreen extends StatelessWidget {
  const GameRulesScreen({super.key});

  static const List<Map<String, dynamic>> _leagues = [
    {
      'id': 'standard',
      'name': 'Acemiler',
      'min_rating': 0,
      'entry_coin': 100,
      'min_rounds': 2,
      'turn_seconds': 60,
      'min_coin': 1000,
      'max_coin': 50000,
      'icon': Icons.circle_outlined,
    },
    {
      'id': 'bronze',
      'name': 'Çıraklar',
      'min_rating': 1000,
      'entry_coin': 250,
      'min_rounds': 2,
      'turn_seconds': 50,
      'min_coin': 50000,
      'max_coin': 250000,
      'icon': Icons.workspace_premium_outlined,
    },
    {
      'id': 'silver',
      'name': 'Kalfalar',
      'min_rating': 1500,
      'entry_coin': 500,
      'min_rounds': 4,
      'turn_seconds': 40,
      'min_coin': 250000,
      'max_coin': 1000000,
      'icon': Icons.military_tech_outlined,
    },
    {
      'id': 'gold',
      'name': 'Ustalar',
      'min_rating': 2000,
      'entry_coin': 1000,
      'min_rounds': 4,
      'turn_seconds': 35,
      'min_coin': 1000000,
      'max_coin': 3000000,
      'icon': Icons.emoji_events_outlined,
    },
    {
      'id': 'elite',
      'name': 'Şampiyonlar',
      'min_rating': 2500,
      'entry_coin': 2500,
      'min_rounds': 6,
      'turn_seconds': 30,
      'min_coin': 3000000,
      'max_coin': 5000000,
      'icon': Icons.auto_awesome,
      'highlight': true,
    },
  ];

  Widget _heroBanner() {
    return Container(
      padding: const EdgeInsets.all(18),
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF193328), Color(0xFF0E1914)],
        ),
        border: Border.all(color: const Color(0x66E7C06A)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x8A000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified, color: Color(0xFFE7C06A), size: 36),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Adil Oyun Garantisi',
                  style: TextStyle(
                    color: Color(0xFFE7C06A),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'OkeyIX tamamen sunucu kontrollü çalışır. '
                  'Taş dağıtımı, sıra yönetimi ve bitiş kontrolleri sunucu tarafında doğrulanır.',
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(IconData icon, String title, String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A2C24), Color(0xFF101A16)],
        ),
        border: Border.all(color: const Color(0x33E7C06A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFE7C06A), size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFFE7C06A),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _leagueCard(Map<String, dynamic> league) {
    final bool highlight = league['highlight'] == true;
    final name = league['name'] as String;
    final minRating = league['min_rating'] as int;
    final minCoin = league['min_coin'] as int;
    final maxCoin = league['max_coin'] as int;
    final icon = league['icon'] as IconData;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: highlight
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE7C06A), Color(0xFFC8973C)],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1A2B24), Color(0xFF111C17)],
              ),
        border: Border.all(
          color: highlight ? const Color(0xFF8F671F) : const Color(0x33E7C06A),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: highlight ? Colors.black : const Color(0xFFE7C06A)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    color: highlight ? Colors.black : Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip('Min Rating', minRating == 0 ? 'Yok' : '$minRating+',
                  highlight: highlight),
              _chip(
                'Coin Aralığı',
                '${Format.coin(minCoin)} - ${Format.coin(maxCoin)}',
                highlight: highlight,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String k, String v, {required bool highlight}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: highlight ? const Color(0x33000000) : const Color(0x22000000),
        border: Border.all(
          color: highlight ? const Color(0x66000000) : const Color(0x33E7C06A),
        ),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            color: highlight ? Colors.black : Colors.white70,
            fontSize: 12,
          ),
          children: [
            TextSpan(
              text: '$k: ',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: highlight ? Colors.black : const Color(0xFFE7C06A),
              ),
            ),
            TextSpan(text: v),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/lobby/lobby.png', fit: BoxFit.cover),
          ),
          Positioned.fill(child: Container(color: const Color(0xCC000000))),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                  child: Row(
                    children: [
                      const Text(
                        'OYUN REHBERİ',
                        style: TextStyle(
                          color: Color(0xFFE7C06A),
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: ListView(
                      children: [
                        _heroBanner(),
                        _infoCard(
                          Icons.casino,
                          'Oyun Kuralları',
                          'OkeyIX klasik Okey kurallarıyla oynanır. '
                              'Amaç taşları seri veya grup halinde dizerek oyunu bitirmektir.',
                        ),
                        _infoCard(
                          Icons.monetization_on,
                          'Coin Sistemi',
                          'Masalara coin ile giriş yapılır. Oyuncuların yatırdığı coinler pot oluşturur. '
                              'Kazanan oyuncu pot ödülünü alır.',
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Ligler',
                          style: TextStyle(
                            color: Color(0xFFE7C06A),
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ..._leagues.map(_leagueCard),
                        const SizedBox(height: 8),
                        _infoCard(
                          Icons.star,
                          'Rating Sistemi',
                          'Kazandıkça rating artar, kaybettikçe azalır. '
                              'Yüksek rating daha üst liglere erişim sağlar.',
                        ),
                        const SizedBox(height: 28),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
