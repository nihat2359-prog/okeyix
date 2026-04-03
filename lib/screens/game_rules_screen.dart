import 'package:flutter/material.dart';

class GameRulesScreen extends StatelessWidget {
  const GameRulesScreen({super.key});

  Widget heroBanner() {
    return Container(
      padding: const EdgeInsets.all(18),
      margin: const EdgeInsets.only(bottom: 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF1F2A30), Color(0xFF11181C)],
        ),
        border: Border.all(color: const Color(0x66E7C06A)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified, color: Color(0xFFE7C06A), size: 38),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  "Adil Oyun Garantisi",
                  style: TextStyle(
                    color: Color(0xFFE7C06A),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  "OkeyIX tamamen hilesiz ve sunucu kontrollü çalışır. "
                  "Tüm taş dağıtımı ve oyun akışı sunucu tarafından yönetilir.",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget infoCard(IconData icon, String title, String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF1A2328), Color(0xFF11181C)],
        ),
        border: Border.all(color: const Color(0x33E7C06A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFE7C06A), size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFFE7C06A),
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white70,
                    height: 1.45,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget leagueCard(String name, int coin, String rating, bool highlight) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: highlight
              ? const LinearGradient(
                  colors: [Color(0xFFE7C06A), Color(0xFFC79B3A)],
                )
              : const LinearGradient(
                  colors: [Color(0xFF1A2328), Color(0xFF11181C)],
                ),
          border: Border.all(color: const Color(0x44E7C06A)),
        ),
        child: Column(
          children: [
            Text(
              name,
              style: TextStyle(
                color: highlight ? Colors.black : Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "$coin",
              style: TextStyle(
                color: highlight ? Colors.black : const Color(0xFFE7C06A),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              "Rating $rating",
              style: TextStyle(
                color: highlight ? Colors.black : Colors.white70,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget leagueSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Ligler",
          style: TextStyle(
            color: Color(0xFFE7C06A),
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),

        Row(
          children: [
            leagueCard("Standart", 100, "-", false),
            leagueCard("Bronz", 250, "1000+", false),
            leagueCard("Gümüş", 500, "1500+", false),
          ],
        ),

        const SizedBox(height: 8),

        Row(
          children: [
            leagueCard("Altın", 1000, "2000+", false),
            leagueCard("Elit", 2500, "2500+", true),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          /// BACKGROUND
          Positioned.fill(
            child: Image.asset(
              "assets/images/lobby/lobby.png",
              fit: BoxFit.cover,
            ),
          ),

          Positioned.fill(child: Container(color: const Color(0xCC000000))),

          SafeArea(
            child: Column(
              children: [
                /// HEADER
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Row(
                    children: [
                      const Text(
                        "OYUN REHBERİ",
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
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: ListView(
                      children: [
                        heroBanner(),

                        infoCard(
                          Icons.casino,
                          "Oyun Kuralları",
                          "OkeyIX klasik Okey kurallarıyla oynanır. "
                              "Amaç taşlarınızı seri veya grup halinde dizerek "
                              "oyunu bitirmektir.",
                        ),

                        infoCard(
                          Icons.monetization_on,
                          "Coin Sistemi",
                          "Masalara coin ile giriş yapılır. "
                              "Oyuncuların yatırdığı coinler pot oluşturur "
                              "ve oyunu kazanan oyuncu potu kazanır.",
                        ),

                        leagueSection(),

                        const SizedBox(height: 18),

                        infoCard(
                          Icons.star,
                          "Rating Sistemi",
                          "Oyuncular kazandıkça rating kazanır, "
                              "kaybettikçe rating kaybeder. "
                              "Daha yüksek rating daha yüksek liglere erişim sağlar.",
                        ),

                        infoCard(
                          Icons.trending_down,
                          "Sistem Kesintisi",
                          "Oyun ekonomisini dengede tutmak için "
                              "her oyunda küçük bir sistem kesintisi uygulanır.",
                        ),

                        const SizedBox(height: 40),
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
